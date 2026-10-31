import SwiftUI
import AppKit

// MARK: - 倒数日列表视图

struct CountdownListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var settings = AppSettings.shared
    let initialDate: Date?
    @State private var events: [CountdownEvent] = []
    @State private var showAddView = false
    @State private var editingEvent: CountdownEvent?
    // 行内删除：hover 时显示按钮，确认后才真删
    @State private var hoveredEventID: UUID?
    @State private var eventPendingDelete: CountdownEvent?

    init(initialDate: Date? = nil) {
        self.initialDate = initialDate
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView

            Divider()

            if events.isEmpty {
                emptyView
            } else {
                List {
                    ForEach(events) { event in
                        eventRow(event)
                    }
                }
                .listStyle(.plain)
            }

            Divider()

            addButton
        }
        .frame(width: 300, height: 380)
        .background(colorScheme == .dark ? Color(nsColor: .windowBackgroundColor) : Color.white)
        .onAppear {
            loadEvents()
        }
        .sheet(isPresented: $showAddView) {
            CountdownAddView(initialDate: initialDate) { event in
                CountdownManager.shared.saveEvent(event)
                loadEvents()
            }
        }
        .sheet(item: $editingEvent) { event in
            CountdownAddView(existingEvent: event) { updatedEvent in
                CountdownManager.shared.updateEvent(updatedEvent)
                loadEvents()
            }
        }
        .confirmationDialog(
            LocalizedString.l(
                settings.language,
                en: "Delete countdown \"\(eventPendingDelete?.name ?? "")\"?",
                zh: "删除倒数日“\(eventPendingDelete?.name ?? "")”？",
                ja: "カウントダウン「\(eventPendingDelete?.name ?? "")」を削除しますか？",
                ko: "카운트다운 \"\(eventPendingDelete?.name ?? "")\"을(를) 삭제하시겠습니까?"
            ),
            isPresented: Binding(
                get: { eventPendingDelete != nil },
                set: { if !$0 { eventPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(LocalizedString.l(settings.language, en: "Delete", zh: "删除", ja: "削除", ko: "삭제"), role: .destructive) {
                if let event = eventPendingDelete {
                    CountdownManager.shared.deleteEvent(event)
                    loadEvents()
                }
                eventPendingDelete = nil
            }
            Button(LocalizedString.l(settings.language, en: "Cancel", zh: "取消", ja: "キャンセル", ko: "취소"), role: .cancel) {
                eventPendingDelete = nil
            }
        }
    }

    // MARK: - 标题栏

    private var headerView: some View {
        HStack {
            Text(LocalizedString.countdown("manage"))
                .font(.system(size: 14, weight: .semibold))

            Spacer()

            Text("\(events.count)")
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))

            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - 空视图

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "hourglass")
                .font(.system(size: 36))
                .foregroundStyle(AppTheme.textSecondary(colorScheme).opacity(0.5))

            Text(LocalizedString.countdown("empty"))
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))

            Text(LocalizedString.countdown("empty_hint"))
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.textSecondary(colorScheme).opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 事件行

    private func eventRow(_ event: CountdownEvent) -> some View {
        let days = event.daysRemaining()

        return HStack(spacing: 10) {
            // 剩余天数徽章
            VStack(spacing: 0) {
                Text(badgeNumberText(days: days))
                    .font(.system(size: days.map { abs($0) >= 1000 ? 11 : 14 } ?? 14, weight: .bold, design: .rounded))
                    .foregroundStyle(badgeColor(days: days))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(badgeUnitText(days: days))
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(badgeColor(days: days).opacity(0.8))
            }
            .frame(width: 44, height: 40)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(badgeColor(days: days).opacity(0.12))
            }

            // 信息
            VStack(alignment: .leading, spacing: 2) {
                Text(event.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.textPrimary(colorScheme))

                HStack(spacing: 6) {
                    if event.isLunar {
                        Text(LocalizedString.countdown("lunar"))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(AppTheme.warning)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background {
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(AppTheme.warning.opacity(0.12))
                            }
                    }

                    Text(event.dateString)
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.textSecondary(colorScheme))

                    if !event.note.isEmpty {
                        Text("·")
                            .foregroundStyle(AppTheme.textSecondary(colorScheme).opacity(0.5))
                        Text(event.note)
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.textSecondary(colorScheme))
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            // 编辑按钮
            Button(action: { editingEvent = event }) {
                Image(systemName: "pencil")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
                    .padding(6)
                    .background {
                        Circle()
                            .fill(AppTheme.progressBg(colorScheme))
                    }
            }
            .buttonStyle(.plain)

            if hoveredEventID == event.id {
                Button(action: { eventPendingDelete = event }) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.critical)
                        .padding(6)
                        .background {
                            Circle()
                                .fill(AppTheme.critical.opacity(0.12))
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                hoveredEventID = event.id
            } else if hoveredEventID == event.id {
                hoveredEventID = nil
            }
        }
    }

    private func badgeNumberText(days: Int?) -> String {
        guard let days else { return "--" }
        if days == 0 { return LocalizedString.countdown("today") }
        return "\(abs(days))"
    }

    private func badgeUnitText(days: Int?) -> String {
        guard let days, days != 0 else { return " " }
        return days > 0 ? LocalizedString.countdown("days_left") : LocalizedString.countdown("days_ago")
    }

    private func badgeColor(days: Int?) -> Color {
        guard let days else { return AppTheme.textSecondary(colorScheme) }
        if days < 0 { return AppTheme.textSecondary(colorScheme) }
        if days == 0 { return AppTheme.critical }
        if days <= 7 { return AppTheme.warning }
        return AppTheme.healthy
    }

    // MARK: - 添加按钮

    private var addButton: some View {
        Button(action: { showAddView = true }) {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 14))
                Text(LocalizedString.countdown("add"))
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(AppTheme.healthy)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppTheme.healthy.opacity(0.1))
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func loadEvents() {
        events = CountdownManager.shared.sortedEvents()
    }
}

// MARK: - 添加/编辑倒数日视图

struct CountdownAddView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let existingEvent: CountdownEvent?
    let initialDate: Date?
    let onSave: (CountdownEvent) -> Void

    @State private var name: String = ""
    @State private var isLunar: Bool = false
    @State private var selectedMonth: Int = 1
    @State private var selectedDay: Int = 1
    @State private var isLeapMonth: Bool = false
    @State private var repeatsAnnually: Bool = true
    @State private var targetYearText: String = ""
    @State private var note: String = ""
    @ObservedObject private var settings = AppSettings.shared

    init(
        existingEvent: CountdownEvent? = nil,
        initialDate: Date? = nil,
        onSave: @escaping (CountdownEvent) -> Void
    ) {
        self.existingEvent = existingEvent
        self.initialDate = initialDate
        self.onSave = onSave

        if let event = existingEvent {
            _name = State(initialValue: event.name)
            _isLunar = State(initialValue: event.isLunar)
            _selectedMonth = State(initialValue: event.month)
            _selectedDay = State(initialValue: event.day)
            _isLeapMonth = State(initialValue: event.isLeapMonth)
            _repeatsAnnually = State(initialValue: event.repeatsAnnually)
            _targetYearText = State(initialValue: event.targetYear.map(String.init) ?? "")
            _note = State(initialValue: event.note)
        } else if let initialDate {
            let components = Calendar.current.dateComponents([.year, .month, .day], from: initialDate)
            let year = components.year ?? Calendar.current.component(.year, from: Date())
            _selectedMonth = State(initialValue: components.month ?? 1)
            _selectedDay = State(initialValue: components.day ?? 1)
            _repeatsAnnually = State(initialValue: false)
            _targetYearText = State(initialValue: "\(year)")
        } else {
            let year = Calendar.current.component(.year, from: Date())
            _targetYearText = State(initialValue: "\(year)")
        }
    }

    private var lunarMonthNames: [String] {
        ["正月", "二月", "三月", "四月", "五月", "六月",
         "七月", "八月", "九月", "十月", "冬月", "腊月"]
    }

    private var lunarDayNames: [String] {
        ["初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
         "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
         "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十"]
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView

            Divider()

            ScrollView {
                VStack(spacing: 16) {
                    // 事件名称
                    formField(title: LocalizedString.countdown("event_name")) {
                        AppKitTextField(text: $name, placeholder: LocalizedString.countdown("event_name_placeholder"))
                            .frame(height: 24)
                    }

                    // 日期类型 + 重复
                    formField(title: LocalizedString.countdown("date_type")) {
                        VStack(spacing: 10) {
                            Picker("", selection: $isLunar) {
                                Text(LocalizedString.countdown("solar")).tag(false)
                                Text(LocalizedString.countdown("lunar")).tag(true)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()

                            Toggle(isOn: $repeatsAnnually) {
                                Text(LocalizedString.countdown("repeat_annually"))
                                    .font(.system(size: 12))
                            }
                            .toggleStyle(.switch)
                            .tint(AppTheme.healthy)

                            if isLunar {
                                Toggle(isOn: $isLeapMonth) {
                                    Text(LocalizedString.calendar("leap_month"))
                                        .font(.system(size: 12))
                                }
                                .toggleStyle(.switch)
                                .tint(AppTheme.healthy)
                            }

                            if !repeatsAnnually {
                                HStack(spacing: 8) {
                                    Text(LocalizedString.countdown("year"))
                                        .font(.system(size: 12))
                                    AppKitTextField(text: $targetYearText, placeholder: "2026")
                                        .frame(width: 80, height: 24)
                                    Spacer()
                                }
                            }
                        }
                    }

                    // 月份选择
                    formField(title: LocalizedString.calendar("month")) {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 6) {
                            ForEach(1...12, id: \.self) { month in
                                monthButton(month: month)
                            }
                        }
                    }

                    // 日期选择
                    formField(title: LocalizedString.calendar("date")) {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 6) {
                            ForEach(1...maxDay, id: \.self) { day in
                                dayButton(day: day)
                            }
                        }
                    }

                    // 备注
                    formField(title: LocalizedString.calendar("note")) {
                        AppKitTextField(text: $note, placeholder: LocalizedString.calendar("note_placeholder"))
                            .frame(height: 24)
                    }

                    previewSection
                }
                .padding(16)
            }

            Divider()

            bottomButtons
        }
        .frame(width: 300, height: 480)
        .background(colorScheme == .dark ? Color(nsColor: .windowBackgroundColor) : Color.white)
        .onChange(of: isLunar) { _, _ in
            if selectedDay > maxDay { selectedDay = maxDay }
        }
        .onChange(of: selectedMonth) { _, _ in
            if selectedDay > maxDay { selectedDay = maxDay }
        }
        .onChange(of: targetYearText) { _, _ in
            if selectedDay > maxDay { selectedDay = maxDay }
        }
        .onChange(of: repeatsAnnually) { _, _ in
            if selectedDay > maxDay { selectedDay = maxDay }
        }
    }

    private var headerView: some View {
        HStack {
            Text(existingEvent == nil ? LocalizedString.countdown("add") : LocalizedString.countdown("edit"))
                .font(.system(size: 14, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func formField<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary(colorScheme))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func monthButton(month: Int) -> some View {
        let isSelected = selectedMonth == month
        let title = isLunar ? lunarMonthNames[month - 1] : "\(month)月"

        return Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedMonth = month
            }
        }) {
            Text(title)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .white : AppTheme.textPrimary(colorScheme))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? AppTheme.healthy : AppTheme.progressBg(colorScheme))
                }
        }
        .buttonStyle(.plain)
    }

    private func dayButton(day: Int) -> some View {
        let isSelected = selectedDay == day
        let title = isLunar ? lunarDayNames[day - 1] : "\(day)"

        return Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedDay = day
            }
        }) {
            Text(title)
                .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .white : AppTheme.textPrimary(colorScheme))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isSelected ? AppTheme.healthy : AppTheme.progressBg(colorScheme))
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - 预览

    private var previewSection: some View {
        let event = buildEvent()
        let days = event.daysRemaining()

        return VStack(alignment: .leading, spacing: 6) {
            Text(LocalizedString.calendar("preview"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary(colorScheme))

            HStack(spacing: 8) {
                Image(systemName: "hourglass")
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.healthy)

                VStack(alignment: .leading, spacing: 2) {
                    Text(name.isEmpty ? LocalizedString.calendar("unnamed") : name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.textPrimary(colorScheme))

                    Text(previewText(event: event, days: days))
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.textSecondary(colorScheme))
                }

                Spacer()
            }
            .padding(10)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppTheme.healthy.opacity(0.1))
            }
        }
    }

    private func previewText(event: CountdownEvent, days: Int?) -> String {
        guard let days else { return event.dateString }
        let lang = settings.language
        if days == 0 {
            return event.dateString + " · " + LocalizedString.countdown("today")
        }
        if days < 0 {
            return event.dateString + " · " + LocalizedString.l(lang, en: "\(abs(days)) days ago", zh: "已过 \(abs(days)) 天", ja: "\(abs(days))日前", ko: "\(abs(days))일 전")
        }
        return event.dateString + " · " + LocalizedString.l(lang, en: "\(days) days left", zh: "还有 \(days) 天", ja: "あと\(days)日", ko: "\(days)일 남음")
    }

    // MARK: - 底部按钮

    private var bottomButtons: some View {
        HStack(spacing: 12) {
            Button(action: { dismiss() }) {
                Text(LocalizedString.common("cancel"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(AppTheme.progressBg(colorScheme))
                    }
            }
            .buttonStyle(.plain)

            Button(action: save) {
                Text(LocalizedString.common("save"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isValid ? AppTheme.healthy : AppTheme.healthy.opacity(0.5))
                    }
            }
            .buttonStyle(.plain)
            .disabled(!isValid)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - 计算属性

    private var maxDay: Int {
        if isLunar { return 30 }
        switch selectedMonth {
        case 2:
            guard !repeatsAnnually,
                  let year = Int(targetYearText),
                  let date = Calendar.current.date(from: DateComponents(year: year, month: 2, day: 1)),
                  let range = Calendar.current.range(of: .day, in: .month, for: date) else {
                return 29
            }
            return range.count
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    private var isValid: Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if !repeatsAnnually {
            guard let year = Int(targetYearText.trimmingCharacters(in: .whitespaces)), (1900...2200).contains(year) else { return false }
        }
        return true
    }

    private func buildEvent() -> CountdownEvent {
        CountdownEvent(
            id: existingEvent?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            isLunar: isLunar,
            month: selectedMonth,
            day: selectedDay,
            isLeapMonth: isLunar && isLeapMonth,
            repeatsAnnually: repeatsAnnually,
            targetYear: repeatsAnnually ? nil : Int(targetYearText.trimmingCharacters(in: .whitespaces)),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func save() {
        onSave(buildEvent())
        dismiss()
    }
}
