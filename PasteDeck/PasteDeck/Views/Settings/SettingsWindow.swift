//
//  SettingsWindow.swift
//  PasteDeck
//
//  Created on 2026-05-23.
//

import SwiftUI
import SwiftData

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
    @State private var launchAtLogin = true
    @State private var showMenuBarIcon = true
    @State private var accessibilityGranted = AXIsProcessTrusted()

    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section("启动") {
                Toggle("开机启动", isOn: $launchAtLogin)
            }

            Section("菜单栏") {
                Toggle("显示菜单栏图标", isOn: $showMenuBarIcon)
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
    @State private var currentShortcut = "⌘ + Shift + V"

    var body: some View {
        Form {
            Section("快捷键设置") {
                HStack {
                    Text("弹出窗口")
                    Spacer()
                    Text(currentShortcut)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.1))
                        .cornerRadius(4)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - History Settings

struct HistorySettingsView: View {
    @State private var historyCountLimit = 500
    @State private var historyDaysLimit = 0
    @State private var cacheSizeLimit = 500

    var body: some View {
        Form {
            Section("历史记录限制") {
                Picker("条数限制", selection: $historyCountLimit) {
                    Text("100 条").tag(100)
                    Text("500 条").tag(500)
                    Text("1000 条").tag(1000)
                    Text("2000 条").tag(2000)
                    Text("无限制").tag(0)
                }

                Picker("时间限制", selection: $historyDaysLimit) {
                    Text("7 天").tag(7)
                    Text("14 天").tag(14)
                    Text("30 天").tag(30)
                    Text("无限制").tag(0)
                }
            }

            Section("缓存空间") {
                Picker("最大缓存空间", selection: $cacheSizeLimit) {
                    Text("100 MB").tag(100)
                    Text("500 MB").tag(500)
                    Text("1 GB").tag(1000)
                    Text("无限制").tag(0)
                }

                HStack {
                    Text("当前缓存占用")
                    Spacer()
                    Text(formatBytes(CacheManager().getTotalCacheSize()))
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
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
        .onTapGesture(count: 2) {
            if !collection.isDefault && !isEditing {
                startEditing()
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
    @State private var themeMode = 0
    @State private var cardSizeOption = 1

    var body: some View {
        Form {
            Section("主题") {
                Picker("外观模式", selection: $themeMode) {
                    Text("跟随系统").tag(0)
                    Text("浅色").tag(1)
                    Text("深色").tag(2)
                }
                .pickerStyle(.segmented)
            }

            Section("卡片") {
                Picker("卡片大小", selection: $cardSizeOption) {
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
    @State private var highlightExtensions: [String: String] = PreviewConfigManager.shared.config.highlightExtensions
    @State private var plainTextExtensions: [String] = PreviewConfigManager.shared.config.plainTextExtensions
    @State private var newHighlightExt = ""
    @State private var newHighlightLang = ""
    @State private var newPlainExt = ""
    @State private var showingClearHistoryAlert = false
    @State private var showingClearCacheAlert = false

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
