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

struct GeneralSettingsView: View {
    @State private var launchAtLogin = true
    @State private var showMenuBarIcon = true

    var body: some View {
        Form {
            Section("启动") {
                Toggle("开机启动", isOn: $launchAtLogin)
            }

            Section("菜单栏") {
                Toggle("显示菜单栏图标", isOn: $showMenuBarIcon)
            }
        }
        .formStyle(.grouped)
    }
}

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
                    Text("\(CacheManager().getTotalCacheSize() / 1024 / 1024) MB")
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct FilterSettingsView: View {
    @State private var blacklistedApps: [String] = []

    var body: some View {
        Form {
            Section("应用黑名单") {
                Text("以下应用的复制内容将不会被记录")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                if blacklistedApps.isEmpty {
                    Text("暂无黑名单应用")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else {
                    List {
                        ForEach(blacklistedApps, id: \.self) { app in
                            Text(app)
                        }
                        .onDelete { indexSet in
                            blacklistedApps.remove(atOffsets: indexSet)
                        }
                    }
                    .frame(height: 150)
                }

                Button("添加应用") {
                    // TODO: Show app selection
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct AppearanceSettingsView: View {
    @State private var themeMode = 0
    @State private var cardSize = 1

    var body: some View {
        Form {
            Section("主题") {
                Picker("外观模式", selection: $themeMode) {
                    Text("跟随系统").tag(0)
                    Text("亮色").tag(1)
                    Text("暗色").tag(2)
                }
                .pickerStyle(.radioGroup)
            }

            Section("卡片") {
                Picker("卡片大小", selection: $cardSize) {
                    Text("小").tag(0)
                    Text("中").tag(1)
                    Text("大").tag(2)
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct AdvancedSettingsView: View {
    @State private var showingClearHistoryAlert = false
    @State private var showingClearCacheAlert = false

    var body: some View {
        Form {
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
                    Text("1.0.0")
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
