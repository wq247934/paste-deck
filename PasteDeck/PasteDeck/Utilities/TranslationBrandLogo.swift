//
//  TranslationBrandLogo.swift
//  PasteDeck
//
//  Shared local brand-logo mapping for translation configuration and result surfaces.
//

import AppKit
import SwiftUI

/// 翻译功能中可识别的服务商品牌；每个候选值都对应 Resources/BrandLogos 中的一份本地 SVG。
enum TranslationBrand: String {
    /// 百度翻译开放平台。
    case baidu
    /// 腾讯云机器翻译。
    case tencentCloud
    /// 网易有道智云翻译。
    case youdao
    /// 阿里云机器翻译。
    case alibabaCloud
    /// DeepSeek 大模型服务。
    case deepSeek
    /// 智谱 AI / GLM 大模型服务。
    case glm
    /// Moonshot AI / Kimi 大模型服务。
    case kimi
    /// 小米 MiMo 大模型服务。
    case mimo
    /// OpenAI 大模型服务。
    case openAI
    /// MiniMax 大模型服务。
    case miniMax
    /// 阿里云通义千问大模型服务。
    case qwen

    /// 本地 SVG 文件名，不含扩展名。
    var assetName: String { rawValue }

    /// SwiftPM 资源包中的 Logo 地址；测试也使用此入口验证所有品牌资源都随应用分发。
    var bundledLogoURL: URL? {
        Bundle.module.url(
            forResource: assetName,
            withExtension: "svg",
            subdirectory: "BrandLogos"
        ) ?? Bundle.module.url(forResource: assetName, withExtension: "svg")
    }

    /// 图片不可用时供辅助功能和系统图标兜底使用的品牌名称。
    var displayName: String {
        switch self {
        case .baidu: return "百度"
        case .tencentCloud: return "腾讯云"
        case .youdao: return "有道"
        case .alibabaCloud: return "阿里云"
        case .deepSeek: return "DeepSeek"
        case .glm: return "GLM"
        case .kimi: return "Kimi"
        case .mimo: return "MiMo"
        case .openAI: return "OpenAI"
        case .miniMax: return "MiniMax"
        case .qwen: return "通义千问"
        }
    }

    /// 配置已被删除或端点已更改时，依据历史卡片文本尽力恢复品牌，不影响翻译本身。
    static func infer(providerName: String, detail: String = "") -> TranslationBrand? {
        let candidate = "\(providerName) \(detail)".lowercased()
        if candidate.contains("deepseek") { return .deepSeek }
        if candidate.contains("glm") || candidate.contains("智谱") || candidate.contains("z.ai") { return .glm }
        if candidate.contains("kimi") || candidate.contains("moonshot") { return .kimi }
        if candidate.contains("mimo") || candidate.contains("小米") { return .mimo }
        if candidate.contains("openai") { return .openAI }
        if candidate.contains("minimax") { return .miniMax }
        if candidate.contains("qwen") || candidate.contains("千问") || candidate.contains("百炼") { return .qwen }
        if candidate.contains("百度") || candidate.contains("baidu") { return .baidu }
        if candidate.contains("腾讯") || candidate.contains("tencent") { return .tencentCloud }
        if candidate.contains("有道") || candidate.contains("youdao") { return .youdao }
        if candidate.contains("阿里") || candidate.contains("alibaba") { return .alibabaCloud }
        return nil
    }
}

extension TranslationProviderKind {
    /// 常规翻译 API 对应的稳定品牌标识。
    var translationBrand: TranslationBrand {
        switch self {
        case .baidu: return .baidu
        case .tencent: return .tencentCloud
        case .youdao: return .youdao
        case .alibaba: return .alibabaCloud
        }
    }
}

extension LLMTranslationPreset {
    /// 大模型预设对应的稳定品牌标识。
    var translationBrand: TranslationBrand {
        switch self {
        case .deepSeek: return .deepSeek
        case .glm: return .glm
        case .kimi: return .kimi
        case .mimo: return .mimo
        case .openAI: return .openAI
        case .miniMax: return .miniMax
        case .qwen: return .qwen
        }
    }
}

extension LLMTranslationConfiguration {
    /// 根据官方端点优先识别品牌；自定义端点可继续使用名称兜底，不新增持久化字段。
    var translationBrand: TranslationBrand? {
        let normalizedBaseURL = baseURL.lowercased()
        if normalizedBaseURL.contains("deepseek.com") { return .deepSeek }
        if normalizedBaseURL.contains("bigmodel.cn") || normalizedBaseURL.contains("z.ai") { return .glm }
        if normalizedBaseURL.contains("moonshot.cn") { return .kimi }
        if normalizedBaseURL.contains("xiaomimimo.com") { return .mimo }
        if normalizedBaseURL.contains("openai.com") { return .openAI }
        if normalizedBaseURL.contains("minimaxi.com") { return .miniMax }
        if normalizedBaseURL.contains("dashscope.aliyuncs.com") { return .qwen }
        return TranslationBrand.infer(providerName: name, detail: model)
    }
}

/// 进程内缓存已解析的 SVG，避免列表刷新或卡片滚动时重复读取和解码资源。
private enum TranslationBrandLogoImageStore {
    private static let cache = NSCache<NSString, NSImage>()

    static func image(for brand: TranslationBrand) -> NSImage? {
        let cacheKey = brand.assetName as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }
        guard let resourceURL = brand.bundledLogoURL,
        let image = NSImage(contentsOf: resourceURL) else {
            return nil
        }
        cache.setObject(image, forKey: cacheKey)
        return image
    }
}

/// 统一的品牌 Logo 容器；白色底板保留各厂商规定的原始颜色，并保证深色模式下仍清晰。
struct TranslationBrandLogoView: View {
    /// 要展示的已知品牌；nil 表示自定义 OpenAI-compatible 服务。
    let brand: TranslationBrand?
    /// Logo 外框尺寸，配置卡片与翻译结果可按信息密度分别传入。
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(Color.white)

            if let brand, let image = TranslationBrandLogoImageStore.image(for: brand) {
                Image(nsImage: image)
                    .resizable()
                    .antialiased(true)
                    .aspectRatio(contentMode: .fit)
                    .padding(size * 0.2)
                    .accessibilityLabel(brand.displayName)
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundColor(.secondary)
                    .accessibilityLabel("自定义大模型服务")
            }
        }
        .frame(width: size, height: size)
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 1, y: 1)
    }
}
