import CryptoKit
import Foundation
import IOKit

// MARK: - 本地加密凭据存储

/// API Key 之类的凭据存在本地加密文件里，不再用钥匙串。
///
/// 为什么不用 Keychain：这个 app 是 ad-hoc 签名分发的，每次重新打包签名都会变，
/// 钥匙串 ACL 认不出新签名，读取时会弹「CoolRun 想要使用您存储在钥匙串中的机密
/// 信息」并要求输入密码 —— 开发期每次重编译都要弹一次，体验很差。
///
/// 现在的方案：文件权限 0600，内容用 AES-GCM 加密，密钥由本机硬件 UUID 派生。
/// 这样文件即使被同步到 iCloud 或塞进备份，拷到别的机器上也解不开。
/// 代价是重装系统或换机器后需要重新填一次 Key —— 本来也应该重新填。
enum SecretStore {
    private nonisolated static let fileName = "secrets.json"

    nonisolated static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("CoolRun", isDirectory: true)
            .appendingPathComponent(fileName)
    }

    // MARK: 对外接口

    nonisolated static func load(_ account: String) -> String? {
        guard let store = readStore(), let encoded = store[account], !encoded.isEmpty else {
            return nil
        }
        guard let plain = decrypt(encoded) else { return nil }
        return plain.isEmpty ? nil : plain
    }

    @discardableResult
    nonisolated static func save(_ value: String, account: String) -> Bool {
        var store = readStore() ?? [:]

        if value.isEmpty {
            store.removeValue(forKey: account)
        } else {
            guard let encoded = encrypt(value) else { return false }
            store[account] = encoded
        }

        return writeStore(store)
    }

    nonisolated static func delete(_ account: String) {
        guard var store = readStore() else { return }
        guard store.removeValue(forKey: account) != nil else { return }
        _ = writeStore(store)
    }

    // MARK: 文件读写

    private nonisolated static func readStore() -> [String: String]? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode([String: String].self, from: data)
    }

    @discardableResult
    private nonisolated static func writeStore(_ store: [String: String]) -> Bool {
        let url = fileURL
        let manager = FileManager.default

        do {
            try manager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            return false
        }

        guard let data = try? JSONEncoder().encode(store) else { return false }

        do {
            try data.write(to: url, options: .atomic)
            // 只有当前用户可读写。
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return true
        } catch {
            return false
        }
    }

    // MARK: 加解密

    /// 密钥 = SHA256(硬件 UUID + 固定盐)，不落盘也不在二进制里。
    private nonisolated static func symmetricKey() -> SymmetricKey? {
        guard let uuid = platformUUID(), !uuid.isEmpty else { return nil }
        let digest = SHA256.hash(data: Data((uuid + ".coolrun.secret.v1").utf8))
        return SymmetricKey(data: digest)
    }

    private nonisolated static func encrypt(_ plain: String) -> String? {
        guard let key = symmetricKey(), let box = try? AES.GCM.seal(Data(plain.utf8), using: key) else {
            return nil
        }
        return box.combined?.base64EncodedString()
    }

    private nonisolated static func decrypt(_ encoded: String) -> String? {
        guard let key = symmetricKey(),
              let data = Data(base64Encoded: encoded),
              let box = try? AES.GCM.SealedBox(combined: data),
              let plain = try? AES.GCM.open(box, using: key)
        else {
            return nil
        }
        return String(data: plain, encoding: .utf8)
    }

    // MARK: 机器标识

    nonisolated static func platformUUID() -> String? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        guard let property = IORegistryEntryCreateCFProperty(
            service,
            "IOPlatformUUID" as CFString,
            kCFAllocatorDefault,
            0
        ) else {
            return nil
        }

        return property.takeRetainedValue() as? String
    }
}
