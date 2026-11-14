//
//  CodexRouterToolView.swift
//  PasteDeck
//
//  工具中心「Codex 模型路由」界面：
//  顶部 = 路由服务状态 + 一键启用/关闭 + 恢复原始配置；
//  中部 = 官方登录状态 + 第三方端点与模型管理；
//  底部 = 代理设置、连通性测试与最近错误。
//  视觉沿用工具中心既有的卡片语言；所有持久化走 CodexRouterController。
//

import SwiftUI
import CodexRouterKit

struct CodexRouterToolView: View {
    @State private var controller = CodexRouterController()
    @State private var overview: RouterOverview?
    @State private var document = RouterEndpointsDocument.empty()
    @State private var busy = false
    @State private var actionMessage: String?
    @State private var actionMessageIsError = false
    @State private var editingEndpoint: RouterEndpoint?
    @State private var editingAPIKey: String = ""
    @State private var isNewEndpoint = false
    @State private var showingProxyEditor = false
    @State private var proxyDraft = RouterProxyConfig.standard()
    @State private var proxyPasswordDraft = ""
    @State private var proxyTestResults: [(target: String, status: Int?, error: String?)] = []
    @State private var confirmation: ConfirmationKind?
    @State private var refreshTimer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

    enum ConfirmationKind: String, Identifiable {
        case disable
        case restore

        var id: String { rawValue }

        var title: String {
            switch self {
            case .disable: return "关闭 Codex 模型路由？"
            case .restore: return "恢复原始 Codex 配置？"
            }
        }

        var message: String {
            switch self {
            case .disable:
                return "Codex 将恢复原生直连官方通道；已添加的第三方端点与模型会保留，下次启用无需重填。"
            case .restore:
                return "将移除 PasteDeck 的全部托管配置并清理守护进程。仅用于异常状态恢复；常规使用请点「关闭路由」。"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                headerCard
                loginCard
                endpointsCard
                proxyCard
                if let lastError = overview?.lastError {
                    errorCard(lastError)
                }
                if let message = actionMessage {
                    actionBanner(message, isError: actionMessageIsError)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear(perform: reload)
        .onReceive(refreshTimer) { _ in reload() }
        .sheet(item: $editingEndpoint) { endpoint in
            EndpointEditorSheet(
                endpoint: endpoint,
                apiKey: editingAPIKey,
                isNew: isNewEndpoint,
                onSave: { saved, key in
                    saveEndpoint(saved, apiKey: key)
                },
                onCancel: {
                    editingEndpoint = nil
                }
            )
        }
        .sheet(item: $confirmation) { kind in
            confirmationSheet(kind)
        }
    }

    // MARK: - 数据

    private func reload() {
        document = controller.endpointStore.load()
        overview = controller.overview()
    }

    private func run(_ work: @escaping () throws -> String) {
        busy = true
        actionMessage = nil
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let message = try work()
                DispatchQueue.main.async {
                    busy = false
                    actionMessageIsError = false
                    actionMessage = message
                    reload()
                }
            } catch {
                DispatchQueue.main.async {
                    busy = false
                    actionMessageIsError = true
                    actionMessage = error.localizedDescription
                    reload()
                }
            }
        }
    }

    private func saveEndpoint(_ endpoint: RouterEndpoint, apiKey: String?) {
        let routed = isRouted
        run { [controller] in
            try controller.saveEndpoint(endpoint, apiKey: apiKey, routed: routed)
            editingEndpoint = nil
            return routed ? "端点已保存，模型目录已重新发布。请重启 Codex 使选择器刷新。" : "端点已保存。"
        }
        editingEndpoint = nil
    }

    private func deleteEndpoint(_ endpoint: RouterEndpoint) {
        let routed = isRouted
        run { [controller] in
            try controller.deleteEndpoint(id: endpoint.id, routed: routed)
            return routed ? "端点已删除，模型目录已重新发布。" : "端点已删除。"
        }
    }

    private func enableRouter() {
        run { [controller] in
            try controller.enable()
        }
    }

    private func disableRouter() {
        run { [controller] in
            try controller.disable()
            return "路由已关闭，Codex 恢复原生配置。第三方端点配置已保留。"
        }
    }

    private func restoreOriginal() {
        run { [controller] in
            try controller.restore()
        }
    }

    private func testProxy() {
        busy = true
        proxyTestResults = []
        Task { [controller] in
            let results = await controller.testProxy()
            await MainActor.run {
                busy = false
                proxyTestResults = results
            }
        }
    }

    private var isRouted: Bool {
        (overview?.configStatus?.routed ?? false) && (overview?.daemon != nil)
    }

    // MARK: - 顶部：状态与开关

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                statusDot
                VStack(alignment: .leading, spacing: 2) {
                    Text(isRouted ? "路由运行中" : "路由未启用")
                        .font(.system(size: 15, weight: .semibold))
                    Text(statusDetail)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                if isRouted {
                    Button("关闭路由") { confirmation = .disable }
                        .controlSize(.regular)
                } else {
                    Button("启用路由") { enableRouter() }
                        .controlSize(.regular)
                        .disabled(busy)
                }
            }
            HStack(spacing: 14) {
                statusChip("守护进程", ok: overview?.daemon != nil)
                statusChip("配置托管", ok: overview?.configStatus?.routed ?? false)
                statusChip("官方登录", ok: overview?.codexSession.usable ?? false)
                if let port = overview?.daemon?.port {
                    statusChip("端口 \(port)", ok: true)
                }
                Spacer()
                Button("恢复原始配置") { confirmation = .restore }
                    .controlSize(.small)
                    .disabled(busy)
            }
            if let routes = overview?.daemon?.routesLoaded, routes > 0 {
                Text("当前可路由的第三方模型：\(routes) 个")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
    }

    private var statusDot: some View {
        Circle()
            .fill(isRouted ? Color.green : Color.secondary.opacity(0.4))
            .frame(width: 10, height: 10)
    }

    private var statusDetail: String {
        if isRouted {
            let port = overview?.daemon?.port ?? 0
            let uptime = overview?.daemon?.uptimeSeconds ?? 0
            let minutes = uptime / 60
            return "官方 GPT 走 Plus 通道，第三方模型走已配置的中转站（127.0.0.1:\(port)，运行 \(minutes) 分钟）"
        }
        if overview?.configStatus?.routed == true {
            return "配置已托管但守护进程未运行，请在上方启用路由"
        }
        return "Codex 使用原生配置直连官方；启用后模型选择器将合并第三方模型"
    }

    private func statusChip(_ label: String, ok: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle.dashed")
                .font(.system(size: 10))
                .foregroundColor(ok ? .green : .secondary)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - 登录状态

    private var loginCard: some View {
        card {
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("官方 ChatGPT Plus 登录", symbol: "person.badge.key")
                if let session = overview?.codexSession {
                    HStack(spacing: 8) {
                        Image(systemName: session.usable ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(session.usable ? .green : .orange)
                        Text(session.usable
                            ? (session.email ?? "已登录")
                            : (session.present ? "登录会话已过期，请在 Codex 中重新登录" : "未检测到 Codex 登录"))
                            .font(.system(size: 12))
                        if let hours = session.expiresInHours {
                            Text("（约 \(String(format: "%.0f", hours)) 小时后需要刷新）")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    Text("官方 GPT 模型继续使用 Plus 订阅额度；官方凭据绝不发送给任何第三方端点。")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - 端点管理

    private var endpointsCard: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    sectionHeader("第三方 Responses API 端点", symbol: "point.3.filled.connected.trianglepath.dotted")
                    Spacer()
                    Button {
                        isNewEndpoint = true
                        editingAPIKey = ""
                        editingEndpoint = RouterEndpoint(
                            id: "", displayName: "", baseURL: "https://", enabled: true, models: [])
                    } label: {
                        Label("添加端点", systemImage: "plus")
                    }
                    .controlSize(.small)
                }

                if document.endpoints.isEmpty {
                    Text("还没有端点。添加一个兼容 OpenAI Responses API 的中转站，再添加模型，然后打开路由开关。")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .padding(.vertical, 6)
                } else {
                    ForEach(document.endpoints) { endpoint in
                        endpointRow(endpoint)
                        if !endpoint.models.isEmpty {
                            ForEach(endpoint.models) { model in
                                modelRow(endpoint, model)
                            }
                        } else {
                            HStack {
                                Text("    该端点还没有模型")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                        }
                    }
                }
            }
        }
    }

    private func endpointRow(_ endpoint: RouterEndpoint) -> some View {
        HStack(spacing: 8) {
            Image(systemName: endpoint.enabled ? "checkmark.circle.fill" : "pause.circle")
                .font(.system(size: 12))
                .foregroundColor(endpoint.enabled ? .green : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(endpoint.displayName)（\(endpoint.id)）")
                    .font(.system(size: 13, weight: .medium))
                Text(endpoint.baseURL)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text("\(endpoint.models.count) 个模型")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Button("编辑") {
                isNewEndpoint = false
                editingAPIKey = controller.apiKey(for: endpoint.id) ?? ""
                editingEndpoint = endpoint
            }
            .controlSize(.small)
            Button(role: .destructive) {
                deleteEndpoint(endpoint)
            } label: {
                Image(systemName: "trash")
            }
            .controlSize(.small)
        }
        .padding(.top, 4)
    }

    private func modelRow(_ endpoint: RouterEndpoint, _ model: RouterEndpointModel) -> some View {
        HStack(spacing: 8) {
            Text("    ")
            Image(systemName: model.enabled ? "cube.transparent.fill" : "cube.transparent")
                .font(.system(size: 11))
                .foregroundColor(model.enabled ? .accentColor : .secondary)
            Text("'\(endpoint.id)/\(model.modelID)'")
                .font(.system(size: 12, design: .monospaced))
            Text(model.displayName)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Spacer()
            if !model.enabled {
                Text("已停用")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - 代理

    private var proxyCard: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    sectionHeader("代理设置", symbol: "network.badge.shield.half.filled")
                    Spacer()
                    Button("修改") {
                        proxyDraft = document.proxy
                        proxyPasswordDraft = controller.proxyPassword() ?? ""
                        showingProxyEditor = true
                    }
                    .controlSize(.small)
                }
                Text(proxySummary)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                if !proxyTestResults.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(proxyTestResults.indices, id: \.self) { index in
                            let result = proxyTestResults[index]
                            HStack(spacing: 6) {
                                Image(systemName: result.status != nil ? "checkmark.circle" : "xmark.circle")
                                    .font(.system(size: 11))
                                    .foregroundColor(result.status != nil ? .green : .red)
                                Text(result.target)
                                    .font(.system(size: 11))
                                if let status = result.status {
                                    Text("HTTP \(status)")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                if let error = result.error {
                                    Text(error)
                                        .font(.system(size: 11))
                                        .foregroundColor(.red)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                        }
                    }
                    .padding(.top, 2)
                }
                Button("连通性测试") { testProxy() }
                    .controlSize(.small)
                    .disabled(busy)
            }
        }
        .sheet(isPresented: $showingProxyEditor) {
            ProxyEditorSheet(
                proxy: proxyDraft,
                password: proxyPasswordDraft,
                onSave: { proxy, password in
                    run { [controller] in
                        try controller.saveProxy(proxy, password: password)
                        showingProxyEditor = false
                        return "代理设置已保存。修改代理后需要重启路由（关闭再启用）使其对守护进程生效。"
                    }
                },
                onCancel: { showingProxyEditor = false }
            )
        }
    }

    private var proxySummary: String {
        let proxy = document.proxy
        switch proxy.mode {
        case .none:
            return "不使用代理（官方服务无法直连时请改为自定义 HTTP 代理）"
        case .system:
            return "跟随系统代理设置"
        case .http:
            return proxy.isCustomConfigured
                ? "HTTP/HTTPS 代理：\(proxy.host):\(proxy.port)（本机回环地址自动绕过）"
                : "自定义 HTTP 代理尚未填写完整"
        case .socks5:
            return proxy.isCustomConfigured
                ? "SOCKS5 代理：\(proxy.host):\(proxy.port)（本机回环地址自动绕过）"
                : "自定义 SOCKS5 代理尚未填写完整"
        }
    }

    // MARK: - 消息

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("最近一次错误")
                    .font(.system(size: 11, weight: .semibold))
                Text(message)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
            Button("清除") {
                controller.clearLastError()
                reload()
            }
            .controlSize(.mini)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.08)))
    }

    private func actionBanner(_ message: String, isError: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: isError ? "xmark.octagon.fill" : "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(isError ? .red : .green)
            Text(message)
                .font(.system(size: 11))
                .textSelection(.enabled)
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10)
            .fill((isError ? Color.red : Color.green).opacity(0.08)))
    }

    private func confirmationSheet(_ kind: ConfirmationKind) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(kind.title).font(.system(size: 14, weight: .semibold))
            Text(kind.message).font(.system(size: 12)).foregroundColor(.secondary)
            HStack {
                Spacer()
                Button("取消", role: .cancel) { confirmation = nil }
                Button(kind == .disable ? "关闭路由" : "恢复", role: .destructive) {
                    confirmation = nil
                    if kind == .disable { disableRouter() } else { restoreOriginal() }
                }
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    // MARK: - 通用卡片

    @ViewBuilder
    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) { content() }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
    }

    private func sectionHeader(_ title: String, symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundColor(.accentColor)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
        }
    }
}

// MARK: - 端点编辑

private struct EndpointEditorSheet: View {
    let endpoint: RouterEndpoint
    let apiKey: String
    let isNew: Bool
    let onSave: (RouterEndpoint, String?) -> Void
    let onCancel: () -> Void

    @State private var id: String
    @State private var displayName: String
    @State private var baseURL: String
    @State private var enabled: Bool
    @State private var key: String
    @State private var models: [RouterEndpointModel]
    @State private var validationMessage: String?

    init(endpoint: RouterEndpoint, apiKey: String, isNew: Bool,
         onSave: @escaping (RouterEndpoint, String?) -> Void, onCancel: @escaping () -> Void) {
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.isNew = isNew
        self.onSave = onSave
        self.onCancel = onCancel
        _id = State(initialValue: endpoint.id)
        _displayName = State(initialValue: endpoint.displayName)
        _baseURL = State(initialValue: endpoint.baseURL)
        _enabled = State(initialValue: endpoint.enabled)
        _key = State(initialValue: apiKey)
        _models = State(initialValue: endpoint.models)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isNew ? "添加端点" : "编辑端点")
                .font(.system(size: 14, weight: .semibold))

            Form {
                TextField("ID（slug 前缀，小写字母/数字/连字符）", text: $id)
                    .disabled(!isNew)
                TextField("显示名称", text: $displayName)
                TextField("Base URL（如 https://relay.example.com/v1）", text: $baseURL)
                SecureField("API Key", text: $key)
                Toggle("启用该端点", isOn: $enabled)
            }
            .formStyle(.grouped)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("模型（Codex 选择器里的第三方模型）")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Button {
                        models.append(.standard(modelID: "", displayName: ""))
                    } label: {
                        Label("添加模型", systemImage: "plus")
                    }
                    .controlSize(.small)
                }
                ForEach(models.indices, id: \.self) { index in
                    HStack(spacing: 8) {
                        TextField("上游模型 ID", text: Binding(
                            get: { models[index].modelID },
                            set: { models[index].modelID = $0 }))
                            .textFieldStyle(.roundedBorder)
                        TextField("显示名称", text: Binding(
                            get: { models[index].displayName },
                            set: { models[index].displayName = $0 }))
                            .textFieldStyle(.roundedBorder)
                        Button(role: .destructive) {
                            models.remove(at: index)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .controlSize(.small)
                    }
                }
                if models.isEmpty {
                    Text("至少添加一个模型；模型 ID 手动填写，不依赖 /v1/models 接口。")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            if let message = validationMessage {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
            }

            HStack {
                Spacer()
                Button("取消", role: .cancel) { onCancel() }
                Button("保存") { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520, height: 480)
    }

    private func save() {
        let trimmedID = id.trimmingCharacters(in: .whitespaces).lowercased()
        guard SlugBuilder.isValidEndpointID(trimmedID) else {
            validationMessage = "端点 ID 只能包含小写字母、数字与连字符（1-32 位）。"
            return
        }
        let trimmedURL = baseURL.trimmingCharacters(in: .whitespaces)
        guard trimmedURL.hasPrefix("http://") || trimmedURL.hasPrefix("https://") else {
            validationMessage = "Base URL 必须以 http:// 或 https:// 开头。"
            return
        }
        let validModels = models
            .map { model in
                var model = model
                if model.displayName.trimmingCharacters(in: .whitespaces).isEmpty {
                    model.displayName = model.modelID
                }
                return model
            }
            .filter { !trimmed($0.modelID).isEmpty }
        guard !validModels.isEmpty else {
            validationMessage = "至少添加一个有效的上游模型 ID。"
            return
        }
        onSave(
            RouterEndpoint(
                id: trimmedID, displayName: displayName.trimmingCharacters(in: .whitespaces).isEmpty ? trimmedID : displayName,
                baseURL: trimmedURL, enabled: enabled, models: validModels),
            key.isEmpty ? nil : key
        )
    }
}

private func trimmed(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespaces)
}

// MARK: - 代理编辑

private struct ProxyEditorSheet: View {
    let proxy: RouterProxyConfig
    let password: String
    let onSave: (RouterProxyConfig, String?) -> Void
    let onCancel: () -> Void

    @State private var mode: RouterProxyConfig.Mode
    @State private var host: String
    @State private var port: Int
    @State private var username: String
    @State private var passwordDraft: String

    init(proxy: RouterProxyConfig, password: String,
         onSave: @escaping (RouterProxyConfig, String?) -> Void, onCancel: @escaping () -> Void) {
        self.proxy = proxy
        self.password = password
        self.onSave = onSave
        self.onCancel = onCancel
        _mode = State(initialValue: proxy.mode)
        _host = State(initialValue: proxy.host)
        _port = State(initialValue: proxy.port)
        _username = State(initialValue: proxy.username)
        _passwordDraft = State(initialValue: password)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("代理设置").font(.system(size: 14, weight: .semibold))
            Picker("模式", selection: $mode) {
                ForEach(RouterProxyConfig.Mode.allCases) { mode in
                    Text(mode.localizedName).tag(mode)
                }
            }
            .pickerStyle(.inline)
            if mode == .http || mode == .socks5 {
                Form {
                    TextField("地址（如 127.0.0.1）", text: $host)
                    TextField("端口", value: $port, formatter: NumberFormatter())
                    TextField("用户名（可选）", text: $username)
                    SecureField("密码（可选）", text: $passwordDraft)
                }
                .formStyle(.grouped)
                Text("提示：本机路由地址（127.0.0.1 / localhost / ::1）始终绕过代理，不会形成请求循环。")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            HStack {
                Spacer()
                Button("取消", role: .cancel) { onCancel() }
                Button("保存") {
                    var draft = RouterProxyConfig(mode: mode, host: host.trimmingCharacters(in: .whitespaces), port: port, username: username)
                    if mode == .none || mode == .system {
                        draft.host = ""
                        draft.port = 0
                        draft.username = ""
                    }
                    onSave(draft, passwordDraft.isEmpty ? nil : passwordDraft)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440, height: mode == .http || mode == .socks5 ? 380 : 200)
    }
}
