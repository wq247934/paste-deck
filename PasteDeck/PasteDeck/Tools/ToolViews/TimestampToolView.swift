//
//  TimestampToolView.swift
//  PasteDeck
//
//  时间日期计算工具（uTools 式多分区）：时间戳转换、计算日期差、推算日期、
//  推算工作日、工作天数、日期格式、世界时间、在线秒表。
//  宽容器（独立工具窗口）使用左侧导航，窄容器（上下文面板）使用顶部胶囊导航。
//  计算逻辑全部在 DateMath / WorkdayCalendar，可单元测试。
//

import Combine
import SwiftUI

struct TimestampToolView: View {
    let context: ToolContext

    private enum Section: String, CaseIterable {
        case stamp = "时间戳转换"
        case diff = "计算日期差"
        case forward = "推算日期"
        case workday = "推算工作日"
        case workdays = "工作天数"
        case format = "日期格式"
        case world = "世界时间"
        case stopwatch = "在线秒表"
        case history = "往年今日"
    }

    @State private var section: Section = .stamp
    // 秒表状态提升到容器，切换分区不打断计时。
    @State private var stopwatch = StopwatchModel()

    /// 时区选择：本地 / UTC / 指定时区。
    enum ZoneSelection: Hashable {
        case local
        case utc
        case custom(identifier: String)

        var timeZone: TimeZone {
            switch self {
            case .local: return TimeZone.current
            case .utc: return TimeZone(identifier: "UTC") ?? TimeZone.current
            case .custom(let identifier): return TimeZone(identifier: identifier) ?? TimeZone.current
            }
        }

        var displayName: String {
            switch self {
            case .local: return "本地 \(timeZone.identifier)"
            case .utc: return "UTC"
            case .custom(let identifier): return identifier
            }
        }

        static let commonZones: [ZoneSelection] = [
            .custom(identifier: "Asia/Shanghai"),
            .custom(identifier: "Asia/Tokyo"),
            .custom(identifier: "Asia/Singapore"),
            .custom(identifier: "Europe/London"),
            .custom(identifier: "Europe/Berlin"),
            .custom(identifier: "America/New_York"),
            .custom(identifier: "America/Los_Angeles"),
            .custom(identifier: "Australia/Sydney")
        ]
    }

    init(context: ToolContext) {
        self.context = context
        if let prefill = context.prefilledText,
           TimestampMath.parse(prefill) != nil {
            _section = State(initialValue: .stamp)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let useSideNav = geometry.size.width >= 520
            Group {
                if useSideNav {
                    HStack(spacing: 0) {
                        sideNav
                            .frame(width: 106)
                        Divider()
                            .overlay(Color.primary.opacity(0.08))
                        sectionContent
                    }
                } else {
                    VStack(spacing: 0) {
                        topNav
                        Divider()
                            .overlay(Color.primary.opacity(0.08))
                        sectionContent
                    }
                }
            }
        }
    }

    // MARK: - 导航

    private var sideNav: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Section.allCases, id: \.self) { candidate in
                navRow(candidate)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
    }

    private func navRow(_ candidate: Section) -> some View {
        let isSelected = section == candidate
        return Button {
            section = candidate
        } label: {
            HStack(spacing: 0) {
                Capsule()
                    .fill(isSelected ? Color.accentColor : Color.clear)
                    .frame(width: 3, height: 16)
                Text(candidate.rawValue)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .accentColor : .primary)
                    .padding(.leading, 8)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var topNav: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Section.allCases, id: \.self) { candidate in
                    Button {
                        section = candidate
                    } label: {
                        Text(candidate.rawValue)
                            .font(.system(size: 11, weight: section == candidate ? .semibold : .regular))
                            .foregroundColor(section == candidate ? .white : .primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule().fill(section == candidate ? Color.accentColor : Color.primary.opacity(0.06))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                switch section {
                case .stamp:
                    StampSection(prefilledText: context.prefilledText)
                case .diff:
                    DiffSection()
                case .forward:
                    ForwardSection()
                case .workday:
                    WorkdaySection()
                case .workdays:
                    WorkdaysSection()
                case .format:
                    FormatSection()
                case .world:
                    WorldSection()
                case .stopwatch:
                    StopwatchSection(model: stopwatch)
                case .history:
                    historyPlaceholder
                }
            }
            .padding(14)
        }
    }

    private var historyPlaceholder: some View {
        ToolNoticeBox(title: "往年今日") {
            Text("内置历史事件数据暂未收录，此分区将在后续版本提供。")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - 分区 1：时间戳转换

private struct StampSection: View {
    let prefilledText: String?

    @State private var stampInput: String
    @State private var stampResult: String = ""
    @State private var dateInput: String = ""
    @State private var dateResult: String = ""
    @State private var useMilliseconds = false
    @State private var isRunning = true
    @State private var stampError: String?
    @State private var dateError: String?
    @State private var zone: TimestampToolView.ZoneSelection = .local

    init(prefilledText: String?) {
        self.prefilledText = prefilledText
        _stampInput = State(initialValue: prefilledText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("现在：")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    Text(runningText(now: timeline.date))
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .foregroundColor(.accentColor)
                }
                Spacer()
                controlButton
            }

            conversionRow(
                label: "时间戳：",
                input: $stampInput,
                actionTitle: "转换 →",
                result: stampResult,
                resultPlaceholder: "日期时间"
            ) {
                convertStamp()
            }

            conversionRow(
                label: "日期时间：",
                input: $dateInput,
                actionTitle: "转换 →",
                result: dateResult,
                resultPlaceholder: useMilliseconds ? "毫秒时间戳" : "秒级时间戳"
            ) {
                convertDate()
            }

            HStack(spacing: 16) {
                Toggle("毫秒", isOn: $useMilliseconds)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
                Spacer()
                zoneMenu
            }

            if let stampError {
                inlineError(stampError)
            }
            if let dateError {
                inlineError(dateError)
            }

            ToolNoticeBox(title: "简介") {
                Text("时间戳，是从 1970 年 1 月 1 日（UTC/GMT 的午夜）开始所经过的秒数（不考虑闰秒），用于表示一个时间点。这个工具能够在时间戳和可读的日期时间之间快速转换，同时也支持反向转换。")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var controlButton: some View {
        Button {
            isRunning.toggle()
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(isRunning ? .red : .green)
                    .frame(width: 7, height: 7)
                Text(isRunning ? "停止" : "继续")
                    .font(.system(size: 11, weight: .medium))
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().stroke(Color.primary.opacity(0.15), lineWidth: 1))
    }

    private var zoneMenu: some View {
        Menu {
            Button("本地时区（\(TimeZone.current.identifier)）") { zone = .local }
            Button("UTC") { zone = .utc }
            Divider()
            ForEach(TimestampToolView.ZoneSelection.commonZones, id: \.self) { candidate in
                Button(candidate.displayName) { zone = candidate }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "globe")
                    .font(.system(size: 10))
                Text(zone.displayName)
                    .font(.system(size: 11))
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
            }
            .foregroundColor(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func runningText(now: Date) -> String {
        guard isRunning else { return stampResult.isEmpty ? String(TimestampMath.unixSeconds(of: now)) : stampResult }
        return String(TimestampMath.unixSeconds(of: now))
    }

    private func convertStamp() {
        stampError = nil
        let trimmed = stampInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = TimestampMath.parse(trimmed) else {
            stampError = "无法识别的时间戳：支持 9–10 位秒级或 12–13 位毫秒级纯数字"
            return
        }
        let date = TimestampMath.date(from: parsed)
        stampResult = TimestampMath.formattedText(date, timeZone: zone.timeZone)
    }

    private func convertDate() {
        dateError = nil
        guard let date = DateMath.parseDateTime(dateInput) else {
            dateError = "日期格式无效：请输入 yyyy-MM-dd 或 yyyy-MM-dd HH:mm:ss"
            return
        }
        let value = useMilliseconds ? TimestampMath.unixMilliseconds(of: date) : TimestampMath.unixSeconds(of: date)
        dateResult = String(value)
    }

    @ViewBuilder
    private func conversionRow(
        label: String,
        input: Binding<String>,
        actionTitle: String,
        result: String,
        resultPlaceholder: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            TextField("", text: input)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
                .frame(minWidth: 110, idealWidth: 130)

            Button(actionTitle) {
                action()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor, lineWidth: 1))

            ToolResultBox(text: result, placeholder: resultPlaceholder)
                .frame(maxWidth: .infinity)
        }
    }
}

/// 结果展示框（不可编辑的输入框样式）。
struct ToolResultBox: View {
    let text: String
    var placeholder: String = ""

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(Color.primary.opacity(0.18), lineWidth: 1)
            Text(text.isEmpty ? placeholder : text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(text.isEmpty ? .secondary.opacity(0.6) : .primary)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 7)
        }
        .frame(height: 24)
    }
}

// MARK: - 分区 2：计算日期差

private struct DiffSection: View {
    @State private var startInput = ""
    @State private var endInput = ""
    @State private var includeTime = false
    @State private var result: String?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("计算日期差")

            dateField(label: "日期", text: $startInput)
            dateField(label: "距离", text: $endInput)

            HStack(spacing: 14) {
                ToolActionButton(title: "相差（计算）") { calculate() }
                Toggle("时分秒", isOn: $includeTime)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
                Spacer()
            }

            if let error {
                inlineError(error)
            }

            if let result {
                Text(result)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .textSelection(.enabled)
            }

            ToolNoticeBox(title: "工具说明") {
                Text("本工具用于计算两个日期之间相隔的天数；勾选\"时分秒\"后可按 yyyy-MM-dd HH:mm:ss 计算出精确的时、分、秒差。")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func calculate() {
        error = nil
        result = nil
        guard let start = includeTime ? DateMath.parseDateTime(startInput) : DateMath.parseDate(startInput) else {
            error = "起始日期无效：请输入 yyyy-MM-dd\(includeTime ? " HH:mm:ss" : "")"
            return
        }
        guard let end = includeTime ? DateMath.parseDateTime(endInput) : DateMath.parseDate(endInput) else {
            error = "目标日期无效：请输入 yyyy-MM-dd\(includeTime ? " HH:mm:ss" : "")"
            return
        }

        if includeTime {
            result = DateMath.durationText(from: start, to: end)
        } else {
            result = "相差 \(DateMath.days(from: start, to: end)) 天"
        }
    }
}

// MARK: - 分区 3：推算日期

private struct ForwardSection: View {
    @State private var dateInput = ""
    @State private var directionForward = true
    @State private var amountText = "100"
    @State private var unit: DateMath.Unit = .day
    @State private var result: String?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("推算日期")

            dateField(label: "", text: $dateInput, showToday: true)

            HStack(spacing: 8) {
                directionMenu
                TextField("数量", text: $amountText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 76)
                unitMenu
            }

            ToolActionButton(title: "是（计算）") { calculate() }

            if let error {
                inlineError(error)
            }

            if let result {
                Text(result)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .textSelection(.enabled)
            }

            ToolNoticeBox(title: "工具说明") {
                Text("本工具用于计算某个日期在一定时间单位之前或之后的日期，可用于推算纪念日、保质期等。")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var directionMenu: some View {
        Menu {
            Button("往后") { directionForward = true }
            Button("往前") { directionForward = false }
        } label: {
            HStack(spacing: 4) {
                Text(directionForward ? "往后" : "往前")
                    .font(.system(size: 12))
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.18), lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var unitMenu: some View {
        Menu {
            ForEach(DateMath.Unit.allCases, id: \.self) { candidate in
                Button(candidate.rawValue) { unit = candidate }
            }
        } label: {
            HStack(spacing: 4) {
                Text(unit.rawValue)
                    .font(.system(size: 12))
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.18), lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func calculate() {
        error = nil
        result = nil
        guard let date = DateMath.parseDate(dateInput) else {
            error = "日期无效：请输入 yyyy-MM-dd"
            return
        }
        guard let amount = Int(amountText.trimmingCharacters(in: .whitespaces)), amount != 0 else {
            error = "请输入非零的推算数量"
            return
        }
        let signedAmount = directionForward ? amount : -amount
        guard let target = DateMath.add(signedAmount, of: unit, to: date) else {
            error = "推算结果超出可表示的日期范围"
            return
        }
        result = "\(DateMath.formatDate(target)) · \(DateMath.weekdayText(target))"
    }
}

// MARK: - 分区 4：推算工作日

private struct WorkdaySection: View {
    @State private var dateInput = ""
    @State private var directionForward = true
    @State private var amountText = "15"
    @State private var result: String?
    @State private var error: String?
    @State private var usesApproximation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("推算工作日")

            dateField(label: "", text: $dateInput, showToday: true)

            HStack(spacing: 8) {
                Menu {
                    Button("往后") { directionForward = true }
                    Button("往前") { directionForward = false }
                } label: {
                    HStack(spacing: 4) {
                        Text(directionForward ? "往后" : "往前")
                            .font(.system(size: 12))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7, weight: .semibold))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.18), lineWidth: 1))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()

                TextField("数量", text: $amountText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 76)

                Text("个工作日")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            ToolActionButton(title: "是（计算）") { calculate() }

            if let error {
                inlineError(error)
            }

            if let result {
                Text(result)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .textSelection(.enabled)
            }

            ToolNoticeBox(title: "工具说明") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("本工具可计算某个日期经历 n 个工作日之后的日期，计算过程会剔除周末、法定假日并补充调休上班日。")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text(WorkdayCalendar.supportedYearsNotice)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.8))
                }
            }
        }
    }

    private func calculate() {
        error = nil
        result = nil
        usesApproximation = false
        guard let date = DateMath.parseDate(dateInput) else {
            error = "日期无效：请输入 yyyy-MM-dd"
            return
        }
        guard let amount = Int(amountText.trimmingCharacters(in: .whitespaces)), amount != 0 else {
            error = "请输入非零的工作日数量"
            return
        }
        let (target, fullySupported) = WorkdayCalendar.addWorkdays(
            from: date,
            count: directionForward ? amount : -amount
        )
        usesApproximation = !fullySupported
        result = "\(DateMath.formatDate(target)) · \(DateMath.weekdayText(target))"
    }
}

// MARK: - 分区 5：工作天数

private struct WorkdaysSection: View {
    @State private var startInput = ""
    @State private var endInput = ""
    @State private var result: String?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("工作天数计算")

            dateField(label: "开始", text: $startInput, showToday: true)
            dateField(label: "结束", text: $endInput, showToday: true)

            HStack(spacing: 8) {
                ToolActionButton(title: "天数（计算）") { calculate() }
                quickButton("本月") { fillMonth(offset: 0) }
                quickButton("下月") { fillMonth(offset: 1) }
                quickButton("上月") { fillMonth(offset: -1) }
                Spacer()
            }

            if let error {
                inlineError(error)
            }

            if let result {
                Text(result)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .textSelection(.enabled)
            }

            ToolNoticeBox(title: "工具说明") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("本工具可计算某时间段内的工作天数，计算过程会剔除周末、法定假日并补充调休上班日。")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text(WorkdayCalendar.supportedYearsNotice)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.8))
                }
            }
        }
    }

    private func quickButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title) { action() }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.2), lineWidth: 1))
    }

    private func fillMonth(offset: Int) {
        let calendar = DateMath.utcCalendar
        let today = DateMath.today()
        guard let monthDate = calendar.date(byAdding: .month, value: offset, to: today),
              let interval = calendar.dateInterval(of: .month, for: monthDate) else {
            return
        }
        startInput = DateMath.formatDate(interval.start)
        // 区间 end 是下月 1 日 0 点，往前一天才是本月最后一天。
        endInput = DateMath.formatDate(calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end)
    }

    private func calculate() {
        error = nil
        result = nil
        guard let start = DateMath.parseDate(startInput) else {
            error = "开始日期无效：请输入 yyyy-MM-dd"
            return
        }
        guard let end = DateMath.parseDate(endInput) else {
            error = "结束日期无效：请输入 yyyy-MM-dd"
            return
        }
        let outcome = WorkdayCalendar.workdays(from: start, to: end)
        result = "工作日 \(outcome.count) 天（自然日 \(outcome.totalDays) 天）"
    }
}

// MARK: - 分区 6：日期格式

private struct FormatSection: View {
    @State private var input = ""
    @State private var result: DateMath.EnglishDateFormats?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("英文日期格式转换")

            dateField(label: "", text: $input, showToday: true)

            ToolActionButton(title: "转换格式") { convert() }

            if let error {
                inlineError(error)
            }

            if let result {
                ToolCard {
                    ToolResultRow(label: "美式", value: result.american, monospaced: false)
                    Divider()
                    ToolResultRow(label: "英式", value: result.british, monospaced: false)
                    Divider()
                    ToolResultRow(label: "星期", value: result.weekday, monospaced: false)
                }
            }

            ToolNoticeBox(title: "工具说明") {
                Text("英文日期格式分英式和美式：美式日期格式为 Month Date, Year；英式日期格式为 Date Month, Year。")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func convert() {
        error = nil
        result = nil
        guard let formats = DateMath.englishDateFormats(input) else {
            error = "日期无效：请输入 yyyy-MM-dd"
            return
        }
        result = formats
    }
}

// MARK: - 分区 7：世界时间

private struct WorldSection: View {
    @State private var timeInput = ""
    @State private var sourceZone: TimestampToolView.ZoneSelection = .local
    @State private var selectedZones: Set<String> = [
        "UTC", "Asia/Shanghai", "Asia/Tokyo", "America/New_York", "Europe/London"
    ]
    @State private var results: [WorldTimeResult] = []
    @State private var error: String?

    struct WorldTimeResult: Equatable {
        let zoneName: String
        let timeText: String
        let offsetText: String
    }

    static let candidateZones: [TimestampToolView.ZoneSelection] = [
        .utc,
        .custom(identifier: "Asia/Shanghai"),
        .custom(identifier: "Asia/Tokyo"),
        .custom(identifier: "Asia/Singapore"),
        .custom(identifier: "Asia/Dubai"),
        .custom(identifier: "Europe/London"),
        .custom(identifier: "Europe/Berlin"),
        .custom(identifier: "Europe/Paris"),
        .custom(identifier: "America/New_York"),
        .custom(identifier: "America/Chicago"),
        .custom(identifier: "America/Los_Angeles"),
        .custom(identifier: "Australia/Sydney")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("世界时间转换器")

            HStack(spacing: 8) {
                Text("初始时间")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                TextField("yyyy-MM-dd HH:mm:ss", text: $timeInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minWidth: 150)
                Button("设置为当前时间") {
                    timeInput = DateMath.formatDateTime(Date())
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(.accentColor)
            }

            HStack(spacing: 8) {
                Text("初始时区")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                zoneMenu
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("转换时区")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    chipButton("全选") { selectedZones = Set(Self.candidateZones.map(\.displayName)) }
                    chipButton("全不选") { selectedZones.removeAll() }
                    chipButton("反选") {
                        let all = Set(Self.candidateZones.map(\.displayName))
                        selectedZones = all.symmetricDifference(selectedZones)
                    }
                }

                FlowLayout(spacing: 6) {
                    ForEach(Self.candidateZones, id: \.displayName) { candidate in
                        Toggle(candidate.displayName, isOn: Binding(
                            get: { selectedZones.contains(candidate.displayName) },
                            set: { on in
                                if on {
                                    selectedZones.insert(candidate.displayName)
                                } else {
                                    selectedZones.remove(candidate.displayName)
                                }
                            }
                        ))
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11))
                    }
                }
            }

            ToolActionButton(title: "立即转换") { convert() }

            if let error {
                inlineError(error)
            }

            if !results.isEmpty {
                ToolCard {
                    ForEach(Array(results.enumerated()), id: \.offset) { index, row in
                        if index > 0 {
                            Divider()
                        }
                        ToolResultRow(label: row.zoneName, value: "\(row.timeText) \(row.offsetText)", monospaced: false)
                    }
                }
            }

            ToolNoticeBox(title: "工具说明") {
                Text("输入要转换的时间和选择该时间所在的时区，即可转换成其他时区的对应时间。")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var zoneMenu: some View {
        Menu {
            Button("本地时区（\(TimeZone.current.identifier)）") { sourceZone = .local }
            Button("UTC") { sourceZone = .utc }
            Divider()
            ForEach(TimestampToolView.ZoneSelection.commonZones, id: \.self) { candidate in
                Button(candidate.displayName) { sourceZone = candidate }
            }
        } label: {
            HStack(spacing: 4) {
                Text(sourceZone.displayName)
                    .font(.system(size: 11))
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.18), lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func chipButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title) { action() }
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.2), lineWidth: 1))
    }

    private func convert() {
        error = nil
        results = []
        guard let date = DateMath.parseDateTime(timeInput) else {
            error = "时间无效：请输入 yyyy-MM-dd HH:mm:ss"
            return
        }

        // 把"源时区的墙上时间"换算为绝对时刻，再展示到各目标时区。
        var components = DateComponents()
        components.year = DateMath.utcCalendar.component(.year, from: date)
        components.month = DateMath.utcCalendar.component(.month, from: date)
        components.day = DateMath.utcCalendar.component(.day, from: date)
        components.hour = DateMath.utcCalendar.component(.hour, from: date)
        components.minute = DateMath.utcCalendar.component(.minute, from: date)
        components.second = DateMath.utcCalendar.component(.second, from: date)
        components.timeZone = sourceZone.timeZone
        guard let absolute = DateMath.utcCalendar.date(from: components) else {
            error = "时间无效"
            return
        }

        let zones = Self.candidateZones
            .filter { selectedZones.contains($0.displayName) }
            .map(\.timeZone)

        results = zones.map { zone in
            let name = zone.identifier == TimeZone.current.identifier
                ? "本地（\(zone.identifier)）"
                : zone.identifier
            let offsetSeconds = zone.secondsFromGMT(for: absolute)
            let hours = offsetSeconds / 3_600
            let minutes = abs(offsetSeconds % 3_600) / 60
            let sign = offsetSeconds >= 0 ? "+" : "-"
            let offsetText = String(format: "UTC%@%02d:%02d", sign, abs(hours), minutes)
            return WorldTimeResult(
                zoneName: name,
                timeText: TimestampMath.formattedText(absolute, timeZone: zone),
                offsetText: offsetText
            )
        }
        .sorted { $0.zoneName < $1.zoneName }
    }
}

/// 简单的流式布局：元素依次排布，放不下时换行。
/// 复用 SettingsWindow.swift 中已有的 FlowLayout（Layout 协议实现）。

// MARK: - 分区 8：在线秒表

@MainActor
final class StopwatchModel: ObservableObject {
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var laps: [TimeInterval] = []
    @Published private(set) var isRunning = false

    private var startDate: Date?
    private var accumulated: TimeInterval = 0
    private var timer: AnyCancellable?

    func toggle() {
        if isRunning {
            pause()
        } else {
            start()
        }
    }

    private func start() {
        guard !isRunning else { return }
        startDate = Date()
        isRunning = true
        timer = Timer.publish(every: 0.05, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, let startDate = self.startDate else { return }
                self.elapsed = self.accumulated + Date().timeIntervalSince(startDate)
            }
    }

    private func pause() {
        guard isRunning, let startDate else { return }
        accumulated += Date().timeIntervalSince(startDate)
        elapsed = accumulated
        isRunning = false
        timer?.cancel()
        timer = nil
    }

    func lap() {
        guard isRunning else { return }
        laps.insert(elapsed, at: 0)
    }

    func reset() {
        timer?.cancel()
        timer = nil
        startDate = nil
        accumulated = 0
        elapsed = 0
        laps = []
        isRunning = false
    }

    static func text(_ interval: TimeInterval) -> String {
        let total = max(0, interval)
        let hours = Int(total) / 3_600
        let minutes = (Int(total) % 3_600) / 60
        let seconds = Int(total) % 60
        let milliseconds = Int((total - total.rounded(.down)) * 1000)
        return String(format: "%02d:%02d:%02d.%03d", hours, minutes, seconds, milliseconds)
    }
}

private struct StopwatchSection: View {
    @ObservedObject var model: StopwatchModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("秒表")

            Text(StopwatchModel.text(model.elapsed))
                .font(.system(size: 44, weight: .semibold, design: .monospaced))
                .foregroundColor(.accentColor)
                .frame(maxWidth: .infinity)
                .textSelection(.enabled)

            HStack(spacing: 12) {
                stopwatchButton(model.isRunning ? "计次" : "开始", key: "a") {
                    if model.isRunning {
                        model.lap()
                    } else {
                        model.toggle()
                    }
                }
                stopwatchButton("计次", key: "s") { model.lap() }
                stopwatchButton("复位", key: "c") { model.reset() }
            }
            .frame(maxWidth: .infinity)

            if !model.laps.isEmpty {
                ToolCard {
                    ForEach(Array(model.laps.enumerated()), id: \.offset) { index, lap in
                        if index > 0 {
                            Divider()
                        }
                        ToolResultRow(label: "计次 \(model.laps.count - index)", value: StopwatchModel.text(lap))
                    }
                }
            }

            ToolNoticeBox(title: "使用说明") {
                VStack(alignment: .leading, spacing: 3) {
                    Text("1、点击\"开始\"按钮或键盘 A 可以启动秒表。")
                    Text("2、秒表计时中点击\"暂停\"按钮或键盘 A 可以暂停秒表。")
                    Text("3、秒表计时中点击\"计次\"按钮或键盘 S 可以计次。")
                    Text("4、点击\"复位\"按钮或键盘 C 可以清除所有记录。")
                }
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            }
        }
    }

    private func stopwatchButton(_ title: String, key: KeyEquivalent, action: @escaping () -> Void) -> some View {
        Button(title) { action() }
            .keyboardShortcut(key, modifiers: [])
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor, lineWidth: 1))
    }
}

// MARK: - 共享小部件

private func sectionTitle(_ title: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        Text(title)
            .font(.system(size: 16, weight: .semibold))
        Divider()
            .overlay(Color.primary.opacity(0.08))
    }
}

private func inlineError(_ text: String) -> some View {
    Label(text, systemImage: "exclamationmark.triangle.fill")
        .font(.system(size: 11))
        .foregroundColor(.orange)
}

private func dateField(
    label: String,
    text: Binding<String>,
    showToday: Bool = false
) -> some View {
    HStack(spacing: 8) {
        if !label.isEmpty {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        TextField("yyyy-MM-dd", text: text)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 12, design: .monospaced))
            .frame(width: 140)
        if showToday {
            Button("设置为今天") {
                text.wrappedValue = DateMath.formatDate(DateMath.today())
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundColor(.accentColor)
        }
        Spacer(minLength: 0)
    }
}

/// uTools 风格的说明框：主题色浅底 + 标题 + 正文。
struct ToolNoticeBox<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    @Environment(\.themeColors) private var themeColors

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(themeColors.accent.opacity(0.08))
        )
    }
}

/// 转换类操作按钮（描边样式）。
struct ToolActionButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title) { action() }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor, lineWidth: 1))
    }
}
