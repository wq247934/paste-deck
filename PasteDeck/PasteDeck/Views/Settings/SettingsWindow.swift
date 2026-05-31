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
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("通用", systemImage: "gear")
                }

            HotkeySettingsView()
                .tabItem {
                    Label("快捷键", systemImage: "keyboard")
                }

            HistorySettingsView()
                .tabItem {
                    Label("历史记录", systemImage: "clock")
                }

            FilterSettingsView()
                .tabItem {
                    Label("过滤", systemImage: "line.3.horizontal.decrease")
                }

            FavoritesSettingsView()
                .tabItem {
                    Label("收藏夹", systemImage: "star")
                }

            AppearanceSettingsView()
                .tabItem {
                    Label("外观", systemImage: "paintpalette")
                }

            AdvancedSettingsView()
                .tabItem {
                    Label("高级", systemImage: "wrench.and.screwdriver")
                }
        }
        .frame(width: 500, height: 400)
        .padding(20)
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
        Form {
            Section("启动") {
                Toggle("开机启动", isOn: Binding(
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
            }

            Section("菜单栏") {
                Toggle("显示菜单栏图标", isOn: Binding(
                    get: { appSettings.showMenuBarIcon },
                    set: { appSettings.showMenuBarIcon = $0; try? modelContext.save() }
                ))
            }

            Section("权限") {
                HStack {
                    Text("辅助功能")
                    Spacer()
                    Text(accessibilityGranted ? "已开启" : "未开启")
                        .foregroundColor(accessibilityGranted ? .green : .orange)
                        .font(.system(size: 13, weight: .medium))
                    Toggle("", isOn: .constant(accessibilityGranted))
                        .toggleStyle(.switch)
                        .disabled(true)
                        .labelsHidden()
                }

                if !accessibilityGranted {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("部分功能受限：全局快捷键和模拟粘贴将无法使用")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Button(action: {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }) {
                            Text("打开系统设置授权")
                                .font(.system(size: 12))
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
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
        Form {
            Section("快捷键设置") {
                HStack {
                    Text("弹出窗口")
                    Spacer()
                    if isRecording {
                        Text("按下新的快捷键...")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.1))
                            .cornerRadius(4)
                    } else {
                        Text(shortcutDisplay)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.1))
                            .cornerRadius(4)
                    }
                    Button(isRecording ? "取消" : "修改") {
                        isRecording.toggle()
                    }
                    .buttonStyle(.bordered)
                }
            }

            Section {
                Button("恢复默认 (⌘ + Shift + V)") {
                    appSettings.hotkeyKeyCode = 9
                    appSettings.hotkeyModifiers = Int(NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue)
                    appSettings.hotkeyDisplay = "V"
                    try? modelContext.save()
                    reregisterHotkey()
                }
            }
        }
        .formStyle(.grouped)
        .overlay {
            if isRecording {
                HotkeyRecorderView { keyCode, modifiers, displayChar in
                    appSettings.hotkeyKeyCode = Int(keyCode)
                    appSettings.hotkeyModifiers = modifiers
                    appSettings.hotkeyDisplay = displayChar
                    try? modelContext.save()
                    reregisterHotkey()
                    isRecording = false
                } onCancel: {
                    isRecording = false
                }
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

/// 快捷键录制视图，拦截键盘事件
struct HotkeyRecorderView: NSViewRepresentable {
    let onRecorded: (UInt32, Int, String) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = HotkeyRecorderNSView()
        view.onRecorded = onRecorded
        view.onCancel = onCancel
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    class HotkeyRecorderNSView: NSView {
        var onRecorded: ((UInt32, Int, String) -> Void)?
        var onCancel: (() -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            // 必须至少一个修饰键
            guard !modifiers.isEmpty else { return }
            // 不允许单独的修饰键组合（没有实际字母）
            let modifierOnly = [.shift, .command, .control, .option,
                                 NSEvent.ModifierFlags(arrayLiteral: .command, .shift),
                                 NSEvent.ModifierFlags(arrayLiteral: .command, .option),
                                 NSEvent.ModifierFlags(arrayLiteral: .command, .control),
                                 NSEvent.ModifierFlags(arrayLiteral: .control, .shift),
                                 NSEvent.ModifierFlags(arrayLiteral: .control, .option),
                                 NSEvent.ModifierFlags(arrayLiteral: .option, .shift)]
            guard !modifierOnly.contains(modifiers) || event.charactersIgnoringModifiers != nil else { return }

            let modifierInt = Int(modifiers.rawValue)
            let keyCode = UInt32(event.keyCode)
            // 用 charactersIgnoringModifiers 获取实际按键字符，不受键盘布局影响
            let displayChar = event.charactersIgnoringModifiers?.uppercased() ?? "Key\(keyCode)"

            onRecorded?(keyCode, modifierInt, displayChar)
        }

        override func cancelOperation(_ sender: Any?) {
            onCancel?()
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
        Form {
            Section("当前状态") {
                HStack {
                    Text("记录条数")
                    Spacer()
                    Text("\(totalItemCount) 条")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("最早记录")
                    Spacer()
                    if let date = earliestDate {
                        Text(dateFormatter.string(from: date))
                            .foregroundColor(.secondary)
                    } else {
                        Text("无记录")
                            .foregroundColor(.secondary)
                    }
                }

                HStack {
                    Text("缓存占用")
                    Spacer()
                    Text(formatBytes(CacheManager().getTotalCacheSize()))
                        .foregroundColor(.secondary)
                }
            }

            Section("自动限制") {
                Picker("条数限制", selection: Binding(
                    get: { appSettings.historyCountLimit },
                    set: { appSettings.historyCountLimit = $0; try? modelContext.save() }
                )) {
                    Text("100 条").tag(100)
                    Text("500 条").tag(500)
                    Text("1000 条").tag(1000)
                    Text("2000 条").tag(2000)
                    Text("无限制").tag(0)
                }

                Picker("时间限制", selection: Binding(
                    get: { appSettings.historyDaysLimit },
                    set: { appSettings.historyDaysLimit = $0; try? modelContext.save() }
                )) {
                    Text("7 天").tag(7)
                    Text("14 天").tag(14)
                    Text("30 天").tag(30)
                    Text("无限制").tag(0)
                }
            }

            Section("缓存空间") {
                Picker("最大缓存空间", selection: Binding(
                    get: { appSettings.cacheSizeLimit },
                    set: { appSettings.cacheSizeLimit = $0; try? modelContext.save() }
                )) {
                    Text("100 MB").tag(100)
                    Text("500 MB").tag(500)
                    Text("1 GB").tag(1000)
                    Text("无限制").tag(0)
                }
            }

            Section("手动清理") {
                HStack {
                    Stepper("清理最早", value: $cleanupCount, in: 1...1000, step: 10)
                    Text("\(cleanupCount) 条")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("清理") {
                        showCleanupCountAlert = true
                    }
                    .foregroundColor(.red)
                }

                HStack {
                    Stepper("清理", value: $cleanupDays, in: 1...365, step: 7)
                    Text("\(cleanupDays) 天前的数据")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("清理") {
                        showCleanupDaysAlert = true
                    }
                    .foregroundColor(.red)
                }
            }
        }
        .formStyle(.grouped)
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
        let allItems = items.sorted(by: { $0.createdAt < $1.createdAt })
        let toDelete = Array(allItems.prefix(count))
        for item in toDelete {
            modelContext.delete(item)
        }
        try? modelContext.save()
    }

    private func cleanupItemsOlderThan(days: Int) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.createdAt < cutoff }
        )
        guard let oldItems = try? modelContext.fetch(descriptor) else { return }
        for item in oldItems {
            modelContext.delete(item)
        }
        try? modelContext.save()
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
        Form {
            Section("应用黑名单") {
                ForEach(appSettings.blacklistedApps, id: \.self) { app in
                    HStack {
                        Text(app)
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
                }

                HStack {
                    TextField("添加应用名称", text: $newBlacklistApp)
                        .textFieldStyle(.roundedBorder)
                    Button("添加") {
                        let trimmed = newBlacklistApp.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty && !appSettings.blacklistedApps.contains(trimmed) {
                            appSettings.blacklistedApps.append(trimmed)
                            newBlacklistApp = ""
                            try? modelContext.save()
                        }
                    }
                }
            }

            Section("运行中的应用") {
                if runningApps.isEmpty {
                    Text("暂无可添加的运行中应用")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(runningApps) { appInfo in
                                Button(action: {
                                    if !appSettings.blacklistedApps.contains(appInfo.name) {
                                        appSettings.blacklistedApps.append(appInfo.name)
                                        try? modelContext.save()
                                    }
                                }) {
                                    HStack(spacing: 8) {
                                        if let icon = appInfo.icon {
                                            Image(nsImage: icon)
                                                .resizable()
                                                .frame(width: 20, height: 20)
                                        }
                                        Text(appInfo.name)
                                            .foregroundColor(.primary)
                                        if !appInfo.bundleID.isEmpty {
                                            Text(appInfo.bundleID)
                                                .font(.system(size: 10, design: .monospaced))
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                                .truncationMode(.tail)
                                        }
                                        Spacer()
                                        Image(systemName: "plus.circle.fill")
                                            .foregroundColor(.accentColor)
                                            .font(.system(size: 14))
                                    }
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 8)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.03)))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
            }
        }
        .formStyle(.grouped)
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
        Form {
            Section {
                if collections.isEmpty {
                    Text("暂无收藏夹")
                        .foregroundColor(.secondary)
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
                }
            } header: {
                HStack {
                    Text("收藏夹列表")
                    Spacer()
                    Text("拖拽排序")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
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
    }

    private func deleteCollection(_ collection: FavoriteCollection) {
        // 仅解除卡片关联，不删除卡片
        collection.items?.forEach { item in
            item.collections?.removeAll(where: { $0.id == collection.id })
        }
        modelContext.delete(collection)
        try? modelContext.save()
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
        Form {
            Section("主题") {
                Picker("外观模式", selection: Binding(
                    get: { appSettings.themeMode },
                    set: { appSettings.themeMode = $0; try? modelContext.save() }
                )) {
                    Text("跟随系统").tag(0)
                    Text("浅色").tag(1)
                    Text("深色").tag(2)
                }
                .pickerStyle(.segmented)
            }

            Section("卡片") {
                Picker("卡片大小", selection: Binding(
                    get: { appSettings.cardSize },
                    set: { appSettings.cardSize = $0; try? modelContext.save() }
                )) {
                    Text("小").tag(0)
                    Text("中").tag(1)
                    Text("大").tag(2)
                }
            }
        }
        .formStyle(.grouped)
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
        Form {
            Section("语法高亮后缀") {
                FlowLayout(spacing: 6) {
                    ForEach(Array(highlightExtensions.keys.sorted()), id: \.self) { ext in
                        HStack(spacing: 4) {
                            Text("." + ext)
                                .font(.system(size: 12, design: .monospaced))
                            Text("→")
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
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }

                HStack {
                    TextField("后缀", text: $newHighlightExt)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    Text("→")
                    TextField("语言", text: $newHighlightLang)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                    Button("添加") {
                        let ext = newHighlightExt.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
                        let lang = newHighlightLang.lowercased().trimmingCharacters(in: .whitespaces)
                        if !ext.isEmpty && !lang.isEmpty {
                            highlightExtensions[ext] = lang
                            newHighlightExt = ""
                            newHighlightLang = ""
                            saveConfig()
                        }
                    }
                }
            }

            Section("纯文本后缀") {
                FlowLayout(spacing: 6) {
                    ForEach(plainTextExtensions, id: \.self) { ext in
                        HStack(spacing: 4) {
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
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }

                HStack {
                    TextField("后缀", text: $newPlainExt)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                    Button("添加") {
                        let ext = newPlainExt.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
                        if !ext.isEmpty && !plainTextExtensions.contains(ext) {
                            plainTextExtensions.append(ext)
                            newPlainExt = ""
                            saveConfig()
                        }
                    }
                }
            }

            Section {
                Toggle("启用百度翻译", isOn: Binding(
                    get: { appSettings.baiduTranslateEnabled },
                    set: { appSettings.baiduTranslateEnabled = $0; try? modelContext.save() }
                ))
            } header: {
                Text("百度翻译")
            } footer: {
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
                Section("翻译配置") {
                    TextField("App ID", text: Binding(
                        get: { appSettings.baiduTranslateAppId },
                        set: { appSettings.baiduTranslateAppId = $0; try? modelContext.save() }
                    ))
                    .textFieldStyle(.roundedBorder)

                    SecureField("密钥", text: Binding(
                        get: { appSettings.baiduTranslateSecretKey },
                        set: { appSettings.baiduTranslateSecretKey = $0; try? modelContext.save() }
                    ))
                    .textFieldStyle(.roundedBorder)

                    Toggle("高级版（支持并发请求）", isOn: Binding(
                        get: { appSettings.baiduTranslateIsAdvanced },
                        set: { appSettings.baiduTranslateIsAdvanced = $0; try? modelContext.save() }
                    ))

                    HStack {
                        Button("验证配置") {
                            verifyBaiduApi()
                        }
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

            Section("清除数据") {
                Button("清除所有历史记录") {
                    showingClearHistoryAlert = true
                }
                .foregroundColor(.red)

                Button("清除缓存") {
                    showingClearCacheAlert = true
                }
                .foregroundColor(.red)
            }

            Section("关于") {
                HStack {
                    Text("版本")
                    Spacer()
                    Text("1.0.3")
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
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
            for item in items {
                context.delete(item)
            }
            try? context.save()
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
