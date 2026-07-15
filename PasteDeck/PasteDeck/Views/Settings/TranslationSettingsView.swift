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

    @State private var providerConfigurations: [TranslationProviderConfiguration] = []
    @State private var llmConfigurations: [LLMTranslationConfiguration] = []
    @State private var recordingAction: TranslationShortcutAction?
    @State private var providerTestMessages: [UUID: String] = [:]
    @State private var testingProviderIDs: Set<UUID> = []
    @State private var llmTestMessages: [UUID: String] = [:]
    @State private var testingLLMIds: Set<UUID> = []
    @State private var availableLLMModels: [UUID: [String]] = [:]
    @State private var loadingLLMModelIDs: Set<UUID> = []
    @State private var llmModelFetchMessages: [UUID: String] = [:]
    @State private var inputMonitoringGranted = CGPreflightListenEventAccess()
    @State private var credentialStorageError: String?

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

    /// 当前可用于自动划词气泡的已启用服务；设置顺序只影响气泡，不改变完整翻译工作区的并行策略。
    private var availableAutomaticSelectionServices: [AutomaticSelectionTranslationService] {
        providerConfigurations.filter(\.isConfigured).map(AutomaticSelectionTranslationService.api)
            + llmConfigurations.filter(\.isConfigured).map(AutomaticSelectionTranslationService.llm)
    }

    /// 设置页展示顺序为已选服务在前、未选服务在后；旧数据默认选中全部可用服务。
    private var displayedAutomaticSelectionServices: [AutomaticSelectionTranslationService] {
        let services = availableAutomaticSelectionServices
        guard appSettings.automaticSelectionTranslationServiceOrderJSON != nil else {
            return services
        }

        let servicesByReference = Dictionary(
            uniqueKeysWithValues: services.map { ($0.reference, $0) }
        )
        let selectedServices = appSettings.automaticSelectionTranslationServiceOrder.compactMap { reference in
            servicesByReference[reference]
        }
        let selectedReferences = Set(selectedServices.map(\.reference))
        return selectedServices + services.filter { !selectedReferences.contains($0.reference) }
    }

    var body: some View {
        SettingsContentStack {
            SettingsCard(title: "翻译入口", icon: "character.cursor.ibeam") {
                SettingsRow(
                    title: "划词自动翻译",
                    subtitle: "鼠标划词后在选区旁显示轻量译文气泡；默认关闭"
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
                    automaticSelectionServicesSection

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

            SettingsCard(
                title: "常规翻译 API",
                icon: "network",
                footer: "完整凭据存于 macOS Keychain。同一服务可保存多套密钥；同一种 API 同时只能启用一套密钥。已启用的不同 API 会在翻译窗口中并行生成独立译文。"
            ) {
                VStack(spacing: 12) {
                    ForEach(providerConfigurations) { configuration in
                        providerConfigurationView(configuration)
                    }

                    Menu {
                        ForEach(TranslationProviderKind.allCases) { kind in
                            Button {
                                addProviderConfiguration(kind: kind)
                            } label: {
                                Label {
                                    Text(kind.displayName)
                                } icon: {
                                    TranslationBrandLogoView(brand: kind.translationBrand, size: 18)
                                }
                            }
                        }
                    } label: {
                        addConfigurationLabel(
                            title: "添加翻译服务",
                            subtitle: "百度、腾讯云、有道或阿里云",
                            systemImage: "plus"
                        )
                    }
                    .menuIndicator(.hidden)
                    .buttonStyle(.plain)
                }
            }

            SettingsCard(title: "大模型 API", icon: "sparkles") {
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkles.rectangle.stack")
                            .foregroundColor(.purple)
                        Text("添加 OpenAI-compatible 服务后，可从接口获取模型或直接输入模型名称。每次调用都会追加结果卡片，方便横向比较。")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 4)

                    ForEach(llmConfigurations) { configuration in
                        llmConfigurationView(configuration)
                    }

                    Menu {
                        ForEach(LLMTranslationPreset.allCases) { preset in
                            Button {
                                addLLMConfiguration(preset: preset)
                            } label: {
                                Label {
                                    Text(preset.displayName)
                                } icon: {
                                    TranslationBrandLogoView(brand: preset.translationBrand, size: 18)
                                }
                            }
                        }
                        Divider()
                        Button("自定义 OpenAI-compatible 端点") {
                            addLLMConfiguration(preset: nil)
                        }
                    } label: {
                        addConfigurationLabel(
                            title: "添加大模型服务",
                            subtitle: "使用预设，或连接自定义端点",
                            systemImage: "sparkles"
                        )
                    }
                    .menuIndicator(.hidden)
                    .buttonStyle(.plain)
                }
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
            providerConfigurations = appSettings.translationProviderConfigurations
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
        .alert(
            "无法保存密钥",
            isPresented: Binding(
                get: { credentialStorageError != nil },
                set: { isPresented in
                    if !isPresented {
                        credentialStorageError = nil
                    }
                }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(credentialStorageError ?? "请稍后重试。")
        }
    }

    @ViewBuilder
    private var automaticSelectionServicesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("气泡翻译服务")
                        .font(.system(size: 13, weight: .medium))
                    Text("可选择多个 API 或大模型；第一个为默认服务，气泡内可随时切换")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text("\(automaticSelectionServiceOrderForEditing.count) 个")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.06), in: Capsule())
            }

            if displayedAutomaticSelectionServices.isEmpty {
                Label("请先启用并完成至少一套常规 API 或大模型配置", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
            } else {
                ForEach(displayedAutomaticSelectionServices, id: \.reference.id) { service in
                    automaticSelectionServiceRow(service)
                }
            }
        }
    }

    private var automaticSelectionServiceOrderForEditing: [AutomaticSelectionTranslationServiceReference] {
        if appSettings.automaticSelectionTranslationServiceOrderJSON == nil {
            return availableAutomaticSelectionServices.map(\.reference)
        }

        let availableReferences = Set(availableAutomaticSelectionServices.map(\.reference))
        return appSettings.automaticSelectionTranslationServiceOrder.filter(availableReferences.contains)
    }

    private func automaticSelectionServiceRow(_ service: AutomaticSelectionTranslationService) -> some View {
        let reference = service.reference
        let selectedOrder = automaticSelectionServiceOrderForEditing
        let selectedIndex = selectedOrder.firstIndex(of: reference)

        return HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { automaticSelectionServiceOrderForEditing.contains(reference) },
                set: { setAutomaticSelectionService(reference, enabled: $0) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            automaticSelectionServiceLogo(service)

            VStack(alignment: .leading, spacing: 2) {
                Text(service.displayName)
                    .font(.system(size: 12, weight: .semibold))
                Text(service.detail)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let selectedIndex {
                Text(selectedIndex == 0 ? "默认" : "\(selectedIndex + 1)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(selectedIndex == 0 ? .accentColor : .secondary)
                    .frame(minWidth: 30)

                Button {
                    moveAutomaticSelectionService(reference, offset: -1)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.borderless)
                .disabled(selectedIndex == 0)
                .help("上移")

                Button {
                    moveAutomaticSelectionService(reference, offset: 1)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.borderless)
                .disabled(selectedIndex == selectedOrder.count - 1)
                .help("下移")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func automaticSelectionServiceLogo(_ service: AutomaticSelectionTranslationService) -> some View {
        switch service {
        case .api(let configuration):
            TranslationBrandLogoView(brand: configuration.kind.translationBrand, size: 22)
        case .llm(let configuration):
            TranslationBrandLogoView(brand: configuration.translationBrand, size: 22)
        }
    }

    private func setAutomaticSelectionService(
        _ reference: AutomaticSelectionTranslationServiceReference,
        enabled: Bool
    ) {
        var order = automaticSelectionServiceOrderForEditing
        if enabled {
            if !order.contains(reference) {
                order.append(reference)
            }
        } else {
            order.removeAll { $0 == reference }
        }
        appSettings.automaticSelectionTranslationServiceOrder = order
        saveAndReload()
    }

    private func moveAutomaticSelectionService(
        _ reference: AutomaticSelectionTranslationServiceReference,
        offset: Int
    ) {
        var order = automaticSelectionServiceOrderForEditing
        guard let sourceIndex = order.firstIndex(of: reference) else { return }
        let destinationIndex = sourceIndex + offset
        guard order.indices.contains(destinationIndex) else { return }
        order.swapAt(sourceIndex, destinationIndex)
        appSettings.automaticSelectionTranslationServiceOrder = order
        saveAndReload()
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

    private func addConfigurationLabel(title: String, subtitle: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.accentColor)
                .frame(width: 32, height: 32)
                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.14), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        )
    }

    private func configurationFieldLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.secondary)
            .frame(width: 92, alignment: .leading)
    }

    @ViewBuilder
    private func providerConfigurationView(_ configuration: TranslationProviderConfiguration) -> some View {
        let binding = bindingForProvider(configuration.id)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                TranslationBrandLogoView(brand: configuration.kind.translationBrand)

                VStack(alignment: .leading, spacing: 2) {
                    Text(configuration.name.isEmpty ? configuration.kind.displayName : configuration.name)
                        .font(.system(size: 13, weight: .semibold))
                    Text(configuration.kind.displayName)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(configuration.enabled ? "已启用" : "未启用")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(configuration.enabled ? .green : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        (configuration.enabled ? Color.green : Color.secondary).opacity(0.1),
                        in: Capsule()
                    )

                Toggle("启用", isOn: Binding(
                    get: { configuration.enabled },
                    set: { setProviderEnabled(configuration.id, enabled: $0) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()

                Button(role: .destructive) {
                    TranslationCredentialStore.deleteCredential(reference: configuration.credentialReference)
                    providerConfigurations.removeAll { $0.id == configuration.id }
                    providerTestMessages[configuration.id] = nil
                    testingProviderIDs.remove(configuration.id)
                    saveProviderConfigurations()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("删除这套密钥")
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    configurationFieldLabel("显示名称", systemImage: "tag")
                    TextField("例如：工作账号", text: binding.name)
                        .translationSettingsField()
                }

                GridRow {
                    configurationFieldLabel(configuration.kind.credentialIdTitle, systemImage: "person.text.rectangle")
                    TextField(configuration.kind.credentialIdTitle, text: binding.credentialId)
                        .translationSettingsField()
                }

                GridRow {
                    configurationFieldLabel(configuration.kind.credentialSecretTitle, systemImage: "key")
                    SecureField(configuration.kind.credentialSecretTitle, text: binding.credentialSecret)
                        .translationSettingsField()
                }

                if configuration.kind == .tencent {
                    GridRow {
                        configurationFieldLabel("地域", systemImage: "mappin.and.ellipse")
                        TextField("例如 ap-guangzhou", text: binding.region)
                            .translationSettingsField()
                    }
                }
            }

            HStack(spacing: 10) {
                Toggle("并发处理长文本", isOn: binding.allowsConcurrentRequests)
                    .toggleStyle(.switch)
                    .font(.system(size: 11, weight: .medium))

                Spacer()

                Button {
                    testProvider(configuration.id)
                } label: {
                    Label("测试连接", systemImage: "wave.3.right")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(testingProviderIDs.contains(configuration.id) || !configuration.isConfigured)

                if testingProviderIDs.contains(configuration.id) {
                    ProgressView().controlSize(.small)
                }
                if let message = providerTestMessages[configuration.id] {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundColor(message.hasPrefix("可用") ? .green : .orange)
                }
            }
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(configuration.enabled ? Color.accentColor.opacity(0.28) : Color.primary.opacity(0.07), lineWidth: 1)
        )
    }

    private func bindingForProvider(_ id: UUID) -> Binding<TranslationProviderConfiguration> {
        Binding(
            get: { providerConfigurations.first(where: { $0.id == id }) ?? TranslationProviderConfiguration(
                id: id,
                kind: .baidu,
                name: "百度翻译",
                enabled: false,
                credentialId: "",
                credentialSecret: "",
                region: "ap-guangzhou",
                allowsConcurrentRequests: false
            ) },
            set: { updated in
                guard let index = providerConfigurations.firstIndex(where: { $0.id == id }) else { return }
                providerConfigurations[index] = updated
                if updated.enabled {
                    setProviderEnabled(id, enabled: true, savesChanges: false)
                }
                saveProviderConfigurations()
            }
        )
    }

    private func addProviderConfiguration(kind: TranslationProviderKind) {
        let existingCount = providerConfigurations.filter { $0.kind == kind }.count
        providerConfigurations.append(TranslationProviderConfiguration(
            kind: kind,
            name: existingCount == 0 ? kind.displayName : "\(kind.displayName) 密钥 \(existingCount + 1)",
            enabled: false,
            credentialId: "",
            credentialSecret: "",
            region: "ap-guangzhou",
            allowsConcurrentRequests: false
        ))
        saveProviderConfigurations()
    }

    /// 开启一个密钥时仅关闭同类型的其他密钥，保留其内容以便稍后无损切换。
    private func setProviderEnabled(_ id: UUID, enabled: Bool, savesChanges: Bool = true) {
        guard let target = providerConfigurations.first(where: { $0.id == id }) else { return }
        for index in providerConfigurations.indices {
            if providerConfigurations[index].id == id {
                providerConfigurations[index].enabled = enabled
            } else if enabled && providerConfigurations[index].kind == target.kind {
                providerConfigurations[index].enabled = false
            }
        }
        if savesChanges {
            saveProviderConfigurations()
        }
    }

    @ViewBuilder
    private func llmConfigurationView(_ configuration: LLMTranslationConfiguration) -> some View {
        let binding = bindingForLLM(configuration.id)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                TranslationBrandLogoView(brand: configuration.translationBrand)

                VStack(alignment: .leading, spacing: 2) {
                    Text(configuration.name.isEmpty ? "大模型服务" : configuration.name)
                        .font(.system(size: 13, weight: .semibold))
                    Text(configuration.model.isEmpty ? "等待选择模型" : configuration.model)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Text(configuration.enabled ? "已启用" : "未启用")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(configuration.enabled ? .green : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        (configuration.enabled ? Color.green : Color.secondary).opacity(0.1),
                        in: Capsule()
                    )

                Toggle("启用", isOn: binding.enabled)
                    .toggleStyle(.switch)
                    .labelsHidden()

                Button(role: .destructive) {
                    TranslationCredentialStore.deleteCredential(reference: configuration.credentialReference)
                    llmConfigurations.removeAll { $0.id == configuration.id }
                    availableLLMModels[configuration.id] = nil
                    loadingLLMModelIDs.remove(configuration.id)
                    llmModelFetchMessages[configuration.id] = nil
                    saveLLMConfigurations()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("删除这个大模型服务")
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    configurationFieldLabel("显示名称", systemImage: "tag")
                    TextField("例如：DeepSeek 翻译", text: binding.name)
                        .translationSettingsField()
                }

                GridRow {
                    configurationFieldLabel("API 地址", systemImage: "link")
                    TextField("https://api.example.com/v1", text: binding.baseURL)
                        .translationSettingsField()
                }

                GridRow {
                    configurationFieldLabel("API Key", systemImage: "key")
                    SecureField("sk-…", text: binding.apiKey)
                        .translationSettingsField()
                }

                GridRow {
                    configurationFieldLabel("模型", systemImage: "cpu")
                    HStack(spacing: 6) {
                        TextField("获取后选择，或手动输入模型名称", text: binding.model)
                            .translationSettingsField()

                        if let models = availableLLMModels[configuration.id], !models.isEmpty {
                            Menu {
                                ForEach(models, id: \.self) { model in
                                    Button(model) {
                                        binding.model.wrappedValue = model
                                    }
                                }
                            } label: {
                                Image(systemName: "chevron.up.chevron.down")
                                    .frame(width: 26, height: 26)
                            }
                            .menuIndicator(.hidden)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("选择已获取的模型")
                        }

                        Button {
                            fetchLLMModels(configuration.id)
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .frame(width: 26, height: 26)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(
                            loadingLLMModelIDs.contains(configuration.id)
                                || configuration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                        .help("从服务商获取模型")

                        if loadingLLMModelIDs.contains(configuration.id) {
                            ProgressView().controlSize(.small)
                        }
                    }
                }

            }

            if let message = llmModelFetchMessages[configuration.id] {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(message.hasPrefix("已获取") ? .green : .orange)
            }

            HStack(spacing: 10) {
                Spacer()

                Button {
                    testLLM(configuration.id)
                } label: {
                    Label("测试连接", systemImage: "wave.3.right")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
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
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(configuration.enabled ? Color.purple.opacity(0.28) : Color.primary.opacity(0.07), lineWidth: 1)
        )
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

    /// 通过服务商预设或空白自定义配置新建一套大模型 API；模型字段刻意保持空白，由用户获取或输入。
    private func addLLMConfiguration(preset: LLMTranslationPreset?) {
        let configuration = LLMTranslationConfiguration(
            name: preset?.displayName ?? "自定义大模型",
            baseURL: preset?.baseURL ?? "",
            model: ""
        )
        llmConfigurations.append(configuration)
        saveLLMConfigurations()
    }

    private func fetchLLMModels(_ id: UUID) {
        guard let configuration = llmConfigurations.first(where: { $0.id == id }) else { return }
        loadingLLMModelIDs.insert(id)
        llmModelFetchMessages[id] = nil
        LLMTranslationService(configuration: configuration).fetchAvailableModels { result in
            DispatchQueue.main.async {
                loadingLLMModelIDs.remove(id)
                switch result {
                case .success(let models):
                    availableLLMModels[id] = models
                    llmModelFetchMessages[id] = models.isEmpty
                        ? "服务商未返回可用模型，请手动输入模型名称。"
                        : "已获取 \(models.count) 个模型，可选择或继续手动输入。"
                case .failure(let error):
                    llmModelFetchMessages[id] = "获取失败：\(error.localizedDescription)。可手动输入模型名称。"
                }
            }
        }
    }

    private func saveProviderConfigurations() {
        let credentials: [String: TranslationProviderCredential] = Dictionary(uniqueKeysWithValues: providerConfigurations.compactMap { configuration in
            let hasCredential = !configuration.credentialId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !configuration.credentialSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            guard hasCredential else { return nil }
            return (
                configuration.credentialReference,
                TranslationProviderCredential(
                    credentialID: configuration.credentialId,
                    credentialSecret: configuration.credentialSecret
                )
            )
        })
        let referencesToDelete = Set(providerConfigurations.compactMap { configuration -> String? in
            let hasCredential = !configuration.credentialId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !configuration.credentialSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return hasCredential ? nil : configuration.credentialReference
        })
        guard TranslationCredentialStore.replaceProviderCredentials(
            credentials,
            deleting: referencesToDelete
        ) else {
            credentialStorageError = "无法写入 macOS Keychain。请确认登录钥匙串已解锁后重试。"
            return
        }
        credentialStorageError = nil
        appSettings.translationProviderConfigurations = providerConfigurations
        try? modelContext.save()
        NotificationCenter.default.post(name: .translationSettingsDidChange, object: nil)
    }

    private func saveLLMConfigurations() {
        let credentials: [String: LLMTranslationCredential] = Dictionary(uniqueKeysWithValues: llmConfigurations.compactMap { configuration in
            guard !configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return (
                configuration.credentialReference,
                LLMTranslationCredential(apiKey: configuration.apiKey)
            )
        })
        let referencesToDelete = Set(llmConfigurations.compactMap { configuration -> String? in
            configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? configuration.credentialReference
                : nil
        })
        guard TranslationCredentialStore.replaceLLMCredentials(
            credentials,
            deleting: referencesToDelete
        ) else {
            credentialStorageError = "无法写入 macOS Keychain。请确认登录钥匙串已解锁后重试。"
            return
        }
        credentialStorageError = nil
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

    private func testProvider(_ id: UUID) {
        guard let configuration = providerConfigurations.first(where: { $0.id == id }) else { return }
        testingProviderIDs.insert(id)
        providerTestMessages[id] = nil
        let startDate = Date()
        let service = TranslateService(configuration: configuration)
        service.translateSegment("hello", from: "en", to: .simplifiedChinese) { result in
            DispatchQueue.main.async {
                testingProviderIDs.remove(id)
                let latency = Int(Date().timeIntervalSince(startDate) * 1000)
                switch result {
                case .success:
                    providerTestMessages[id] = "可用 · \(latency) ms"
                case .failure(let error):
                    providerTestMessages[id] = "失败 · \(latency) ms · \(error.localizedDescription)"
                }
            }
        }
    }

    private func testLLM(_ id: UUID) {
        guard let configuration = llmConfigurations.first(where: { $0.id == id }) else { return }
        testingLLMIds.insert(id)
        llmTestMessages[id] = nil
        let startDate = Date()
        LLMTranslationService(configuration: configuration).translate("hello", targetLanguage: .simplifiedChinese) { result in
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
