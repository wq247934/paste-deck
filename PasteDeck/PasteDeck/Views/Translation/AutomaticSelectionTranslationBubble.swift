//
//  AutomaticSelectionTranslationBubble.swift
//  PasteDeck
//
//  Lightweight, non-activating translation bubble for automatic mouse selections.
//

import AppKit
import SwiftUI

/// 单个气泡服务在本次划词中的请求状态；切换服务时保留已返回结果，避免重复计费。
private enum AutomaticSelectionTranslationBubbleResultState: Equatable {
    /// 尚未选择或尚未向该服务发起请求。
    case idle
    /// 请求进行中。
    case translating
    /// 请求成功并携带译文。
    case translated(String)
    /// 请求失败并携带面向用户的错误信息。
    case failed(String)
}

@MainActor
private final class AutomaticSelectionTranslationBubbleModel: ObservableObject {
    /// 本次划词原文；仅驻留内存，不写入翻译收藏分类。
    let sourceText: String
    /// 按设置顺序解析的候选服务；首项为默认服务。
    let services: [AutomaticSelectionTranslationService]

    /// 当前气泡展示的服务引用；nil 表示没有可用配置。
    @Published private(set) var selectedReference: AutomaticSelectionTranslationServiceReference?
    /// 本次划词中各服务的结果缓存；切回已完成服务时直接复用。
    @Published private var resultStates: [AutomaticSelectionTranslationServiceReference: AutomaticSelectionTranslationBubbleResultState] = [:]

    /// 尚未完成的网络请求；关闭气泡时统一取消，避免离开后继续消耗额度。
    private var requests: [AutomaticSelectionTranslationServiceReference: URLSessionDataTask] = [:]

    init(sourceText: String, services: [AutomaticSelectionTranslationService]) {
        self.sourceText = sourceText
        self.services = services
        self.selectedReference = services.first?.reference
    }

    /// 当前气泡选中的完整服务配置。
    var selectedService: AutomaticSelectionTranslationService? {
        guard let selectedReference else { return nil }

        return services.first { $0.reference == selectedReference }
    }

    /// 当前服务的请求状态；无可用配置时直接提供设置引导。
    var selectedResultState: AutomaticSelectionTranslationBubbleResultState {
        guard let selectedReference else {
            return .failed("请先在“设置 -> 翻译”中启用并选择至少一个气泡翻译服务")
        }

        return resultStates[selectedReference] ?? .idle
    }

    /// 当前服务在设置顺序中的零起始位置；nil 表示没有可用服务。
    var selectedServiceIndex: Int? {
        guard let selectedReference else { return nil }

        return services.firstIndex { $0.reference == selectedReference }
    }

    /// 只在用户首次查看某个服务时发起请求；已完成、失败或进行中的结果均不重复请求。
    func select(_ reference: AutomaticSelectionTranslationServiceReference) {
        guard services.contains(where: { $0.reference == reference }) else { return }
        selectedReference = reference
        translateSelectedServiceIfNeeded()
    }

    /// 按设置顺序切换相邻服务；到达首尾后保持不变，避免误循环到非预期服务。
    func selectService(offset: Int) {
        guard let selectedServiceIndex else { return }
        let destinationIndex = selectedServiceIndex + offset
        guard services.indices.contains(destinationIndex) else { return }

        select(services[destinationIndex].reference)
    }

    /// 默认服务在气泡出现后立即翻译，其他服务延迟到用户切换时再调用。
    func translateSelectedServiceIfNeeded() {
        guard let service = selectedService else { return }
        let reference = service.reference
        guard resultStates[reference] == nil else { return }

        resultStates[reference] = .translating
        let targetLanguage = TranslateService.detectTargetLanguage(for: sourceText)
        let completion: (Result<String, Error>) -> Void = { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.requests[reference] = nil
                switch result {
                case .success(let translatedText):
                    self.resultStates[reference] = .translated(translatedText)
                case .failure(let error):
                    if let urlError = error as? URLError, urlError.code == .timedOut {
                        self.resultStates[reference] = .failed("请求超时，请切换服务或稍后重试")
                    } else if let urlError = error as? URLError, urlError.code == .cancelled {
                        self.resultStates[reference] = .failed("请求已取消")
                    } else {
                        self.resultStates[reference] = .failed(error.localizedDescription)
                    }
                }
            }
        }

        let request: URLSessionDataTask?
        switch service {
        case .api(let configuration):
            request = TranslateService(configuration: configuration).translateSegment(
                sourceText,
                to: targetLanguage,
                completion: completion
            )
        case .llm(let configuration):
            request = LLMTranslationService(configuration: configuration).translate(
                sourceText,
                targetLanguage: targetLanguage,
                completion: completion
            )
        }
        if let request {
            requests[reference] = request
        }
    }

    /// 关闭或替换气泡时取消全部未完成请求；已返回结果只随当前内存模型一起释放。
    func cancelAll() {
        requests.values.forEach { $0.cancel() }
        requests.removeAll()
    }
}

/// 非激活面板只在用户主动点击气泡控件时成为 key window，不会在出现时抢走阅读应用焦点。
private final class AutomaticSelectionTranslationBubblePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class AutomaticSelectionTranslationBubbleController {
    /// 气泡固定尺寸，在长译文时通过内部滚动保持轻量边界。
    private let bubbleSize = NSSize(width: 360, height: 176)
    /// 当前可见非激活面板；nil 表示没有自动划词结果。
    private var panel: NSPanel?
    /// 当前气泡模型，用于替换或关闭时取消网络请求。
    private var model: AutomaticSelectionTranslationBubbleModel?

    /// 在鼠标划词结束点附近展示气泡；只翻译默认服务，其他服务按用户切换懒加载。
    func show(
        text: String,
        near anchorPoint: NSPoint,
        services: [AutomaticSelectionTranslationService],
        onExpand: @escaping () -> Void
    ) {
        dismiss()

        let model = AutomaticSelectionTranslationBubbleModel(
            sourceText: text,
            services: services
        )
        let rootView = AutomaticSelectionTranslationBubbleView(
            model: model,
            onExpand: onExpand
        )
        let hostingController = NSHostingController(rootView: rootView)
        let panel = AutomaticSelectionTranslationBubblePanel(
            contentRect: NSRect(origin: .zero, size: bubbleSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hostingController
        panel.level = .popUpMenu
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.appearance = AppearanceResolver.currentAppearance
        panel.setFrameOrigin(origin(near: anchorPoint))

        self.model = model
        self.panel = panel
        panel.orderFrontRegardless()
        model.translateSelectedServiceIfNeeded()
    }

    /// 判断全局鼠标按下是否落在气泡内，避免切换服务或放大时被外部点击逻辑提前关闭。
    func contains(_ screenPoint: NSPoint) -> Bool {
        panel?.frame.contains(screenPoint) ?? false
    }

    /// 关闭气泡且不激活 PasteDeck，也不恢复或改变原阅读应用焦点。
    func dismiss() {
        model?.cancelAll()
        panel?.orderOut(nil)
        panel?.contentViewController = nil
        panel = nil
        model = nil
    }

    /// 优先放在划词终点右下方，空间不足时向左或向上翻转，并约束在当前屏幕可见区域内。
    private func origin(near anchorPoint: NSPoint) -> NSPoint {
        let screen = NSScreen.screens.first { $0.frame.contains(anchorPoint) } ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let spacing: CGFloat = 12

        var horizontalOrigin = anchorPoint.x + spacing
        if horizontalOrigin + bubbleSize.width > visibleFrame.maxX {
            horizontalOrigin = anchorPoint.x - bubbleSize.width - spacing
        }

        var verticalOrigin = anchorPoint.y - bubbleSize.height - spacing
        if verticalOrigin < visibleFrame.minY {
            verticalOrigin = anchorPoint.y + spacing
        }

        horizontalOrigin = min(
            max(horizontalOrigin, visibleFrame.minX + spacing),
            visibleFrame.maxX - bubbleSize.width - spacing
        )
        verticalOrigin = min(
            max(verticalOrigin, visibleFrame.minY + spacing),
            visibleFrame.maxY - bubbleSize.height - spacing
        )
        return NSPoint(x: horizontalOrigin, y: verticalOrigin)
    }
}

private struct AutomaticSelectionTranslationBubbleView: View {
    /// 本次划词气泡的服务、选择和请求状态。
    @ObservedObject var model: AutomaticSelectionTranslationBubbleModel
    /// 用户主动放大时进入原完整翻译工作区的回调。
    let onExpand: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                serviceSelector

                Spacer(minLength: 8)

                Button(action: onExpand) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 26, height: 24)
                        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .disabled(model.selectedService == nil)
                .help("在完整翻译窗口中打开")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            Divider()

            resultContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(12)
        }
        .frame(width: 360, height: 176)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 13))
        .overlay(
            RoundedRectangle(cornerRadius: 13)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 13))
    }

    @ViewBuilder
    private var serviceSelector: some View {
        serviceLabel

        if model.services.count > 1, let selectedServiceIndex = model.selectedServiceIndex {
            HStack(spacing: 4) {
                Button {
                    model.selectService(offset: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .disabled(selectedServiceIndex == 0)
                .help("上一个翻译服务")

                Text("\(selectedServiceIndex + 1)/\(model.services.count)")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(minWidth: 27)

                Button {
                    model.selectService(offset: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .disabled(selectedServiceIndex == model.services.count - 1)
                .help("下一个翻译服务")
            }
        }
    }

    private var serviceLabel: some View {
        HStack(spacing: 7) {
            Image(systemName: model.selectedService?.kind == .llm ? "sparkles" : "character.book.closed.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 1) {
                Text(model.selectedService?.displayName ?? "未配置翻译服务")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                if let detail = model.selectedService?.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

        }
    }

    @ViewBuilder
    private var resultContent: some View {
        switch model.selectedResultState {
        case .idle, .translating:
            HStack(spacing: 9) {
                ProgressView()
                    .controlSize(.small)
                Text("正在翻译…")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        case .translated(let translatedText):
            ScrollView {
                Text(translatedText)
                    .font(.system(size: 14))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundColor(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
