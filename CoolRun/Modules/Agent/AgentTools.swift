import Foundation

// MARK: - 工具装配

/// P0 只注册 L0 只读工具。写入类工具在 P1 接入权限闸门后再注册。
@MainActor
enum AgentTools {
    private static var registered = false

    static func registerAll() {
        guard !registered else { return }
        registered = true

        registerSystemTools()
        registerGoldTools()
        AgentGoldTools.registerAll()
        registerCalendarTools()
        registerEnglishTools()
        registerNotesTools()
        registerClipboardTools()
    }

    // MARK: - 通用格式化

    private static func iso(_ date: Date) -> String {
        date.formatted(.iso8601)
    }

    private static func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .memory)
    }

    private static func percent(_ value: Double) -> Double {
        (value * 100 * 10).rounded() / 10
    }

    // MARK: - 系统

    private static func registerSystemTools() {
        let registry = ToolRegistry.shared

        registry.register(ToolDescriptor(
            name: "system_snapshot",
            summary: "读取当前 Mac 的整体状态：CPU、内存、磁盘、电池、温度、网络速率、开机时长。回答性能类问题前优先调用。",
            permission: .read
        )) { _ in
            let snapshot = await SystemToolSupport.snapshot(includeProcesses: false)
            var payload: [String: JSONValue] = [
                "cpu_usage_percent": .number(percent(snapshot.cpu.usage)),
                "cpu_core_count": .number(Double(snapshot.cpu.coreCount)),
                "memory_used": .string(bytes(snapshot.memory.used)),
                "memory_total": .string(bytes(snapshot.memory.total)),
                "memory_usage_percent": .number(percent(snapshot.memory.usage)),
                "storage_used": .string(bytes(snapshot.storage.used)),
                "storage_total": .string(bytes(snapshot.storage.total)),
                "storage_usage_percent": .number(percent(snapshot.storage.usage)),
                "battery_state": .string(snapshot.battery.state.rawValue),
                "low_power_mode": .bool(snapshot.battery.isLowPowerModeEnabled),
                "uptime_seconds": .number(snapshot.uptime.uptime),
                "uptime_text": .string(snapshot.uptime.compactFormatted),
                "network_download": .string(bytes(snapshot.network.downloadSpeed) + "/s"),
                "network_upload": .string(bytes(snapshot.network.uploadSpeed) + "/s"),
                "process_count": .number(Double(snapshot.processes.totalCount)),
                "updated_at": .string(iso(snapshot.updatedAt)),
                // macOS 的「已用内存」含文件缓存、压缩内存和内核占用，
                // 天然大于「所有进程 phys_footprint 之和」。不写清楚，
                // 模型会把这当成数据矛盾，白白浪费一轮去「质疑采样」。
                "memory_note": .string(
                    "memory_used 是 macOS 口径（含文件缓存、压缩内存、内核占用），"
                        + "不等于所有进程占用之和，两者差得多是正常的。"
                ),
            ]
            if let level = snapshot.battery.level {
                payload["battery_level_percent"] = .number(percent(level))
            }
            if let temperature = snapshot.temperature.cpuTemperature {
                payload["cpu_temperature_celsius"] = .number((temperature * 10).rounded() / 10)
            }
            return .text(JSONValue.object(payload).prettyJSONString())
        }

        registry.register(ToolDescriptor(
            name: "system_processes",
            summary: "列出占用最高的进程，用于定位「谁在吃 CPU / 内存」。",
            parameters: ToolSchema.object(
                properties: [
                    ("limit", ToolSchema.integer("返回条数，默认 10，最大 30", minimum: 1, maximum: 30)),
                    ("sort_by", ToolSchema.string("排序维度", enumValues: ["cpu", "memory"])),
                ]
            ),
            permission: .read
        )) { arguments in
            let limit = min(max(arguments["limit"]?.intValue ?? 10, 1), 30)
            let sortBy = arguments["sort_by"]?.stringValue ?? "cpu"
            let snapshot = await SystemToolSupport.snapshot(includeProcesses: true)

            let sorted = snapshot.processes.processes.sorted { lhs, rhs in
                sortBy == "memory"
                    ? lhs.memoryBytes > rhs.memoryBytes
                    : lhs.cpuUsage > rhs.cpuUsage
            }

            let items = sorted.prefix(limit).map { process -> JSONValue in
                .object([
                    "name": .string(process.name),
                    "pid": .number(Double(process.pid)),
                    "cpu_percent": .number((process.cpuUsage * 100 * 10).rounded() / 10),
                    "memory": .string(bytes(process.memoryBytes)),
                    "instances": .number(Double(process.instanceCount)),
                ])
            }
            // 只给前 N 条时，模型很容易拿这几条相加当「全部占用」，
            // 于是得出「内存前几名加起来才 1GB，和实际 36GB 对不上」这种
            // 看似发现矛盾、其实是读不懂截断的结论。把总量和口径一起给出去。
            let merged = snapshot.processes.processes
            let memoryTotal = merged.reduce(UInt64(0)) { $0 + $1.memoryBytes }
            return .text(JSONValue.object([
                "sort_by": .string(sortBy),
                "total_process_count": .number(Double(snapshot.processes.totalCount)),
                "shown": .number(Double(items.count)),
                "all_processes_memory": .string(bytes(memoryTotal)),
                "note": .string(
                    "只列出前 \(limit) 个（合并后共 \(merged.count) 项，系统进程总数 "
                        + "\(snapshot.processes.totalCount)）。全部进程内存合计 "
                        + "\(bytes(memoryTotal))，比前几项相加大得多 —— "
                        + "要判断内存占用请用这个合计值，不要拿前几项当总量。"
                ),
                "processes": .array(Array(items)),
            ]).prettyJSONString())
        }

        registry.register(ToolDescriptor(
            name: "system_battery",
            summary: "读取电池健康详情：循环次数、健康度、温度、功率、剩余时间。",
            permission: .read
        )) { _ in
            let snapshot = await SystemToolSupport.snapshot(includeProcesses: false)
            var payload: [String: JSONValue] = [
                "state": .string(snapshot.battery.state.rawValue),
                "low_power_mode": .bool(snapshot.battery.isLowPowerModeEnabled),
            ]
            if let level = snapshot.battery.level {
                payload["level_percent"] = .number(percent(level))
            }
            if let health = snapshot.battery.health {
                if let cycles = health.cycleCount { payload["cycle_count"] = .number(Double(cycles)) }
                if let healthPercent = health.healthPercent {
                    payload["health_percent"] = .number((healthPercent * 10).rounded() / 10)
                }
                if let temperature = health.temperatureCelsius {
                    payload["temperature_celsius"] = .number((temperature * 10).rounded() / 10)
                }
                if let wattage = health.wattage {
                    payload["wattage"] = .number((wattage * 10).rounded() / 10)
                }
                if let remaining = health.timeRemainingMinutes {
                    payload["time_remaining_minutes"] = .number(Double(remaining))
                }
            }
            // 缺的字段把原因写出来。不写的话模型只能说「系统没返回」，
            // 用户看到的就是一句没用的「未返回」。
            var notes: [String] = []
            if let health = snapshot.battery.health {
                if health.healthPercent == nil {
                    notes.append("health_percent 缺失：读不到设计容量，算不出健康度。")
                }
                if health.temperatureCelsius == nil {
                    notes.append("temperature_celsius 缺失：这台机型不提供电池温度传感器（CPU 温度在 system_snapshot 的 temperature 里）。")
                }
            } else {
                notes.append("没读到电池健康信息：这台机器可能没有内置电池。")
            }
            if !notes.isEmpty {
                payload["note"] = .string(notes.joined(separator: " "))
            }
            return .text(JSONValue.object(payload).prettyJSONString())
        }

        registry.register(ToolDescriptor(
            name: "system_network",
            summary: "读取网络状态：活动接口数量、主 IP 地址、当前上下行速率。",
            permission: .read
        )) { _ in
            let snapshot = await SystemToolSupport.snapshot(includeProcesses: false)
            return .text(JSONValue.object([
                "active_interfaces": .number(Double(snapshot.network.activeInterfaceCount)),
                "primary_address": .string(snapshot.network.primaryAddress ?? "unknown"),
                "download": .string(bytes(snapshot.network.downloadSpeed) + "/s"),
                "upload": .string(bytes(snapshot.network.uploadSpeed) + "/s"),
            ]).prettyJSONString())
        }
    }

    // MARK: - 金价

    private static func registerGoldTools() {
        let registry = ToolRegistry.shared

        registry.register(ToolDescriptor(
            name: "gold_price",
            summary: "读取当前积存金价格、今日涨跌、昨收与市场开闭市状态。",
            permission: .read
        )) { _ in
            guard let quote = GoldPriceStore.shared.latestQuote else {
                return .text("暂无金价数据。可能尚未刷新或网络不可用，请让用户在金价面板手动刷新。")
            }
            var payload: [String: JSONValue] = [
                "price_cny_per_gram": .number((quote.cnyPerGram * 100).rounded() / 100),
                "market_closed": .bool(quote.isMarketClosed),
                "source": .string(quote.source),
                "updated_at": .string(iso(quote.updatedAt)),
            ]
            if let yesterday = quote.yesterdayPrice {
                payload["previous_close"] = .number((yesterday * 100).rounded() / 100)
            }
            if let change = quote.changeAmount {
                payload["change_amount"] = .number((change * 100).rounded() / 100)
            }
            if let rate = quote.changeRatePercent {
                payload["change_percent"] = .number((rate * 100).rounded() / 100)
            }
            payload["disclaimer"] = .string("仅供参考，不构成投资建议")
            return .text(JSONValue.object(payload).prettyJSONString())
        }

        registry.register(ToolDescriptor(
            name: "gold_history",
            summary: "读取最近若干天的金价历史，按天聚合为开高低收。",
            parameters: ToolSchema.object(properties: [
                ("days", ToolSchema.integer("回溯天数，默认 7，最大 90", minimum: 1, maximum: 90)),
            ]),
            permission: .read
        )) { arguments in
            let days = min(max(arguments["days"]?.intValue ?? 7, 1), 90)
            let since = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
            let records = GoldPriceStore.shared.recordsSince(since)
            guard !records.isEmpty else {
                return .text("最近 \(days) 天没有金价记录。")
            }

            let calendar = Calendar.current
            var buckets: [Date: [Double]] = [:]
            for record in records {
                let day = calendar.startOfDay(for: record.timestamp)
                buckets[day, default: []].append(record.price)
            }

            let daily = buckets.keys.sorted().compactMap { day -> JSONValue? in
                guard let prices = buckets[day], let open = prices.first, let close = prices.last else {
                    return nil
                }
                return .object([
                    "date": .string(day.formatted(.iso8601.year().month().day())),
                    "open": .number((open * 100).rounded() / 100),
                    "close": .number((close * 100).rounded() / 100),
                    "high": .number(((prices.max() ?? close) * 100).rounded() / 100),
                    "low": .number(((prices.min() ?? close) * 100).rounded() / 100),
                    "samples": .number(Double(prices.count)),
                ])
            }
            return .text(JSONValue.object([
                "days": .number(Double(days)),
                "record_count": .number(Double(records.count)),
                "daily": .array(daily),
            ]).prettyJSONString())
        }

        registry.register(ToolDescriptor(
            name: "gold_signals",
            summary: "基于最近记录计算金价简单技术指标：5/10 日均线、区间涨跌、波动率。",
            parameters: ToolSchema.object(properties: [
                ("days", ToolSchema.integer("统计窗口，默认 20，最大 120", minimum: 5, maximum: 120)),
            ]),
            permission: .read
        )) { arguments in
            let days = min(max(arguments["days"]?.intValue ?? 20, 5), 120)
            let since = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
            let prices = GoldPriceStore.shared.recordsSince(since).map(\.price)
            guard prices.count >= 5 else {
                return .text("样本不足（\(prices.count) 条），无法计算技术指标。")
            }

            func movingAverage(_ window: Int) -> Double? {
                guard prices.count >= window else { return nil }
                let slice = prices.suffix(window)
                return slice.reduce(0, +) / Double(window)
            }

            let latest = prices.last ?? 0
            let first = prices.first ?? latest
            let changePercent = first > 0 ? (latest - first) / first * 100 : 0
            let mean = prices.reduce(0, +) / Double(prices.count)
            let variance = prices.reduce(0) { $0 + pow($1 - mean, 2) } / Double(prices.count)
            let volatility = mean > 0 ? sqrt(variance) / mean * 100 : 0

            var payload: [String: JSONValue] = [
                "samples": .number(Double(prices.count)),
                "latest": .number((latest * 100).rounded() / 100),
                "period_high": .number(((prices.max() ?? latest) * 100).rounded() / 100),
                "period_low": .number(((prices.min() ?? latest) * 100).rounded() / 100),
                "change_percent": .number((changePercent * 100).rounded() / 100),
                "volatility_percent": .number((volatility * 100).rounded() / 100),
                "disclaimer": .string("仅供参考，不构成投资建议"),
            ]
            if let ma5 = movingAverage(5) { payload["ma5"] = .number((ma5 * 100).rounded() / 100) }
            if let ma10 = movingAverage(10) { payload["ma10"] = .number((ma10 * 100).rounded() / 100) }
            return .text(JSONValue.object(payload).prettyJSONString())
        }
    }

    // MARK: - 日历

    private static func registerCalendarTools() {
        ToolRegistry.shared.register(ToolDescriptor(
            name: "calendar_upcoming",
            summary: "读取倒数日与生日，返回剩余天数。回答「最近有什么安排」时调用。",
            parameters: ToolSchema.object(properties: [
                ("days", ToolSchema.integer("只看未来多少天内，默认 30，最大 365", minimum: 1, maximum: 365)),
            ]),
            permission: .read
        )) { arguments in
            let window = min(max(arguments["days"]?.intValue ?? 30, 1), 365)
            let now = Date()
            let events = CountdownManager.shared.sortedEvents(from: now).compactMap { event -> JSONValue? in
                guard let remaining = event.daysRemaining(from: now), remaining >= 0, remaining <= window else {
                    return nil
                }
                return .object([
                    "name": .string(event.name),
                    "days_remaining": .number(Double(remaining)),
                    "date": .string(event.isLunar ? "农历 \(event.month)月\(event.day)日" : "\(event.month)月\(event.day)日"),
                    "is_lunar": .bool(event.isLunar),
                    "note": .string(event.note),
                ])
            }

            let birthdays = BirthdayManager.shared.getAllBirthdays().map { birthday -> JSONValue in
                .object([
                    "name": .string(birthday.name),
                    "lunar_date": .string(birthday.lunarDateString),
                    "note": .string(birthday.note),
                ])
            }

            return .text(JSONValue.object([
                "today": .string(now.formatted(.iso8601.year().month().day())),
                "window_days": .number(Double(window)),
                "countdowns": .array(events),
                "birthdays": .array(birthdays),
            ]).prettyJSONString())
        }
    }

    // MARK: - 英语

    private static func registerEnglishTools() {
        ToolRegistry.shared.register(ToolDescriptor(
            name: "english_daily",
            summary: "读取今日英语单词、例句与每日名言。",
            permission: .read
        )) { _ in
            let repository = EnglishContentRepository.shared
            let word = repository.dailyWord()
            let quote = repository.dailyQuote()

            func describe(_ item: EnglishLearningItem) -> JSONValue {
                var payload: [String: JSONValue] = [
                    "title": .string(item.title),
                    "translation": .string(item.translation),
                    "difficulty": .string(item.difficulty.rawValue),
                ]
                if let pronunciation = item.pronunciation { payload["pronunciation"] = .string(pronunciation) }
                if let partOfSpeech = item.partOfSpeech { payload["part_of_speech"] = .string(partOfSpeech) }
                if let example = item.example { payload["example"] = .string(example) }
                if let exampleTranslation = item.exampleTranslation {
                    payload["example_translation"] = .string(exampleTranslation)
                }
                return .object(payload)
            }

            return .text(JSONValue.object([
                "word_of_the_day": describe(word),
                "quote_of_the_day": describe(quote),
            ]).prettyJSONString())
        }
    }

    // MARK: - 笔记

    private static func registerNotesTools() {
        ToolRegistry.shared.register(ToolDescriptor(
            name: "notes_search",
            summary: "在本地笔记中检索，返回标题与正文片段。",
            parameters: ToolSchema.object(
                properties: [
                    ("query", ToolSchema.string("检索词；留空则返回最近的笔记")),
                    ("limit", ToolSchema.integer("返回条数，默认 5，最大 20", minimum: 1, maximum: 20)),
                ]
            ),
            permission: .read
        )) { arguments in
            let query = arguments["query"]?.stringValue ?? ""
            let limit = min(max(arguments["limit"]?.intValue ?? 5, 1), 20)
            let notes = NotesStore.shared.filteredNotes(group: .all, query: query)
            guard !notes.isEmpty else {
                return .text(query.isEmpty ? "还没有任何笔记。" : "没有匹配「\(query)」的笔记。")
            }
            let items = notes.prefix(limit).map { note -> JSONValue in
                let body = note.body.count > 300 ? String(note.body.prefix(300)) + "…" : note.body
                return .object([
                    "title": .string(note.title),
                    "body": .string(body),
                    "pinned": .bool(note.isPinned),
                    "updated_at": .string(iso(note.updatedAt)),
                ])
            }
            return .text(JSONValue.object([
                "query": .string(query),
                "total": .number(Double(notes.count)),
                "notes": .array(Array(items)),
            ]).prettyJSONString())
        }
    }

    // MARK: - 剪贴板

    private static func registerClipboardTools() {
        ToolRegistry.shared.register(ToolDescriptor(
            name: "clipboard_search",
            summary: "检索本地剪贴板历史。注意：内容可能包含隐私，只在用户明确要求时调用。",
            parameters: ToolSchema.object(
                properties: [
                    ("query", ToolSchema.string("检索词")),
                    ("limit", ToolSchema.integer("返回条数，默认 3，最大 10", minimum: 1, maximum: 10)),
                ]
            ),
            permission: .read
        )) { arguments in
            let query = arguments["query"]?.stringValue ?? ""
            guard !query.isEmpty else {
                return .failure("需要提供检索词。剪贴板历史不支持无条件全量导出。")
            }
            let limit = min(max(arguments["limit"]?.intValue ?? 3, 1), 10)
            let entries = ClipboardHistoryStore.shared.filteredEntries(query: query)
            guard !entries.isEmpty else {
                return .text("剪贴板历史里没有匹配「\(query)」的内容。")
            }
            let items = entries.prefix(limit).map { entry -> JSONValue in
                let text = entry.text.count > 200 ? String(entry.text.prefix(200)) + "…" : entry.text
                return .object([
                    "text": .string(text),
                    "copied_at": .string(iso(entry.copiedAt)),
                    "pinned": .bool(entry.isPinned),
                ])
            }
            return .text(JSONValue.object([
                "query": .string(query),
                "total": .number(Double(entries.count)),
                "entries": .array(Array(items)),
            ]).prettyJSONString())
        }
    }
}

// MARK: - 采样辅助

/// SystemSampler 的 CPU 占用需要两次采样求差值，因此共享一个实例并预热。
@MainActor
private enum SystemToolSupport {
    static let sampler = SystemSampler()

    static func snapshot(includeProcesses: Bool) async -> SystemSnapshot {
        // 预热必须与正式采样带同样的 includeProcesses：整机 CPU 和进程 CPU
        // 都是「两次采样求差」，只预热整机的话 ProcessSampler 的上一帧时间戳
        // 还是空的，正式采样出来的进程 cpuUsage 会全是 0（排序随之失效）。
        _ = sampler.sample(includeProcesses: includeProcesses, mergeProcesses: true)
        try? await Task.sleep(for: .milliseconds(320))
        return sampler.sample(includeProcesses: includeProcesses, mergeProcesses: true)
    }
}
