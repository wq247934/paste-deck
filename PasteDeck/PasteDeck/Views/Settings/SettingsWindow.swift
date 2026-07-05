//
//  SettingsWindow.swift
//  PasteDeck
//
//  Created on 2026-05-23.
//

import SwiftUI
import SwiftData
import ServiceManagement

struct SettingsWindow: View {
    @State private var selectedPane: SettingsPane = .general

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar

            Rectangle()
                .fill(Color.primary.opacity(0.07))
                .frame(width: 1)

            VStack(alignment: .leading, spacing: 0) {
                SettingsPaneHeader(pane: selectedPane)

                ScrollView {
                    selectedPaneContent
                        .padding(.horizontal, 22)
                        .padding(.bottom, 22)
                }
                .scrollIndicators(.hidden)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.primary.opacity(0.018))
        }
        .frame(width: 760, height: 520)
        .background(.thinMaterial)
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.stack.badge.play")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor))

                VStack(alignment: .leading, spacing: 2) {
                    Text("PasteDeck")
                        .font(.system(size: 15, weight: .semibold))
                    Text("设置")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.top, 18)
            .padding(.horizontal, 16)

            VStack(spacing: 4) {
                ForEach(SettingsPane.allCases) { pane in
                    SettingsNavigationButton(
                        pane: pane,
                        isSelected: selectedPane == pane
                    ) {
                        selectedPane = pane
                    }
                }
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 12)

            Text(PasteDeckVersion.short)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .frame(width: 176)
        .background(Color.primary.opacity(0.035))
    }

    @ViewBuilder
    private var selectedPaneContent: some View {
        switch selectedPane {
        case .general:
            GeneralSettingsView()
        case .hotkey:
            HotkeySettingsView()
        case .history:
            HistorySettingsView()
        case .filter:
            FilterSettingsView()
        case .favorites:
            FavoritesSettingsView()
        case .appearance:
            AppearanceSettingsView()
        case .advanced:
            AdvancedSettingsView()
        }
    }
}

private enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case hotkey
    case history
    case filter
    case favorites
    case appearance
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "通用"
        case .hotkey: return "快捷键"
        case .history: return "历史记录"
        case .filter: return "过滤"
        case .favorites: return "收藏夹"
        case .appearance: return "外观"
        case .advanced: return "高级"
        }
    }

    var subtitle: String {
        switch self {
        case .general: return "启动和系统权限"
        case .hotkey: return "唤起主面板的键盘入口"
        case .history: return "容量、保留和清理策略"
        case .filter: return "不记录指定来源"
        case .favorites: return "管理收藏夹名称和顺序"
        case .appearance: return "主题和卡片展示密度"
        case .advanced: return "预览、翻译和数据维护"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .hotkey: return "keyboard"
        case .history: return "clock.arrow.circlepath"
        case .filter: return "line.3.horizontal.decrease"
        case .favorites: return "star"
        case .appearance: return "paintpalette"
        case .advanced: return "slider.horizontal.3"
        }
    }
}

private enum PasteDeckVersion {
    static var short: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.2.5"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "125"
    }

    static var display: String {
        "\(short) (\(build))"
    }
}

private struct SettingsNavigationButton: View {
    let pane: SettingsPane
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: pane.icon)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                Text(pane.title)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
            }
            .foregroundColor(isSelected ? .white : .primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsPaneHeader: View {
    let pane: SettingsPane

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: pane.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.accentColor)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.12)))

            VStack(alignment: .leading, spacing: 2) {
                Text(pane.title)
                    .font(.system(size: 20, weight: .semibold))
                Text(pane.subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }
}

private struct SettingsContentStack<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content()
        }
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    var icon: String? = nil
    var footer: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 16)
                }

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)

                Spacer()
            }

            VStack(spacing: 0) {
                content()
            }
            .padding(12)
            .background(Color.primary.opacity(0.035))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )

            if let footer {
                Text(footer)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
            }
        }
    }
}

private struct SettingsRow<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 12)

            trailing()
        }
        .frame(minHeight: 32)
        .padding(.vertical, 5)
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.06))
            .frame(height: 1)
            .padding(.vertical, 8)
    }
}

private struct SettingsStatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.12)))
    }
}

private struct SettingsNotice: View {
    let text: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.orange)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.08)))
    }
}

private struct SettingsTag<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 5) {
            content()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private enum SettingsButtonTone {
    case primary
    case secondary
    case destructive
}

private struct SettingsActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    var tone: SettingsButtonTone = .secondary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(foregroundColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(backgroundColor(configuration: configuration))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(borderColor, lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }

    private var foregroundColor: Color {
        guard isEnabled else { return .secondary }
        switch tone {
        case .primary:
            return .accentColor
        case .secondary:
            return .primary
        case .destructive:
            return .red
        }
    }

    private func backgroundColor(configuration: Configuration) -> Color {
        let pressedBoost = configuration.isPressed ? 0.06 : 0
        switch tone {
        case .primary:
            return Color.accentColor.opacity(0.12 + pressedBoost)
        case .secondary:
            return Color.primary.opacity(0.055 + pressedBoost)
        case .destructive:
            return Color.red.opacity(0.105 + pressedBoost)
        }
    }

    private var borderColor: Color {
        switch tone {
        case .primary:
            return Color.accentColor.opacity(0.16)
        case .secondary:
            return Color.primary.opacity(0.06)
        case .destructive:
            return Color.red.opacity(0.16)
        }
    }
}

private struct SettingsMenuOption: Identifiable {
    let value: Int
    let title: String

    var id: Int { value }
}

private struct SettingsMenuPicker: View {
    @Binding var selection: Int
    let options: [SettingsMenuOption]

    private var selectedTitle: String {
        options.first(where: { $0.value == selection })?.title ?? "未设置"
    }

    var body: some View {
        Menu {
            ForEach(options) { option in
                Button {
                    selection = option.value
                } label: {
                    HStack {
                        Text(option.title)
                        if option.value == selection {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(selectedTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .frame(minWidth: 96, alignment: .center)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.primary.opacity(0.055))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settings: [AppSettings]
    @State private var accessibilityGranted = AXIsProcessTrusted()

    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private var appSettings: AppSettings {
        if let existing = settings.first {
            return existing
        }
        let new = AppSettings()
        modelContext.insert(new)
        try? modelContext.save()
        return new
    }

    var body: some View {
        SettingsContentStack {
            SettingsCard(title: "启动", icon: "power") {
                SettingsRow(title: "开机启动", subtitle: "登录 macOS 后自动常驻菜单栏") {
                    Toggle("", isOn: Binding(
                        get: {
                            SMAppService.mainApp.status == .enabled
                        },
                        set: { enabled in
                            do {
                                if enabled {
                                    try SMAppService.mainApp.register()
                                } else {
                                    try SMAppService.mainApp.unregister()
                                }
                                appSettings.launchAtLogin = enabled
                                try? modelContext.save()
                            } catch {
                                NSLog("[PasteDeck] Failed to toggle launch at login: \(error)")
                            }
                        }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }
            }

            SettingsCard(title: "权限", icon: "lock.shield") {
                SettingsRow(title: "辅助功能", subtitle: "用于全局快捷键和模拟粘贴") {
                    HStack(spacing: 8) {
                        SettingsStatusPill(
                            text: accessibilityGranted ? "已开启" : "未开启",
                            color: accessibilityGranted ? .green : .orange
                        )
                        Toggle("", isOn: .constant(accessibilityGranted))
                            .toggleStyle(.switch)
                            .disabled(true)
                            .labelsHidden()
                    }
                }

                if !accessibilityGranted {
                    SettingsDivider()

                    VStack(alignment: .leading, spacing: 10) {
                        SettingsNotice(
                            text: "未授权时，全局快捷键和自动粘贴会受限。",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        Button(action: {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }) {
                            Label("打开系统设置授权", systemImage: "arrow.up.forward.app")
                        }
                        .buttonStyle(SettingsActionButtonStyle(tone: .primary))
                    }
                }
            }
        }
        .onReceive(timer) { _ in
            accessibilityGranted = AXIsProcessTrusted()
        }
    }
}

// MARK: - Hotkey Settings

struct HotkeySettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settings: [AppSettings]

    @State private var isRecording = false

    private var appSettings: AppSettings {
        if let existing = settings.first {
            return existing
        }
        let new = AppSettings()
        modelContext.insert(new)
        try? modelContext.save()
        return new
    }

    /// 当前快捷键的显示文本
    private var shortcutDisplay: String {
        formatShortcut(display: appSettings.hotkeyDisplay, modifiers: appSettings.hotkeyModifiers)
    }

    var body: some View {
        SettingsContentStack {
            SettingsCard(title: "主面板", icon: "keyboard") {
                SettingsRow(title: "弹出窗口", subtitle: "用于快速打开剪贴板历史") {
                    HStack(spacing: 8) {
                        Text(isRecording ? "按下新的快捷键..." : shortcutDisplay)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(isRecording ? .accentColor : .primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(isRecording ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.08))
                        )
                        Button {
                            if isRecording {
                                isRecording = false
                                reregisterHotkey()
                            } else {
                                HotKeyManager.shared.unregister()
                                isRecording = true
                            }
                        } label: {
                            Label(isRecording ? "取消" : "修改", systemImage: isRecording ? "xmark" : "pencil")
                        }
                        .buttonStyle(SettingsActionButtonStyle(tone: isRecording ? .secondary : .primary))
                    }
                }
            }

            SettingsCard(title: "默认值", icon: "arrow.counterclockwise") {
                Button {
                    isRecording = false
                    appSettings.hotkeyKeyCode = 9
                    appSettings.hotkeyModifiers = Int(NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue)
                    appSettings.hotkeyDisplay = "V"
                    try? modelContext.save()
                    reregisterHotkey()
                } label: {
                    Label("恢复默认 (⌘ + Shift + V)", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(SettingsActionButtonStyle())
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background {
            HotkeyRecorderView(isRecording: isRecording) { keyCode, modifiers, displayChar in
                appSettings.hotkeyKeyCode = Int(keyCode)
                appSettings.hotkeyModifiers = modifiers
                appSettings.hotkeyDisplay = displayChar
                try? modelContext.save()
                reregisterHotkey()
                isRecording = false
            } onCancel: {
                isRecording = false
                reregisterHotkey()
            }
            .frame(width: 0, height: 0)
        }
        .onDisappear {
            if isRecording {
                isRecording = false
                reregisterHotkey()
            }
        }
    }

    // MARK: - Helper

    private func reregisterHotkey() {
        HotKeyManager.shared.unregister()
        HotKeyManager.shared.registerHotKey(
            keyCode: UInt32(appSettings.hotkeyKeyCode),
            modifiers: NSEvent.ModifierFlags(rawValue: UInt(appSettings.hotkeyModifiers))
        ) {
            NotificationCenter.default.post(name: .toggleMainPanel, object: nil)
        }
    }

    private func formatShortcut(display: String, modifiers: Int) -> String {
        let flags = NSEvent.ModifierFlags(rawValue: UInt(modifiers))
        var parts: [String] = []
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        parts.append(display.uppercased())
        return parts.joined(separator: " + ")
    }
}

/// 快捷键录制视图，使用本地键盘事件监听，避免透明录制层遮挡设置页按钮。
struct HotkeyRecorderView: NSViewRepresentable {
    let isRecording: Bool
    let onRecorded: (UInt32, Int, String) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onRecorded: onRecorded, onCancel: onCancel)
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onRecorded = onRecorded
        context.coordinator.onCancel = onCancel
        context.coordinator.setRecording(isRecording)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stopRecording()
    }

    final class Coordinator {
        var onRecorded: (UInt32, Int, String) -> Void
        var onCancel: () -> Void

        private var monitor: Any?
        private var isRecording = false

        init(onRecorded: @escaping (UInt32, Int, String) -> Void, onCancel: @escaping () -> Void) {
            self.onRecorded = onRecorded
            self.onCancel = onCancel
        }

        func setRecording(_ recording: Bool) {
            if recording {
                startRecording()
            } else {
                stopRecording()
            }
        }

        func stopRecording() {
            isRecording = false
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        private func startRecording() {
            isRecording = true
            guard monitor == nil else { return }

            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handleKeyDown(event)
            }
        }

        private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
            guard isRecording else { return event }

            if event.keyCode == 53 {
                isRecording = false
                onCancel()
                return nil
            }

            guard let shortcut = Self.shortcut(from: event) else {
                NSSound.beep()
                return nil
            }

            isRecording = false
            onRecorded(shortcut.keyCode, shortcut.modifiers, shortcut.display)
            return nil
        }

        private static func shortcut(from event: NSEvent) -> (keyCode: UInt32, modifiers: Int, display: String)? {
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard !modifiers.isEmpty else { return nil }
            guard let display = displayText(for: event) else { return nil }
            return (UInt32(event.keyCode), Int(modifiers.rawValue), display)
        }

        private static func displayText(for event: NSEvent) -> String? {
            if let characters = event.charactersIgnoringModifiers?.trimmingCharacters(in: .whitespacesAndNewlines),
               !characters.isEmpty {
                return characters.uppercased()
            }

            switch event.keyCode {
            case 36: return "Return"
            case 48: return "Tab"
            case 49: return "Space"
            case 51: return "Delete"
            case 53: return nil
            case 123: return "Left"
            case 124: return "Right"
            case 125: return "Down"
            case 126: return "Up"
            default: return "Key\(event.keyCode)"
            }
        }
    }
}

// MARK: - History Settings

struct HistorySettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ClipboardItem.createdAt, order: .reverse) private var items: [ClipboardItem]
    @Query private var settings: [AppSettings]

    @State private var cleanupCount = 100
    @State private var cleanupDays = 30
    @State private var showCleanupCountAlert = false
    @State private var showCleanupDaysAlert = false

    private var appSettings: AppSettings {
        if let existing = settings.first {
            return existing
        }
        let new = AppSettings()
        modelContext.insert(new)
        try? modelContext.save()
        return new
    }

    /// 当前记录条数
    private var totalItemCount: Int {
        items.count
    }

    /// 最早记录的日期
    private var earliestDate: Date? {
        items.last?.createdAt
    }

    var body: some View {
        SettingsContentStack {
            SettingsCard(title: "当前状态", icon: "chart.bar") {
                SettingsRow(title: "记录条数") {
                    Text("\(totalItemCount) 条")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                SettingsDivider()

                SettingsRow(title: "最早记录") {
                    Text(earliestDate.map(dateFormatter.string(from:)) ?? "无记录")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }

                SettingsDivider()

                SettingsRow(title: "缓存占用") {
                    Text(formatBytes(CacheManager().getTotalCacheSize()))
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }

            SettingsCard(title: "自动限制", icon: "timer") {
                SettingsRow(title: "条数限制", subtitle: "超过限制后自动清理最早的普通记录") {
                    SettingsMenuPicker(selection: Binding(
                        get: { appSettings.historyCountLimit },
                        set: { appSettings.historyCountLimit = $0; try? modelContext.save() }
                    ), options: [
                        SettingsMenuOption(value: 100, title: "100 条"),
                        SettingsMenuOption(value: 500, title: "500 条"),
                        SettingsMenuOption(value: 1000, title: "1000 条"),
                        SettingsMenuOption(value: 2000, title: "2000 条"),
                        SettingsMenuOption(value: 0, title: "无限制")
                    ])
                }

                SettingsDivider()

                SettingsRow(title: "时间限制", subtitle: "超过保留天数后自动清理普通记录") {
                    SettingsMenuPicker(selection: Binding(
                        get: { appSettings.historyDaysLimit },
                        set: { appSettings.historyDaysLimit = $0; try? modelContext.save() }
                    ), options: [
                        SettingsMenuOption(value: 7, title: "7 天"),
                        SettingsMenuOption(value: 14, title: "14 天"),
                        SettingsMenuOption(value: 30, title: "30 天"),
                        SettingsMenuOption(value: 0, title: "无限制")
                    ])
                }
            }

            SettingsCard(title: "缓存空间", icon: "externaldrive") {
                SettingsRow(title: "最大缓存空间", subtitle: "用于图片等本地缓存文件") {
                    SettingsMenuPicker(selection: Binding(
                        get: { appSettings.cacheSizeLimit },
                        set: { appSettings.cacheSizeLimit = $0; try? modelContext.save() }
                    ), options: [
                        SettingsMenuOption(value: 100, title: "100 MB"),
                        SettingsMenuOption(value: 500, title: "500 MB"),
                        SettingsMenuOption(value: 1000, title: "1 GB"),
                        SettingsMenuOption(value: 0, title: "无限制")
                    ])
                }
            }

            SettingsCard(title: "手动清理", icon: "trash") {
                SettingsRow(title: "清理最早记录") {
                    HStack(spacing: 10) {
                        Stepper("", value: $cleanupCount, in: 1...1000, step: 10)
                            .labelsHidden()
                        Text("\(cleanupCount) 条")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 64, alignment: .trailing)
                        Button(role: .destructive) {
                            showCleanupCountAlert = true
                        } label: {
                            Label("清理", systemImage: "trash")
                        }
                        .buttonStyle(SettingsActionButtonStyle(tone: .destructive))
                    }
                }

                SettingsDivider()

                SettingsRow(title: "按时间清理") {
                    HStack(spacing: 10) {
                        Stepper("", value: $cleanupDays, in: 1...365, step: 7)
                            .labelsHidden()
                        Text("\(cleanupDays) 天前")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .frame(width: 70, alignment: .trailing)
                        Button(role: .destructive) {
                            showCleanupDaysAlert = true
                        } label: {
                            Label("清理", systemImage: "trash")
                        }
                        .buttonStyle(SettingsActionButtonStyle(tone: .destructive))
                    }
                }
            }
        }
        .alert("确定清理最早的 \(cleanupCount) 条记录吗？", isPresented: $showCleanupCountAlert) {
            Button("取消", role: .cancel) {}
            Button("清理", role: .destructive) {
                cleanupOldestItems(count: cleanupCount)
            }
        }
        .alert("确定清理 \(cleanupDays) 天前的所有记录吗？", isPresented: $showCleanupDaysAlert) {
            Button("取消", role: .cancel) {}
            Button("清理", role: .destructive) {
                cleanupItemsOlderThan(days: cleanupDays)
            }
        }
    }

    // MARK: - Cleanup Methods

    private func cleanupOldestItems(count: Int) {
        let allItems = items
            .filter(\.isCleanupEligible)
            .sorted(by: { $0.createdAt < $1.createdAt })
        let toDelete = Array(allItems.prefix(count))
        for item in toDelete {
            modelContext.delete(item)
        }
        try? modelContext.save()
        NotificationCenter.default.post(name: .clipboardDataChanged, object: nil)
    }

    private func cleanupItemsOlderThan(days: Int) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.createdAt < cutoff }
        )
        guard let oldItems = try? modelContext.fetch(descriptor) else { return }
        for item in oldItems where item.isCleanupEligible {
            modelContext.delete(item)
        }
        try? modelContext.save()
        NotificationCenter.default.post(name: .clipboardDataChanged, object: nil)
    }

    // MARK: - Formatters

    private var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }

    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

// MARK: - Filter Settings

struct FilterSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settings: [AppSettings]
    @State private var newBlacklistApp = ""
    @State private var showRunningApps = false

    private var appSettings: AppSettings {
        if let existing = settings.first {
            return existing
        }
        let new = AppSettings()
        modelContext.insert(new)
        try? modelContext.save()
        return new
    }

    /// 当前运行中的应用（排除自身和系统 UI 进程）
    private var runningApps: [RunningAppInfo] {
        let blacklisted = Set(appSettings.blacklistedApps)
        return NSWorkspace.shared.runningApplications
            .filter { app in
                guard let name = app.localizedName, !name.isEmpty else { return false }
                // 排除自身
                if app.bundleIdentifier == "com.pastedeck.app" { return false }
                // 只显示有 Dock 图标的常规应用（排除系统后台进程）
                return app.activationPolicy == .regular
            }
            .compactMap { app in
                guard let name = app.localizedName else { return nil }
                return RunningAppInfo(
                    name: name,
                    bundleID: app.bundleIdentifier ?? "",
                    icon: app.icon
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .filter { !blacklisted.contains($0.name) }
    }

    var body: some View {
        SettingsContentStack {
            SettingsCard(title: "应用黑名单", icon: "nosign") {
                if appSettings.blacklistedApps.isEmpty {
                    Text("暂无黑名单应用")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(appSettings.blacklistedApps, id: \.self) { app in
                            HStack(spacing: 8) {
                                Image(systemName: "app.dashed")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                Text(app)
                                    .font(.system(size: 13, weight: .medium))
                                Spacer()
                                Button(action: {
                                    appSettings.blacklistedApps.removeAll { $0 == app }
                                    try? modelContext.save()
                                }) {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.035)))
                        }
                    }
                }

                SettingsDivider()

                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    TextField("添加应用名称", text: $newBlacklistApp)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                    Button {
                        let trimmed = newBlacklistApp.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty && !appSettings.blacklistedApps.contains(trimmed) {
                            appSettings.blacklistedApps.append(trimmed)
                            newBlacklistApp = ""
                            try? modelContext.save()
                        }
                    } label: {
                        Label("添加", systemImage: "plus.circle")
                    }
                    .buttonStyle(SettingsActionButtonStyle(tone: .primary))
                    .disabled(newBlacklistApp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.045)))
            }

            SettingsCard(title: "运行中的应用", icon: "macwindow") {
                if runningApps.isEmpty {
                    Text("暂无可添加的运行中应用")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(runningApps) { appInfo in
                                Button(action: {
                                    if !appSettings.blacklistedApps.contains(appInfo.name) {
                                        appSettings.blacklistedApps.append(appInfo.name)
                                        try? modelContext.save()
                                    }
                                }) {
                                    HStack(spacing: 9) {
                                        if let icon = appInfo.icon {
                                            Image(nsImage: icon)
                                                .resizable()
                                                .frame(width: 22, height: 22)
                                        } else {
                                            Image(systemName: "app")
                                                .font(.system(size: 15))
                                                .foregroundColor(.secondary)
                                                .frame(width: 22, height: 22)
                                        }

                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(appInfo.name)
                                                .font(.system(size: 13, weight: .medium))
                                                .foregroundColor(.primary)
                                            if !appInfo.bundleID.isEmpty {
                                                Text(appInfo.bundleID)
                                                    .font(.system(size: 10, design: .monospaced))
                                                    .foregroundColor(.secondary)
                                                    .lineLimit(1)
                                                    .truncationMode(.tail)
                                            }
                                        }

                                        Spacer()

                                        Image(systemName: "plus.circle.fill")
                                            .foregroundColor(.accentColor)
                                            .font(.system(size: 15))
                                    }
                                    .padding(.vertical, 7)
                                    .padding(.horizontal, 10)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.035)))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxHeight: 210)
                }
            }
        }
    }
}

/// 运行中应用信息
struct RunningAppInfo: Identifiable {
    let name: String
    let bundleID: String
    let icon: NSImage?

    var id: String { bundleID.isEmpty ? name : bundleID }
}

// MARK: - Favorites Settings

struct FavoritesSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FavoriteCollection.sortOrder) private var collections: [FavoriteCollection]

    @State private var showDeleteAlert = false
    @State private var collectionToDelete: FavoriteCollection?

    var body: some View {
        SettingsContentStack {
            SettingsCard(title: "收藏夹列表", icon: "star") {
                if collections.isEmpty {
                    Text("暂无收藏夹")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    List {
                        ForEach(collections, id: \.id) { collection in
                            CollectionRowView(
                                collection: collection,
                                onDelete: {
                                    collectionToDelete = collection
                                    showDeleteAlert = true
                                }
                            )
                        }
                        .onMove { from, to in
                            moveCollections(from: from, to: to)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .frame(height: min(CGFloat(collections.count) * 36 + 12, 220))
                }

                if !collections.isEmpty {
                    SettingsDivider()

                    Label("拖拽调整顺序", systemImage: "arrow.up.arrow.down")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .alert("确认删除", isPresented: $showDeleteAlert) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                if let collection = collectionToDelete {
                    deleteCollection(collection)
                }
            }
        } message: {
            Text("删除收藏夹「\(collectionToDelete?.name ?? "")」？其中的卡片不会被删除，仅解除关联。")
        }
    }

    private func moveCollections(from source: IndexSet, to destination: Int) {
        var reordered = collections
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, collection) in reordered.enumerated() {
            collection.sortOrder = index
        }
        try? modelContext.save()
        NotificationCenter.default.post(name: .clipboardDataChanged, object: nil)
    }

    private func deleteCollection(_ collection: FavoriteCollection) {
        // 仅解除卡片关联，不删除卡片
        collection.items?.forEach { item in
            item.collections?.removeAll(where: { $0.id == collection.id })
        }
        modelContext.delete(collection)
        try? modelContext.save()
        NotificationCenter.default.post(name: .clipboardDataChanged, object: nil)
    }
}

// MARK: - Collection Row View (支持改名)

struct CollectionRowView: View {
    let collection: FavoriteCollection
    let onDelete: () -> Void

    @State private var isEditing = false
    @State private var editedName: String = ""
    @FocusState private var isTextFieldFocused: Bool

    init(collection: FavoriteCollection, onDelete: @escaping () -> Void) {
        self.collection = collection
        self.onDelete = onDelete
        _editedName = State(initialValue: collection.name)
    }

    var body: some View {
        HStack {
            Image(systemName: collection.isDefault ? "star.fill" : "folder")
                .foregroundColor(collection.isDefault ? .yellow : .secondary)

            if isEditing {
                TextField("收藏夹名称", text: $editedName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($isTextFieldFocused)
                    .onSubmit {
                        saveRename()
                    }
                    .onExitCommand {
                        cancelRename()
                    }
            } else {
                Text(collection.name)
                    .font(.system(size: 13))
            }

            if collection.isDefault {
                Text("默认")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor.opacity(0.7)))
            }

            Spacer()

            Text("\(collection.items?.count ?? 0) 项")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            if !collection.isDefault {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundColor(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            if !collection.isDefault {
                Button("改名") {
                    startEditing()
                }
                Divider()
                Button("删除", role: .destructive, action: onDelete)
            }
        }
    }

    private func startEditing() {
        editedName = collection.name
        isEditing = true
        isTextFieldFocused = true
    }

    private func saveRename() {
        let trimmed = editedName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty && trimmed != collection.name {
            collection.name = trimmed
            try? collection.modelContext?.save()
            NotificationCenter.default.post(name: .clipboardDataChanged, object: nil)
        }
        isEditing = false
    }

    private func cancelRename() {
        isEditing = false
    }
}

// MARK: - Appearance Settings

struct AppearanceSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settings: [AppSettings]

    private var appSettings: AppSettings {
        if let existing = settings.first {
            return existing
        }
        let new = AppSettings()
        modelContext.insert(new)
        try? modelContext.save()
        return new
    }

    var body: some View {
        SettingsContentStack {
            SettingsCard(title: "主题", icon: "circle.lefthalf.filled") {
                SettingsRow(title: "外观模式", subtitle: "设置主面板和预览窗口的颜色模式") {
                    Picker("", selection: Binding(
                        get: { appSettings.themeMode },
                        set: { appSettings.themeMode = $0; try? modelContext.save() }
                    )) {
                        Text("跟随系统").tag(0)
                        Text("浅色").tag(1)
                        Text("深色").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 230)
                }
            }

            SettingsCard(title: "卡片", icon: "rectangle.grid.1x2") {
                SettingsRow(title: "卡片大小", subtitle: "影响主面板中剪贴板卡片的展示尺寸") {
                    Picker("", selection: Binding(
                        get: { appSettings.cardSize },
                        set: { appSettings.cardSize = $0; try? modelContext.save() }
                    )) {
                        Text("小").tag(0)
                        Text("中").tag(1)
                        Text("大").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 160)
                }
            }
        }
    }
}

// MARK: - Advanced Settings

struct AdvancedSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settings: [AppSettings]
    @State private var highlightExtensions: [String: String] = PreviewConfigManager.shared.config.highlightExtensions
    @State private var plainTextExtensions: [String] = PreviewConfigManager.shared.config.plainTextExtensions
    @State private var newHighlightExt = ""
    @State private var newHighlightLang = ""
    @State private var newPlainExt = ""
    @State private var showingClearHistoryAlert = false
    @State private var showingClearCacheAlert = false
    @State private var isVerifyingBaidu = false
    @State private var baiduVerifyResult: (isSuccess: Bool, message: String)?
    private var appSettings: AppSettings {
        if let existing = settings.first {
            return existing
        }
        let new = AppSettings()
        modelContext.insert(new)
        try? modelContext.save()
        return new
    }

    var body: some View {
        SettingsContentStack {
            SettingsCard(title: "语法高亮后缀", icon: "chevron.left.forwardslash.chevron.right") {
                if highlightExtensions.isEmpty {
                    Text("暂无高亮后缀")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    FlowLayout(spacing: 6) {
                        ForEach(Array(highlightExtensions.keys.sorted()), id: \.self) { ext in
                            SettingsTag {
                                Text("." + ext)
                                    .font(.system(size: 12, design: .monospaced))
                                Text("->")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                Text(highlightExtensions[ext] ?? "")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Button(action: {
                                    highlightExtensions.removeValue(forKey: ext)
                                    saveConfig()
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                SettingsDivider()

                HStack(spacing: 8) {
                    TextField("后缀", text: $newHighlightExt)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .frame(width: 90)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.045)))
                    Text("->")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    TextField("语言", text: $newHighlightLang)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .frame(width: 120)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.045)))
                    Button {
                        let ext = newHighlightExt.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
                        let lang = newHighlightLang.lowercased().trimmingCharacters(in: .whitespaces)
                        if !ext.isEmpty && !lang.isEmpty {
                            highlightExtensions[ext] = lang
                            newHighlightExt = ""
                            newHighlightLang = ""
                            saveConfig()
                        }
                    } label: {
                        Label("添加", systemImage: "plus.circle")
                    }
                    .buttonStyle(SettingsActionButtonStyle(tone: .primary))
                    .disabled(newHighlightExt.isEmpty || newHighlightLang.isEmpty)
                }
            }

            SettingsCard(title: "纯文本后缀", icon: "doc.plaintext") {
                if plainTextExtensions.isEmpty {
                    Text("暂无纯文本后缀")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    FlowLayout(spacing: 6) {
                        ForEach(plainTextExtensions, id: \.self) { ext in
                            SettingsTag {
                                Text("." + ext)
                                    .font(.system(size: 12, design: .monospaced))
                                Button(action: {
                                    plainTextExtensions.removeAll { $0 == ext }
                                    saveConfig()
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                SettingsDivider()

                HStack(spacing: 8) {
                    TextField("后缀", text: $newPlainExt)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .frame(width: 110)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.045)))
                    Button {
                        let ext = newPlainExt.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
                        if !ext.isEmpty && !plainTextExtensions.contains(ext) {
                            plainTextExtensions.append(ext)
                            newPlainExt = ""
                            saveConfig()
                        }
                    } label: {
                        Label("添加", systemImage: "plus.circle")
                    }
                    .buttonStyle(SettingsActionButtonStyle(tone: .primary))
                    .disabled(newPlainExt.isEmpty)
                }
            }

            SettingsCard(title: "百度翻译", icon: "character.book.closed") {
                SettingsRow(title: "启用百度翻译", subtitle: "预览窗口中的翻译能力") {
                    Toggle("", isOn: Binding(
                        get: { appSettings.baiduTranslateEnabled },
                        set: { appSettings.baiduTranslateEnabled = $0; try? modelContext.save() }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }

                SettingsDivider()

                HStack {
                    Text("免费额度：5万字/月")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Spacer()
                    Link("注册百度翻译开放平台", destination: URL(string: "https://fanyi-api.baidu.com/")!)
                        .font(.system(size: 11))
                }
            }

            if appSettings.baiduTranslateEnabled {
                SettingsCard(title: "翻译配置", icon: "key") {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("App ID", text: Binding(
                            get: { appSettings.baiduTranslateAppId },
                            set: { appSettings.baiduTranslateAppId = $0; try? modelContext.save() }
                        ))
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.045)))

                        SecureField("密钥", text: Binding(
                            get: { appSettings.baiduTranslateSecretKey },
                            set: { appSettings.baiduTranslateSecretKey = $0; try? modelContext.save() }
                        ))
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.045)))

                        SettingsRow(title: "高级版", subtitle: "支持并发请求") {
                            Toggle("", isOn: Binding(
                                get: { appSettings.baiduTranslateIsAdvanced },
                                set: { appSettings.baiduTranslateIsAdvanced = $0; try? modelContext.save() }
                            ))
                            .toggleStyle(.switch)
                            .labelsHidden()
                        }

                        HStack(spacing: 10) {
                            Button {
                                verifyBaiduApi()
                            } label: {
                                Label("验证配置", systemImage: "checkmark.seal")
                            }
                            .buttonStyle(SettingsActionButtonStyle(tone: .primary))
                            .disabled(appSettings.baiduTranslateAppId.isEmpty || appSettings.baiduTranslateSecretKey.isEmpty)

                            if isVerifyingBaidu {
                                ProgressView()
                                    .controlSize(.small)
                            }

                            if let result = baiduVerifyResult {
                                HStack(spacing: 4) {
                                    Image(systemName: result.isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundColor(result.isSuccess ? .green : .red)
                                    Text(result.message)
                                        .font(.system(size: 12))
                                        .foregroundColor(result.isSuccess ? .green : .secondary)
                                }
                            }
                        }
                    }
                }
            }

            SettingsCard(title: "清除数据", icon: "trash") {
                HStack(spacing: 10) {
                    Button(role: .destructive) {
                        showingClearHistoryAlert = true
                    } label: {
                        Label("清除所有历史记录", systemImage: "trash")
                    }
                    .buttonStyle(SettingsActionButtonStyle(tone: .destructive))

                    Button(role: .destructive) {
                        showingClearCacheAlert = true
                    } label: {
                        Label("清除缓存", systemImage: "externaldrive.badge.xmark")
                    }
                    .buttonStyle(SettingsActionButtonStyle(tone: .destructive))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            SettingsCard(title: "关于", icon: "info.circle") {
                SettingsRow(title: "版本") {
                    Text(PasteDeckVersion.display)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
        }
        .alert("确定要清除所有历史记录吗？", isPresented: $showingClearHistoryAlert) {
            Button("取消", role: .cancel) {}
            Button("清除", role: .destructive) {
                clearAllHistory()
            }
        }
        .alert("确定要清除所有缓存吗？", isPresented: $showingClearCacheAlert) {
            Button("取消", role: .cancel) {}
            Button("清除", role: .destructive) {
                CacheManager().clearAllCache()
            }
        }
    }

    private func verifyBaiduApi() {
        isVerifyingBaidu = true
        baiduVerifyResult = nil

        let service = TranslateService(
            appId: appSettings.baiduTranslateAppId,
            secretKey: appSettings.baiduTranslateSecretKey,
            isAdvanced: appSettings.baiduTranslateIsAdvanced
        )

        service.translateSegment("hello", from: "en", to: "zh") { result in
            DispatchQueue.main.async {
                isVerifyingBaidu = false
                switch result {
                case .success:
                    baiduVerifyResult = (isSuccess: true, message: "验证成功")
                case .failure(let error):
                    baiduVerifyResult = (isSuccess: false, message: error.localizedDescription)
                }
            }
        }
    }

    private func saveConfig() {
        PreviewConfigManager.shared.config.highlightExtensions = highlightExtensions
        PreviewConfigManager.shared.config.plainTextExtensions = plainTextExtensions
        PreviewConfigManager.shared.save()
    }

    private func clearAllHistory() {
        let context = ModelContext(AppModelContainer.container)
        let descriptor = FetchDescriptor<ClipboardItem>()
        if let items = try? context.fetch(descriptor) {
            for item in items where item.isCleanupEligible {
                context.delete(item)
            }
            try? context.save()
            NotificationCenter.default.post(name: .clipboardDataChanged, object: nil)
        }
    }
}

/// 简单的 Flow/Wrap 布局容器
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            totalHeight = y + rowHeight
        }

        return (CGSize(width: maxWidth, height: totalHeight), positions)
    }
}
