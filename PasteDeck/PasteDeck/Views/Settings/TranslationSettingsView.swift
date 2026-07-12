//
//  TranslationSettingsView.swift
//  PasteDeck
//
//  Dedicated translation settings for triggers, shortcuts, API providers, and LLM endpoints.
//

import AppKit
import SwiftData
import SwiftUI

/// 翻译设置页可录制的快捷键动作。
private enum TranslationShortcutAction: String, Identifiable {
    /// 翻译前台应用选中文本，默认 Option + D。
    case selection
    /// 区域截图并 OCR 翻译，默认 Option + S。
    case screenshot
    /// 打开输入翻译窗口，默认 Option + A。
    case input

    var id: String { rawValue }
}

struct TranslationSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settings: [AppSettings]

    @State private var providerConfiguration = TranslationProviderConfiguration(
        kind: .baidu,
        name: "百度翻译",
        enabled: false,
        credentialId: "",
        credentialSecret: "",
        region: "ap-guangzhou",
        allowsConcurrentRequests: false
    )
    @State private var llmConfigurations: [LLMTranslationConfiguration] = []
    @State private var recordingAction: TranslationShortcutAction?
    @State private var providerTestMessage: String?
    @State private var providerTestSucceeded = false
    @State private var providerTesting = false
    @State private var llmTestMessages: [UUID: String] = [:]
    @State private var testingLLMIds: Set<UUID> = []
    @State private var inputMonitoringGranted = CGPreflightListenEventAccess()

    private let permissionStatusTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var appSettings: AppSettings {
        if let existing = settings.first {
            return existing
        }
        let created = AppSettings()
        modelContext.insert(created)
        try? modelContext.save()
        return created
    }

    var body: some View {
        SettingsContentStack {
            SettingsCard(title: "翻译入口", icon: "character.cursor.ibeam") {
                SettingsRow(
                    title: "划词自动翻译",
                    subtitle: "鼠标划词后自动打开翻译窗口；默认关闭"
                ) {
                    Toggle("", isOn: Binding(
                        get: { appSettings.automaticSelectionTranslationEnabled ?? false },
                        set: {
                            appSettings.automaticSelectionTranslationEnabled = $0
                            saveAndReload()
                        }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }

                if appSettings.automaticSelectionTranslationEnabled ?? false {
                    SettingsDivider()
                    SettingsRow(
                        title: "输入监控",
                        subtitle: inputMonitoringGranted
                            ? "已授权，可可靠识别其他应用中的鼠标划词"
                            : "未授权时，浏览器和多数第三方应用无法触发划词翻译"
                    ) {
                        HStack(spacing: 8) {
                            Label(
                                inputMonitoringGranted ? "已开启" : "未开启",
                                systemImage: inputMonitoringGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                            )
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(inputMonitoringGranted ? .green : .orange)

                            if !inputMonitoringGranted {
                                Button("打开系统设置") {
                                    requestInputMonitoringPermission()
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }

                SettingsDivider()
                shortcutRow(
                    title: "翻译所选文本",
                    subtitle: "读取前台应用当前选中的文字并打开翻译窗口",
                    action: .selection,
                    enabled: Binding(
                        get: { appSettings.selectionTranslationShortcutEnabled ?? true },
                        set: { appSettings.selectionTranslationShortcutEnabled = $0; saveAndReload() }
                    ),
                    display: formatShortcut(
                        display: appSettings.selectionTranslationDisplay ?? "D",
                        modifiers: appSettings.selectionTranslationModifiers ?? Int(NSEvent.ModifierFlags.option.rawValue)
                    )
                )

                SettingsDivider()
                shortcutRow(
                    title: "截图 OCR 翻译",
                    subtitle: "选择屏幕区域，识别其中的文字后自动翻译",
                    action: .screenshot,
                    enabled: Binding(
                        get: { appSettings.screenshotTranslationShortcutEnabled ?? true },
                        set: { appSettings.screenshotTranslationShortcutEnabled = $0; saveAndReload() }
                    ),
                    display: formatShortcut(
                        display: appSettings.screenshotTranslationDisplay ?? "S",
                        modifiers: appSettings.screenshotTranslationModifiers ?? Int(NSEvent.ModifierFlags.option.rawValue)
                    )
                )

                SettingsDivider()
                shortcutRow(
                    title: "输入翻译",
                    subtitle: "打开空白翻译窗口，输入后按回车翻译",
                    action: .input,
                    enabled: Binding(
                        get: { appSettings.inputTranslationShortcutEnabled ?? true },
                        set: { appSettings.inputTranslationShortcutEnabled = $0; saveAndReload() }
                    ),
                    display: formatShortcut(
                        display: appSettings.inputTranslationDisplay ?? "A",
                        modifiers: appSettings.inputTranslationModifiers ?? Int(NSEvent.ModifierFlags.option.rawValue)
                    )
                )

                SettingsDivider()
                Text("划词读取需要“辅助功能”和“输入监控”权限；首次使用截图 OCR 时，macOS 可能请求“屏幕录制”权限。")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            SettingsCard(title: "常规翻译 API", icon: "network") {
                SettingsRow(title: "默认翻译服务", subtitle: "翻译窗口优先使用该服务") {
                    HStack(spacing: 10) {
                        Picker("", selection: Binding(
                            get: { providerConfiguration.kind },
                            set: { kind in
                                providerConfiguration.kind = kind
                                providerConfiguration.name = kind.displayName
                                providerConfiguration.credentialId = ""
                                providerConfiguration.credentialSecret = ""
                                providerConfiguration.region = "ap-guangzhou"
                                providerTestMessage = nil
                                saveProvider()
                            }
                        )) {
                            ForEach(TranslationProviderKind.allCases) { provider in
                                Text(provider.displayName).tag(provider)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 155)

                        Toggle("启用", isOn: Binding(
                            get: { providerConfiguration.enabled },
                            set: { providerConfiguration.enabled = $0; saveProvider() }
                        ))
                        .toggleStyle(.switch)
                    }
                }

                SettingsDivider()

                VStack(alignment: .leading, spacing: 10) {
                    TextField(providerConfiguration.kind.credentialIdTitle, text: Binding(
                        get: { providerConfiguration.credentialId },
                        set: { providerConfiguration.credentialId = $0; saveProvider() }
                    ))
                    .translationSettingsField()

                    SecureField(providerConfiguration.kind.credentialSecretTitle, text: Binding(
                        get: { providerConfiguration.credentialSecret },
                        set: { providerConfiguration.credentialSecret = $0; saveProvider() }
                    ))
                    .translationSettingsField()

                    if providerConfiguration.kind == .tencent {
                        TextField("地域，例如 ap-guangzhou", text: Binding(
                            get: { providerConfiguration.region },
                            set: { providerConfiguration.region = $0; saveProvider() }
                        ))
                        .translationSettingsField()
                    }

                    SettingsRow(title: "并发分段", subtitle: "账号配额允许时并发翻译长文本，缩短等待时间") {
                        Toggle("", isOn: Binding(
                            get: { providerConfiguration.allowsConcurrentRequests },
                            set: { providerConfiguration.allowsConcurrentRequests = $0; saveProvider() }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                    }

                    HStack(spacing: 10) {
                        Button {
                            testProvider()
                        } label: {
                            Label("检测连接与延迟", systemImage: "gauge.with.dots.needle.67percent")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(providerTesting || !providerConfiguration.isConfigured)

                        if providerTesting {
                            ProgressView().controlSize(.small)
                        }
                        if let providerTestMessage {
                            Label(
                                providerTestMessage,
                                systemImage: providerTestSucceeded ? "checkmark.circle.fill" : "xmark.circle.fill"
                            )
                            .font(.system(size: 12))
                            .foregroundColor(providerTestSucceeded ? .green : .orange)
                        }
                    }
                }

            }

            SettingsCard(title: "大模型 API", icon: "sparkles") {
                Text("可添加多套 OpenAI-compatible 端点。默认仍使用上方翻译 API；仅在结果页点击“使用大模型重译”后调用。")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !llmConfigurations.isEmpty {
                    SettingsDivider()
                }

                ForEach(llmConfigurations) { configuration in
                    llmConfigurationView(configuration)
                    if configuration.id != llmConfigurations.last?.id {
                        SettingsDivider()
                    }
                }

                if !llmConfigurations.isEmpty {
                    SettingsDivider()
                }

                Button {
                    let configuration = LLMTranslationConfiguration(
                        name: "DeepSeek",
                        baseURL: "https://api.deepseek.com/v1",
                        model: "deepseek-chat"
                    )
                    llmConfigurations.append(configuration)
                    saveLLMConfigurations()
                } label: {
                    Label("添加大模型 API", systemImage: "plus.circle")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .background {
            HotkeyRecorderView(isRecording: recordingAction != nil) { keyCode, modifiers, display in
                saveShortcut(keyCode: keyCode, modifiers: modifiers, display: display)
            } onCancel: {
                recordingAction = nil
                NotificationCenter.default.post(name: .translationSettingsDidChange, object: nil)
            }
            .frame(width: 0, height: 0)
        }
        .onAppear {
            providerConfiguration = appSettings.translationProviderConfiguration
            llmConfigurations = appSettings.llmTranslationConfigurations
            inputMonitoringGranted = CGPreflightListenEventAccess()
        }
        .onReceive(permissionStatusTimer) { _ in
            let currentPermission = CGPreflightListenEventAccess()
            guard currentPermission != inputMonitoringGranted else { return }
            inputMonitoringGranted = currentPermission
            if appSettings.automaticSelectionTranslationEnabled ?? false {
                NotificationCenter.default.post(name: .translationSettingsDidChange, object: nil)
            }
        }
        .onDisappear {
            recordingAction = nil
            NotificationCenter.default.post(name: .translationSettingsDidChange, object: nil)
        }
    }

    @ViewBuilder
    private func shortcutRow(
        title: String,
        subtitle: String,
        action: TranslationShortcutAction,
        enabled: Binding<Bool>,
        display: String
    ) -> some View {
        SettingsRow(title: title, subtitle: subtitle) {
            HStack(spacing: 8) {
                Toggle("", isOn: enabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                Text(recordingAction == action ? "请按新快捷键…" : display)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.primary.opacity(0.07)))
                Button(recordingAction == action ? "取消" : "修改") {
                    if recordingAction == action {
                        recordingAction = nil
                        NotificationCenter.default.post(name: .translationSettingsDidChange, object: nil)
                    } else {
                        unregisterShortcut(action)
                        recordingAction = action
                    }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private func llmConfigurationView(_ configuration: LLMTranslationConfiguration) -> some View {
        let binding = bindingForLLM(configuration.id)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("配置名称", text: binding.name)
                    .translationSettingsField()
                Toggle("启用", isOn: binding.enabled)
                    .toggleStyle(.switch)
                Button(role: .destructive) {
                    llmConfigurations.removeAll { $0.id == configuration.id }
                    saveLLMConfigurations()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
            TextField("API 地址，例如 https://api.deepseek.com/v1", text: binding.baseURL)
                .translationSettingsField()
            SecureField("API Key", text: binding.apiKey)
                .translationSettingsField()
            TextField("模型，例如 deepseek-chat", text: binding.model)
                .translationSettingsField()

            HStack(spacing: 10) {
                Button {
                    testLLM(configuration.id)
                } label: {
                    Label("检测连接与延迟", systemImage: "gauge.with.dots.needle.67percent")
                }
                .buttonStyle(.bordered)
                .disabled(testingLLMIds.contains(configuration.id) || !configuration.isConfigured)
                if testingLLMIds.contains(configuration.id) {
                    ProgressView().controlSize(.small)
                }
                if let message = llmTestMessages[configuration.id] {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundColor(message.hasPrefix("可用") ? .green : .orange)
                }
            }
        }
    }

    private func bindingForLLM(_ id: UUID) -> Binding<LLMTranslationConfiguration> {
        Binding(
            get: { llmConfigurations.first(where: { $0.id == id }) ?? LLMTranslationConfiguration(id: id) },
            set: { updated in
                guard let index = llmConfigurations.firstIndex(where: { $0.id == id }) else { return }
                llmConfigurations[index] = updated
                saveLLMConfigurations()
            }
        )
    }

    private func saveProvider() {
        appSettings.translationProviderConfiguration = providerConfiguration
        try? modelContext.save()
        NotificationCenter.default.post(name: .translationSettingsDidChange, object: nil)
    }

    private func saveLLMConfigurations() {
        appSettings.llmTranslationConfigurations = llmConfigurations
        try? modelContext.save()
        NotificationCenter.default.post(name: .translationSettingsDidChange, object: nil)
    }

    private func saveAndReload() {
        try? modelContext.save()
        NotificationCenter.default.post(name: .translationSettingsDidChange, object: nil)
    }

    private func requestInputMonitoringPermission() {
        if !CGPreflightListenEventAccess() {
            _ = CGRequestListenEventAccess()
        }
        if let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(settingsURL)
        }
    }

    private func testProvider() {
        providerTesting = true
        providerTestMessage = nil
        let startDate = Date()
        let service = TranslateService(configuration: providerConfiguration)
        service.translateSegment("hello", from: "en", to: "zh") { result in
            DispatchQueue.main.async {
                providerTesting = false
                let latency = Int(Date().timeIntervalSince(startDate) * 1000)
                switch result {
                case .success:
                    providerTestSucceeded = true
                    providerTestMessage = "可用 · \(latency) ms"
                case .failure(let error):
                    providerTestSucceeded = false
                    providerTestMessage = "失败 · \(latency) ms · \(error.localizedDescription)"
                }
            }
        }
    }

    private func testLLM(_ id: UUID) {
        guard let configuration = llmConfigurations.first(where: { $0.id == id }) else { return }
        testingLLMIds.insert(id)
        llmTestMessages[id] = nil
        let startDate = Date()
        LLMTranslationService(configuration: configuration).translate("hello", targetLanguage: "zh") { result in
            DispatchQueue.main.async {
                testingLLMIds.remove(id)
                let latency = Int(Date().timeIntervalSince(startDate) * 1000)
                switch result {
                case .success:
                    llmTestMessages[id] = "可用 · \(latency) ms"
                case .failure(let error):
                    llmTestMessages[id] = "失败 · \(latency) ms · \(error.localizedDescription)"
                }
            }
        }
    }

    private func unregisterShortcut(_ action: TranslationShortcutAction) {
        let identifier: HotKeyIdentifier
        switch action {
        case .selection: identifier = .selectionTranslation
        case .screenshot: identifier = .screenshotTranslation
        case .input: identifier = .inputTranslation
        }
        HotKeyManager.shared.unregister(identifier: identifier)
    }

    private func saveShortcut(keyCode: UInt32, modifiers: Int, display: String) {
        guard let recordingAction else { return }
        switch recordingAction {
        case .selection:
            appSettings.selectionTranslationKeyCode = Int(keyCode)
            appSettings.selectionTranslationModifiers = modifiers
            appSettings.selectionTranslationDisplay = display
        case .screenshot:
            appSettings.screenshotTranslationKeyCode = Int(keyCode)
            appSettings.screenshotTranslationModifiers = modifiers
            appSettings.screenshotTranslationDisplay = display
        case .input:
            appSettings.inputTranslationKeyCode = Int(keyCode)
            appSettings.inputTranslationModifiers = modifiers
            appSettings.inputTranslationDisplay = display
        }
        self.recordingAction = nil
        saveAndReload()
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

private extension View {
    func translationSettingsField() -> some View {
        textFieldStyle(.plain)
            .font(.system(size: 13))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.045)))
    }
}
