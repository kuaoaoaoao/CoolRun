import Foundation
import Darwin

struct NetworkRouteAnalysis: Equatable, Sendable {
    let gateway: String?
    let interfaceName: String?
}

struct NetworkPingAnalysis: Equatable, Sendable {
    let latencyMilliseconds: Double?
    let packetLossPercent: Double?
}

enum NetworkDiagnosticParser {
    static func parseDefaultRoute(_ text: String) -> NetworkRouteAnalysis {
        var gateway: String?
        var interfaceName: String?
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard parts.count == 2 else { continue }
            switch parts[0] {
            case "gateway": gateway = parts[1]
            case "interface": interfaceName = parts[1]
            default: break
            }
        }
        return NetworkRouteAnalysis(gateway: gateway, interfaceName: interfaceName)
    }

    static func parsePing(_ text: String) -> NetworkPingAnalysis {
        let lossPattern = #"([0-9]+(?:\.[0-9]+)?)% packet loss"#
        let latencyPattern = #"(?:round-trip|round trip).*?=\s*[0-9.]+/([0-9.]+)/[0-9.]+/[0-9.]+\s*ms"#
        let range = NSRange(text.startIndex..<text.endIndex, in: text)

        var loss: Double?
        if let expression = try? NSRegularExpression(pattern: lossPattern),
           let match = expression.firstMatch(in: text, range: range),
           let valueRange = Range(match.range(at: 1), in: text) {
            loss = Double(text[valueRange])
        }

        var latency: Double?
        if let expression = try? NSRegularExpression(pattern: latencyPattern),
           let match = expression.firstMatch(in: text, range: range),
           let valueRange = Range(match.range(at: 1), in: text) {
            latency = Double(text[valueRange])
        }

        return NetworkPingAnalysis(latencyMilliseconds: latency, packetLossPercent: loss)
    }
}

private struct NetworkInterfaceSnapshot: Sendable {
    let name: String?
    let address: String?
    let vpnInterfaces: [String]
}

private struct DNSProbe: Sendable {
    let state: DiagnosticCheckState
    let detail: String
    let durationMilliseconds: Double
}

private struct HTTPSProbe: Sendable {
    let state: DiagnosticCheckState
    let detail: String
    let durationMilliseconds: Double
}

enum NetworkDiagnosticsService {
    static func run(now: Date = Date()) async -> NetworkDiagnosticSummary {
        let interface = interfaceSnapshot()
        guard let localInterface = interface.name else {
            return NetworkDiagnosticSummary(
                id: UUID(),
                timestamp: now,
                severity: .critical,
                interfaceName: nil,
                localAddress: nil,
                gateway: nil,
                vpnActive: !interface.vpnInterfaces.isEmpty,
                latencyMilliseconds: nil,
                packetLossPercent: nil,
                likelyCause: .localInterface,
                checks: [
                    NetworkCheckResult(kind: .interface, state: .failure, detail: "No active interface", durationMilliseconds: nil),
                    NetworkCheckResult(kind: .gateway, state: .skipped, detail: "No active interface", durationMilliseconds: nil),
                    NetworkCheckResult(kind: .dns, state: .skipped, detail: "No active interface", durationMilliseconds: nil),
                    NetworkCheckResult(kind: .ping, state: .skipped, detail: "No active interface", durationMilliseconds: nil),
                    NetworkCheckResult(kind: .https, state: .skipped, detail: "No active interface", durationMilliseconds: nil),
                    vpnCheck(interface.vpnInterfaces)
                ]
            )
        }

        async let routeResult = FixedCommandRunner.run(
            executable: "/sbin/route",
            arguments: ["-n", "get", "default"],
            timeout: 3,
            outputLimit: 64_000
        )
        async let pingResult = FixedCommandRunner.run(
            executable: "/sbin/ping",
            arguments: ["-c", "4", "-W", "1000", "1.1.1.1"],
            timeout: 6,
            outputLimit: 64_000
        )
        async let dnsResult = dnsProbe(host: "www.apple.com")
        async let webResult = httpsProbe()

        let routeCommand = await routeResult
        let pingCommand = await pingResult
        let dns = await dnsResult
        let https = await webResult
        let route = routeCommand.succeeded
            ? NetworkDiagnosticParser.parseDefaultRoute(routeCommand.standardOutput)
            : NetworkRouteAnalysis(gateway: nil, interfaceName: nil)
        let pingText = pingCommand.standardOutput + "\n" + pingCommand.standardError
        let ping = NetworkDiagnosticParser.parsePing(pingText)

        let interfaceCheck = NetworkCheckResult(
            kind: .interface,
            state: .success,
            detail: [route.interfaceName ?? localInterface, interface.address].compactMap { $0 }.joined(separator: " · "),
            durationMilliseconds: nil
        )
        let gatewayCheck = NetworkCheckResult(
            kind: .gateway,
            state: route.gateway == nil ? (routeCommand.timedOut ? .unavailable : .failure) : .success,
            detail: route.gateway ?? nonEmpty(routeCommand.standardError) ?? "No default gateway",
            durationMilliseconds: nil
        )
        let dnsCheck = NetworkCheckResult(
            kind: .dns,
            state: dns.state,
            detail: dns.detail,
            durationMilliseconds: dns.durationMilliseconds
        )
        let pingState: DiagnosticCheckState
        if let loss = ping.packetLossPercent {
            pingState = loss == 0 ? .success : loss < 100 ? .warning : .failure
        } else {
            pingState = pingCommand.timedOut ? .unavailable : .failure
        }
        let pingDetail: String
        if let loss = ping.packetLossPercent {
            pingDetail = String(format: "1.1.1.1 · %.0f%% loss", loss)
        } else {
            pingDetail = nonEmpty(pingCommand.standardError) ?? "No ICMP response"
        }
        let pingCheck = NetworkCheckResult(
            kind: .ping,
            state: pingState,
            detail: pingDetail,
            durationMilliseconds: ping.latencyMilliseconds
        )
        let httpsCheck = NetworkCheckResult(
            kind: .https,
            state: https.state,
            detail: https.detail,
            durationMilliseconds: https.durationMilliseconds
        )
        let checks = [interfaceCheck, gatewayCheck, dnsCheck, pingCheck, httpsCheck, vpnCheck(interface.vpnInterfaces)]

        let likelyCause: NetworkLikelyCause
        if route.gateway == nil {
            likelyCause = .gateway
        } else if dns.state == .failure && pingState != .failure {
            likelyCause = .dns
        } else if https.state == .failure && pingState == .failure {
            likelyCause = .internet
        } else if (ping.packetLossPercent ?? 0) >= 10 || (ping.latencyMilliseconds ?? 0) >= 180 {
            likelyCause = .unstable
        } else if checks.contains(where: { $0.state == .unavailable || $0.state == .failure }) {
            likelyCause = https.state == .success ? .partial : .internet
        } else {
            likelyCause = .none
        }

        let severity: DiagnosticSeverity
        switch likelyCause {
        case .none:
            severity = .healthy
        case .partial:
            severity = .notice
        case .unstable, .dns:
            severity = .warning
        case .localInterface, .gateway, .internet:
            severity = .critical
        }

        return NetworkDiagnosticSummary(
            id: UUID(),
            timestamp: now,
            severity: severity,
            interfaceName: route.interfaceName ?? localInterface,
            localAddress: interface.address,
            gateway: route.gateway,
            vpnActive: !interface.vpnInterfaces.isEmpty,
            latencyMilliseconds: ping.latencyMilliseconds,
            packetLossPercent: ping.packetLossPercent,
            likelyCause: likelyCause,
            checks: checks
        )
    }

    private static func interfaceSnapshot() -> NetworkInterfaceSnapshot {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let interfaces else {
            return NetworkInterfaceSnapshot(name: nil, address: nil, vpnInterfaces: [])
        }
        defer { freeifaddrs(interfaces) }

        var candidates: [(name: String, address: String)] = []
        var vpnNames = Set<String>()
        var cursor: UnsafeMutablePointer<ifaddrs>? = interfaces
        while let interface = cursor {
            defer { cursor = interface.pointee.ifa_next }
            let flags = Int32(interface.pointee.ifa_flags)
            guard flags & IFF_UP == IFF_UP, flags & IFF_LOOPBACK == 0 else { continue }
            let name = String(cString: interface.pointee.ifa_name)
            if name.hasPrefix("utun") || name.hasPrefix("ppp") || name.hasPrefix("ipsec") {
                vpnNames.insert(name)
            }
            guard !name.hasPrefix("utun"), !name.hasPrefix("awdl"), !name.hasPrefix("llw"),
                  !name.hasPrefix("p2p"), !name.hasPrefix("ap"),
                  let address = interface.pointee.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET) else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(
                address,
                socklen_t(address.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            ) == 0 else { continue }
            candidates.append((name, String(cString: host)))
        }

        candidates.sort {
            interfacePriority($0.name) < interfacePriority($1.name)
        }
        return NetworkInterfaceSnapshot(
            name: candidates.first?.name,
            address: candidates.first?.address,
            vpnInterfaces: vpnNames.sorted()
        )
    }

    private static func interfacePriority(_ name: String) -> Int {
        if name == "en0" { return 0 }
        if name.hasPrefix("en") { return 1 }
        if name.hasPrefix("bridge") { return 2 }
        return 3
    }

    private static func dnsProbe(host: String) async -> DNSProbe {
        await Task.detached(priority: .utility) {
            let startedAt = Date()
            var hints = addrinfo()
            hints.ai_family = AF_UNSPEC
            hints.ai_flags = AI_ADDRCONFIG
            var result: UnsafeMutablePointer<addrinfo>?
            let status = getaddrinfo(host, nil, &hints, &result)
            defer {
                if let result { freeaddrinfo(result) }
            }
            let duration = Date().timeIntervalSince(startedAt) * 1_000
            if status == 0 {
                return DNSProbe(state: .success, detail: host, durationMilliseconds: duration)
            }
            return DNSProbe(
                state: .failure,
                detail: String(cString: gai_strerror(status)),
                durationMilliseconds: duration
            )
        }.value
    }

    private static func httpsProbe() async -> HTTPSProbe {
        let startedAt = Date()
        guard let url = URL(string: "https://captive.apple.com/hotspot-detect.html") else {
            return HTTPSProbe(state: .unavailable, detail: "Invalid probe URL", durationMilliseconds: 0)
        }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 5
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let duration = Date().timeIntervalSince(startedAt) * 1_000
            guard let http = response as? HTTPURLResponse else {
                return HTTPSProbe(state: .failure, detail: "No HTTP response", durationMilliseconds: duration)
            }
            return HTTPSProbe(
                state: (200..<400).contains(http.statusCode) ? .success : .failure,
                detail: "HTTP \(http.statusCode)",
                durationMilliseconds: duration
            )
        } catch {
            return HTTPSProbe(
                state: .failure,
                detail: error.localizedDescription,
                durationMilliseconds: Date().timeIntervalSince(startedAt) * 1_000
            )
        }
    }

    private static func vpnCheck(_ names: [String]) -> NetworkCheckResult {
        NetworkCheckResult(
            kind: .vpn,
            state: .success,
            detail: names.isEmpty ? "Inactive" : names.joined(separator: ", "),
            durationMilliseconds: nil
        )
    }

    private static func nonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
