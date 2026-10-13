//
//  WorkbenchGlass.swift
//  PasteDeck
//
//  工作台的玻璃质感基建。macOS 14 上「磨砂玻璃」有两层，缺一不可：
//
//  1. 背景层：材质必须折射到有色彩、明暗有梯度的环境才通透。全屏铺一层
//     暖色渐变（模拟图二里柔和的环境光），否则材质背后只有一块死灰纯色，
//     渲染出来就是不透明的灰板。
//  2. 表面层：材质之上叠一层**低不透明度**的白色/奶油色，这才是「玻璃」的
//     乳白感；再配柔和投影与高光内描边塑造厚度。
//
//  注意：表面层不透明度必须很低。之前用 0.85 的品牌橙盖在材质上，等于把
//  玻璃完全遮死，渲染出来是实心色块而非玻璃。
//

import SwiftUI

/// 工作台玻璃配色的语义 token。
enum WorkbenchGlass {

    /// 环境背景：中性微渐变，保持 macOS 原生干净透亮的质感。
    static func ambientBackground(_ scheme: ColorScheme) -> some View {
        let isDark = scheme == .dark
        return LinearGradient(
            colors: isDark ? [
                Color(red: 0.12, green: 0.12, blue: 0.14),
                Color(red: 0.14, green: 0.14, blue: 0.16),
                Color(red: 0.11, green: 0.11, blue: 0.13)
            ] : [
                Color(red: 0.965, green: 0.968, blue: 0.975),
                Color(red: 0.940, green: 0.945, blue: 0.955),
                Color(red: 0.960, green: 0.965, blue: 0.972)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// 玻璃表面的乳白填充，半透而有质感。
    static func surfaceFill(_ isDark: Bool) -> Color {
        isDark
            ? Color.white.opacity(0.08)
            : Color.white.opacity(0.72)
    }

    /// 玻璃下方的柔和中性投影。
    static func shadow(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.black.opacity(0.35)
            : Color.black.opacity(0.06)
    }
}

/// 磨砂玻璃表面。叠在任意内容之下作为卡片底。
///
/// 踩过的坑：仅靠 `.regularMaterial` 折射，窗口内采样到的是近似的均匀
/// 浅色背景，实测只比背景亮几个百分点，看不出磨砂感。真正决定「玻璃」
/// 观感的是**可感知的乳白填充 + 双层描边 + 真实投影**，材质只作叠加。
struct FrostedGlassSurface: View {
    var cornerRadius: CGFloat = 12
    var material: Material = .regularMaterial

    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        shape
            .fill(material)
            .overlay(shape.fill(WorkbenchGlass.surfaceFill(isDark)))
            .overlay(
                shape.stroke(
                    isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.06),
                    lineWidth: 1
                )
            )
            .overlay(
                // 内层极细高光，塑造边缘厚度。
                shape.stroke(Color.white.opacity(isDark ? 0.08 : 0.65), lineWidth: 1)
                    .padding(0.5)
            )
            .shadow(
                color: WorkbenchGlass.shadow(colorScheme),
                radius: 12,
                x: 0,
                y: 4
            )
    }
}

extension View {
    /// 给视图套一层磨砂玻璃底。
    func frostedGlass(cornerRadius: CGFloat = 12, material: Material = .regularMaterial) -> some View {
        background(FrostedGlassSurface(cornerRadius: cornerRadius, material: material))
    }
}
