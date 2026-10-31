import SwiftUI
import Combine

// MARK: - 日历视图

struct CalendarView: View {
    @State private var selectedDate = Date()
    @State private var currentMonth = Date()
    @State private var showBirthdayList = false
    @State private var showCountdownList = false
    @State private var showAddCountdown = false
    @State private var showBirthdayDetail = false
    @State private var selectedDateBirthdays: [Birthday] = []
    @State private var showYearMonthPicker = false
    @State private var countdownRevision = 0
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var router = AppNavigationRouter.shared

    private let calendar = Calendar.current
    private var weekdaySymbols: [String] {
        let lang = settings.language
        switch lang {
        case .english:
            return ["S", "M", "T", "W", "T", "F", "S"]
        case .japanese:
            return ["日", "月", "火", "水", "木", "金", "土"]
        case .korean:
            return ["일", "월", "화", "수", "목", "금", "토"]
        default:
            return ["日", "一", "二", "三", "四", "五", "六"]
        }
    }
    private let holidayService = HolidayService.shared

    var body: some View {
        VStack(spacing: 0) {
            // 顶部日期信息
            dateHeaderView
            Separator()

            // 星期头
            weekdayHeaderView
                .padding(.top, 6)

            // 日历网格
            calendarGridView
                .padding(.horizontal, 8)
                .padding(.vertical, 4)

            Separator()

            // 选中日期详情
            selectedDateDetailView
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .appCardSurface(cornerRadius: 12)
        .sheet(isPresented: $showBirthdayList) {
            BirthdayListView()
        }
        .sheet(isPresented: $showCountdownList, onDismiss: refreshCountdowns) {
            CountdownListView(initialDate: selectedDate)
        }
        .sheet(isPresented: $showAddCountdown) {
            CountdownAddView(initialDate: selectedDate) { event in
                CountdownManager.shared.saveEvent(event)
                refreshCountdowns()
            }
        }
        .sheet(isPresented: $showBirthdayDetail) {
            BirthdayDetailView(birthdays: selectedDateBirthdays, date: selectedDate)
        }
        .sheet(isPresented: $showYearMonthPicker) {
            YearMonthPickerView(currentMonth: $currentMonth, isPresented: $showYearMonthPicker)
        }
        .onReceive(router.$request.compactMap { $0 }) { request in
            guard request.quickAction == .addCountdown else { return }
            selectedDate = Date()
            currentMonth = Date()
            showAddCountdown = true
            router.consumeQuickAction(request.id)
        }
    }

    // MARK: - 顶部日期信息

    private var dateHeaderView: some View {
        HStack {
            // 上一月
            Button(action: { changeMonth(by: -1) }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(previousMonthLabel)

            Spacer()

            // 当前年月 - 可点击选择
            Button(action: { showYearMonthPicker = true }) {
                VStack(spacing: 2) {
                    HStack(spacing: 4) {
                        Text(monthYearText)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppTheme.textPrimary(colorScheme))

                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(AppTheme.textSecondary(colorScheme))
                    }

                    // 农历信息
                    if let lunarInfo = lunarMonthText {
                        Text(lunarInfo)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(AppTheme.textSecondary(colorScheme))
                    }
                }
            }
            .buttonStyle(.plain)
            .help(LocalizedString.calendar("select_year_month_help"))

            Spacer()

            // 生日管理按钮
            Button(action: { showBirthdayList = true }) {
                Image(systemName: "gift")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.warning)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(LocalizedString.calendar("birthday_manage"))
            .help(LocalizedString.calendar("birthday_manage"))

            // 倒数日管理按钮
            Button(action: { showCountdownList = true }) {
                Image(systemName: "hourglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.healthy)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(LocalizedString.countdown("manage"))
            .help(LocalizedString.countdown("manage"))

            // 下一月
            Button(action: { changeMonth(by: 1) }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary(colorScheme))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(nextMonthLabel)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - 星期头

    private var weekdayHeaderView: some View {
        HStack(spacing: 0) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { index, symbol in
                Text(symbol)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(index == 0 || index == 6 ?
                        AppTheme.critical.opacity(0.7) :
                        AppTheme.textSecondary(colorScheme))
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 8)
    }

    // MARK: - 日历网格

    private var calendarGridView: some View {
        _ = countdownRevision
        let days = generateDaysForMonth()

        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 2) {
            ForEach(days, id: \.self) { dayInfo in
                dayCellView(dayInfo: dayInfo)
            }
        }
    }

    // MARK: - 日期单元格

    private func dayCellView(dayInfo: DayInfo) -> some View {
        let isSelected = calendar.isDate(dayInfo.date, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(dayInfo.date)
        let isWeekend = dayInfo.isWeekend
        let lunarDate = LunarCalendar.convertSolarToLunar(date: dayInfo.date)
        let birthdays = BirthdayManager.shared.getBirthdays(for: dayInfo.date)
        let hasBirthday = !birthdays.isEmpty && dayInfo.isCurrentMonth
        let countdowns = CountdownManager.shared.events(on: dayInfo.date)
        let hasCountdown = !countdowns.isEmpty && dayInfo.isCurrentMonth
        let holidayInfo = holidayService.getHolidayInfo(for: dayInfo.date)
        let isHoliday = holidayInfo?.type == .holiday && dayInfo.isCurrentMonth
        let isWorkday = holidayInfo?.type == .workday && dayInfo.isCurrentMonth

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedDate = dayInfo.date
            }
            if hasBirthday {
                selectedDateBirthdays = birthdays
                showBirthdayDetail = true
            }
        } label: {
            ZStack(alignment: .topLeading) {
                // 右上角休/班标记
                ZStack(alignment: .topTrailing) {
                    // 主内容
                    VStack(spacing: 1) {
                        // 公历日期
                        Text("\(dayInfo.day)")
                            .font(.system(size: 12, weight: isSelected ? .bold : .regular))
                            .foregroundStyle(dayNumberColor(isToday: isToday, isSelected: isSelected, isWeekend: isWeekend, isCurrentMonth: dayInfo.isCurrentMonth))
                            .frame(height: 14)

                        // 农历/节日/节气
                        Text(lunarDisplayText(lunarDate: lunarDate, isCurrentMonth: dayInfo.isCurrentMonth))
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(lunarTextColor(lunarDate: lunarDate, isToday: isToday, isSelected: isSelected, isCurrentMonth: dayInfo.isCurrentMonth))
                            .lineLimit(1)

                        if hasBirthday {
                            Text(birthdayDisplayText(birthdays: birthdays))
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(AppTheme.warning)
                                .lineLimit(1)
                        } else if hasCountdown {
                            Text(countdownDisplayText(countdowns))
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(AppTheme.healthy)
                                .lineLimit(1)
                        } else {
                            Text(" ")
                                .font(.system(size: 8))
                        }
                    }
                    .frame(height: 36)
                    .frame(maxWidth: .infinity)

                    // 右上角休/班标记
                    if isHoliday {
                        Text(LocalizedString.calendar("holiday"))
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(1)
                            .background {
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(Color(red: 0.2, green: 0.7, blue: 0.3))
                            }
                            .offset(x: 2, y: -2)
                    } else if isWorkday {
                        Text(LocalizedString.calendar("workday"))
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(1)
                            .background {
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(Color(red: 0.9, green: 0.4, blue: 0.3))
                            }
                            .offset(x: 2, y: -2)
                    }
                }

                // 左上角生日标识
                if hasBirthday {
                    Image(systemName: "gift.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(.white)
                        .padding(2)
                        .background {
                            Circle()
                                .fill(AppTheme.warning)
                        }
                        .offset(x: -2, y: -2)
                }
            }
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(AppTheme.accent.opacity(0.18))
                } else if isToday {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(AppTheme.accent.opacity(0.55), lineWidth: 1)
                } else if hasBirthday {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(AppTheme.warning.opacity(0.12))
                } else if hasCountdown {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(AppTheme.healthy.opacity(0.1))
                } else if isHoliday {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(red: 0.2, green: 0.7, blue: 0.3).opacity(0.1))
                } else if isWorkday {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(red: 0.9, green: 0.4, blue: 0.3).opacity(0.1))
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if hasCountdown {
                    Image(systemName: "hourglass")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundStyle(AppTheme.healthy)
                        .padding(2)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel(
            dayAccessibilityLabel(
                dayInfo.date,
                birthdays: birthdays,
                countdowns: countdowns
            )
        )
    }

    // MARK: - 选中日期详情

    private var selectedDateDetailView: some View {
        let lunarDate = LunarCalendar.convertSolarToLunar(date: selectedDate)
        let birthdays = BirthdayManager.shared.getBirthdays(for: selectedDate)
        let countdowns = CountdownManager.shared.events(on: selectedDate)
        let holidayInfo = holidayService.getHolidayInfo(for: selectedDate)

        return VStack(spacing: 4) {
            // 公历日期
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.icon(colorScheme))

                Text(selectedDateFormatted)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.textPrimary(colorScheme))

                Spacer()

                // 节假日标记
                if let holiday = holidayInfo {
                    HStack(spacing: 4) {
                        Text(holiday.type == .holiday ? LocalizedString.calendar("holiday") : LocalizedString.calendar("workday"))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background {
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(holiday.type == .holiday ?
                                          Color(red: 0.2, green: 0.7, blue: 0.3) :
                                          Color(red: 0.9, green: 0.4, blue: 0.3))
                            }

                        Text(holiday.name)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(holiday.type == .holiday ?
                                           Color(red: 0.2, green: 0.7, blue: 0.3) :
                                           Color(red: 0.9, green: 0.4, blue: 0.3))
                    }
                }

                Button {
                    showAddCountdown = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.healthy)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(LocalizedString.countdown("add_selected_date"))
                .help(LocalizedString.countdown("add_selected_date"))
            }

            // 农历详情
            HStack(spacing: 8) {
                Image(systemName: "moon.stars")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.icon(colorScheme))

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(lunarDate.yearChinese) \(lunarDate.monthChinese)\(lunarDate.dayChinese)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppTheme.textPrimary(colorScheme))

                    HStack(spacing: 6) {
                        Text("\(LocalizedString.calendar("zodiac")): \(lunarDate.zodiac)")
                            .font(.system(size: 10))
                            .foregroundStyle(AppTheme.textSecondary(colorScheme))

                        if let term = lunarDate.solarTerm {
                            Text("\(LocalizedString.calendar("solar_term")): \(term)")
                                .font(.system(size: 10))
                                .foregroundStyle(AppTheme.warning)
                        }

                        if let festival = lunarDate.festival {
                            Text(festival)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(AppTheme.critical)
                        }
                    }
                }

                Spacer()
            }

            // 生日提醒
            if !birthdays.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "gift.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.warning)

                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(birthdays) { birthday in
                            HStack(spacing: 4) {
                                Text(birthday.name)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(AppTheme.warning)

                                if !birthday.note.isEmpty {
                                    Text("(\(birthday.note))")
                                        .font(.system(size: 10))
                                        .foregroundStyle(AppTheme.textSecondary(colorScheme))
                                }
                            }
                        }
                    }

                    Spacer()

                    Text("🎂")
                        .font(.system(size: 14))
                }
                .padding(.top, 2)
            }

            if !countdowns.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "hourglass")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.healthy)

                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(countdowns) { countdown in
                            HStack(spacing: 4) {
                                Text(countdown.name)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(AppTheme.healthy)
                                if !countdown.note.isEmpty {
                                    Text("(\(countdown.note))")
                                        .font(.system(size: 10))
                                        .foregroundStyle(AppTheme.textSecondary(colorScheme))
                                        .lineLimit(1)
                                }
                            }
                        }
                    }

                    Spacer()
                }
                .padding(.top, 2)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - 辅助方法

    private var previousMonthLabel: String {
        LocalizedString.l(
            settings.language,
            en: "Previous month",
            zh: "上个月",
            ja: "前の月",
            ko: "이전 달"
        )
    }

    private var nextMonthLabel: String {
        LocalizedString.l(
            settings.language,
            en: "Next month",
            zh: "下个月",
            ja: "次の月",
            ko: "다음 달"
        )
    }

    private func refreshCountdowns() {
        countdownRevision &+= 1
    }

    private func countdownDisplayText(_ countdowns: [CountdownEvent]) -> String {
        guard let first = countdowns.first else { return "" }
        return countdowns.count == 1
            ? first.name
            : first.name + LocalizedString.calendar("and_more")
    }

    private func dayAccessibilityLabel(
        _ date: Date,
        birthdays: [Birthday],
        countdowns: [CountdownEvent]
    ) -> String {
        var parts = [date.formatted(date: .complete, time: .omitted)]
        if !birthdays.isEmpty {
            let names = birthdays.map(\.name).joined(separator: "、")
            parts.append("\(LocalizedString.calendar("birthday")): \(names)")
        }
        if !countdowns.isEmpty {
            let names = countdowns.map(\.name).joined(separator: "、")
            parts.append("\(LocalizedString.countdown("events")): \(names)")
        }
        return parts.joined(separator: "，")
    }

    private var monthYearText: String {
        let formatter = DateFormatter()
        let lang = settings.language
        switch lang {
        case .english:
            formatter.dateFormat = "MMM yyyy"
        case .japanese:
            formatter.dateFormat = "yyyy年M月"
        case .korean:
            formatter.dateFormat = "yyyy년 M월"
        case .chinese:
            formatter.dateFormat = "yyyy年M月"
        }
        formatter.locale = Locale(identifier: lang.rawValue)
        return formatter.string(from: currentMonth)
    }

    private var lunarMonthText: String? {
        guard let lunarDate = LunarCalendar.getFirstDayOfMonth(
            year: calendar.component(.year, from: currentMonth),
            month: calendar.component(.month, from: currentMonth)
        ) else { return nil }

        return lunarDate.yearChinese + " " + lunarDate.monthChinese
    }

    private var selectedDateFormatted: String {
        let formatter = DateFormatter()
        let lang = settings.language
        switch lang {
        case .english:
            formatter.dateFormat = "EEEE, MMM d, yyyy"
        case .japanese:
            formatter.dateFormat = "yyyy年M月d日 EEEE"
        case .korean:
            formatter.dateFormat = "yyyy년 M월 d일 EEEE"
        case .chinese:
            formatter.dateFormat = "yyyy年M月d日 EEEE"
        }
        formatter.locale = Locale(identifier: lang.rawValue)
        return formatter.string(from: selectedDate)
    }

    private func changeMonth(by value: Int) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if let newDate = calendar.date(byAdding: .month, value: value, to: currentMonth) {
                currentMonth = newDate
            }
        }
    }

    private func generateDaysForMonth() -> [DayInfo] {
        let year = calendar.component(.year, from: currentMonth)
        let month = calendar.component(.month, from: currentMonth)

        let daysInMonth = LunarCalendar.getDaysInMonth(year: year, month: month)
        let firstWeekday = LunarCalendar.getFirstWeekdayOfMonth(year: year, month: month)

        var days: [DayInfo] = []

        // 上月末尾
        if firstWeekday > 1 {
            let prevMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth)!
            let prevDaysInMonth = calendar.range(of: .day, in: .month, for: prevMonth)!.count

            for i in stride(from: firstWeekday - 2, through: 0, by: -1) {
                let day = prevDaysInMonth - i
                var components = calendar.dateComponents([.year, .month], from: prevMonth)
                components.day = day
                if let date = calendar.date(from: components) {
                    days.append(DayInfo(date: date, day: day, isCurrentMonth: false, isWeekend: isWeekend(date: date)))
                }
            }
        }

        // 当月
        for day in 1...daysInMonth {
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = day
            if let date = calendar.date(from: components) {
                days.append(DayInfo(date: date, day: day, isCurrentMonth: true, isWeekend: isWeekend(date: date)))
            }
        }

        // 下月开头
        let remainingDays = 42 - days.count // 6行7列
        if remainingDays > 0 {
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth)!
            for day in 1...remainingDays {
                var components = calendar.dateComponents([.year, .month], from: nextMonth)
                components.day = day
                if let date = calendar.date(from: components) {
                    days.append(DayInfo(date: date, day: day, isCurrentMonth: false, isWeekend: isWeekend(date: date)))
                }
            }
        }

        return days
    }

    private func isWeekend(date: Date) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 || weekday == 7
    }

    private func dayNumberColor(isToday: Bool, isSelected: Bool, isWeekend: Bool, isCurrentMonth: Bool) -> Color {
        if isSelected {
            return AppTheme.accent
        } else if isToday {
            return AppTheme.accent
        } else if !isCurrentMonth {
            return AppTheme.textSecondary(colorScheme).opacity(0.4)
        } else if isWeekend {
            return AppTheme.critical.opacity(0.7)
        } else {
            return AppTheme.textPrimary(colorScheme)
        }
    }

    private func lunarDisplayText(lunarDate: LunarDate, isCurrentMonth: Bool) -> String {
        // 节日
        if let festival = lunarDate.festival, isCurrentMonth {
            return festival
        }

        // 节气
        if let term = lunarDate.solarTerm, isCurrentMonth {
            return term
        }

        // 农历初一显示月名
        if lunarDate.day == 1 {
            return lunarDate.monthChinese
        }

        return lunarDate.dayChinese
    }

    private func lunarTextColor(lunarDate: LunarDate, isToday: Bool, isSelected: Bool, isCurrentMonth: Bool) -> Color {
        // 节日颜色
        if lunarDate.festival != nil && isCurrentMonth {
            return AppTheme.critical
        }

        // 节气颜色
        if lunarDate.solarTerm != nil && isCurrentMonth {
            return AppTheme.warning
        }

        // 初一月名
        if lunarDate.day == 1 && isCurrentMonth {
            return AppTheme.accent
        }

        // 非当月
        if !isCurrentMonth {
            return AppTheme.textSecondary(colorScheme).opacity(0.3)
        }

        // 选中
        if isSelected {
            return AppTheme.accent.opacity(0.82)
        }

        return AppTheme.textSecondary(colorScheme)
    }

    private func birthdayDisplayText(birthdays: [Birthday]) -> String {
        if birthdays.count == 1 {
            return birthdays[0].name
        } else {
            return birthdays[0].name + LocalizedString.calendar("and_more")
        }
    }
}

// MARK: - 日期信息模型

private struct DayInfo: Hashable {
    let date: Date
    let day: Int
    let isCurrentMonth: Bool
    let isWeekend: Bool

    func hash(into hasher: inout Hasher) {
        hasher.combine(date)
    }

    static func == (lhs: DayInfo, rhs: DayInfo) -> Bool {
        lhs.date == rhs.date
    }
}

// MARK: - 年月选择器视图

struct YearMonthPickerView: View {
    @Binding var currentMonth: Date
    @Binding var isPresented: Bool
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var settings = AppSettings.shared

    @State private var selectedYear: Int
    @State private var selectedMonth: Int

    private let calendar = Calendar.current

    private var months: [String] {
        let lang = settings.language
        switch lang {
        case .english:
            return ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        case .japanese:
            return ["1月", "2月", "3月", "4月", "5月", "6月",
                    "7月", "8月", "9月", "10月", "11月", "12月"]
        case .korean:
            return ["1월", "2월", "3월", "4월", "5월", "6월",
                    "7월", "8월", "9월", "10월", "11월", "12월"]
        default:
            return ["1月", "2月", "3月", "4月", "5月", "6月",
                    "7月", "8月", "9月", "10月", "11月", "12月"]
        }
    }

    // 年份范围：前后50年
    private var years: [Int] {
        let currentYear = calendar.component(.year, from: Date())
        return Array((currentYear - 50)...(currentYear + 10))
    }

    init(currentMonth: Binding<Date>, isPresented: Binding<Bool>) {
        self._currentMonth = currentMonth
        self._isPresented = isPresented

        let calendar = Calendar.current
        let year = calendar.component(.year, from: currentMonth.wrappedValue)
        let month = calendar.component(.month, from: currentMonth.wrappedValue)

        self._selectedYear = State(initialValue: year)
        self._selectedMonth = State(initialValue: month)
    }

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            headerView

            Divider()

            // 年份选择
            yearSection

            Divider()

            // 月份选择
            monthSection

            Divider()

            // 底部按钮
            bottomButtons
        }
        .frame(width: 280, height: 360)
        .background(colorScheme == .dark ? Color(nsColor: .windowBackgroundColor) : Color.white)
    }

    // MARK: - 标题栏

    private var headerView: some View {
        HStack {
            Text(LocalizedString.calendar("select_year_month"))
                .font(.system(size: 14, weight: .semibold))

            Spacer()

            // 今天按钮
            Button(action: goToToday) {
                Text(LocalizedString.calendar("today"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(AppTheme.accent.opacity(0.5), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - 年份选择

    private var yearSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedString.calendar("year"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
                .padding(.horizontal, 16)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(years, id: \.self) { year in
                            yearButton(year: year)
                                .id(year)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .onAppear {
                    // 滚动到选中的年份
                    proxy.scrollTo(selectedYear, anchor: .center)
                }
            }
        }
        .padding(.vertical, 10)
    }

    // MARK: - 年份按钮

    private func yearButton(year: Int) -> some View {
        let isSelected = selectedYear == year
        let isCurrentYear = year == calendar.component(.year, from: Date())

        return Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedYear = year
            }
        }) {
            Text("\(year)")
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .white : (isCurrentYear ? AppTheme.accent : AppTheme.textPrimary(colorScheme)))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? AppTheme.accent : (isCurrentYear ? AppTheme.accent.opacity(0.1) : AppTheme.progressBg(colorScheme)))
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - 月份选择

    private var monthSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedString.calendar("month"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary(colorScheme))
                .padding(.horizontal, 16)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
                ForEach(1...12, id: \.self) { month in
                    monthButton(month: month)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 10)
    }

    // MARK: - 月份按钮

    private func monthButton(month: Int) -> some View {
        let isSelected = selectedMonth == month
        let isCurrentMonth = selectedYear == calendar.component(.year, from: Date()) &&
                             month == calendar.component(.month, from: Date())

        return Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedMonth = month
            }
        }) {
            Text(months[month - 1])
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .white : (isCurrentMonth ? AppTheme.accent : AppTheme.textPrimary(colorScheme)))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? AppTheme.accent : (isCurrentMonth ? AppTheme.accent.opacity(0.1) : AppTheme.progressBg(colorScheme)))
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - 底部按钮

    private var bottomButtons: some View {
        HStack(spacing: 12) {
            Button(action: { isPresented = false }) {
                Text(LocalizedString.common("cancel", lang: settings.language))
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

            Button(action: confirmSelection) {
                Text(LocalizedString.common("confirm", lang: settings.language))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(AppTheme.accent)
                    }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - 方法

    private func goToToday() {
        let today = Date()
        selectedYear = calendar.component(.year, from: today)
        selectedMonth = calendar.component(.month, from: today)
    }

    private func confirmSelection() {
        var components = DateComponents()
        components.year = selectedYear
        components.month = selectedMonth
        components.day = 1

        if let newDate = calendar.date(from: components) {
            withAnimation(.easeInOut(duration: 0.2)) {
                currentMonth = newDate
            }
        }

        isPresented = false
    }
}

// MARK: - 预览

struct CalendarView_Previews: PreviewProvider {
    static var previews: some View {
        CalendarView()
            .frame(width: 220, height: 320)
    }
}
