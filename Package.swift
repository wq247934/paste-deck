// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PasteDeck",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "PasteDeck", targets: ["PasteDeck"])
    ],
    dependencies: [
        .package(url: "https://github.com/raspu/Highlightr", from: "2.1.0")
    ],
    targets: [
        // MARK: - Agent Speed 引擎（MIT，源自 https://github.com/zoefix/agent-speed，见 PasteDeck/AgentSpeed/LICENSE-AgentSpeed）

        /// zstd C 解压库：读取 Codex 压缩会话日志（上游原样移植）。
        .target(
            name: "CZstd",
            path: "PasteDeck/AgentSpeed/Sources/CZstd",
            exclude: ["LICENSE", "VENDOR.md"],
            publicHeadersPath: ".",
            cSettings: [
                .define("ZSTD_DISABLE_ASM", to: "1"),
                .define("ZSTD_LEGACY_SUPPORT", to: "0"),
                .define("ZSTD_TRACE", to: "0"),
            ]
        ),
        /// 实时测速引擎：数据发现、解析、速度计算、聚合与历史（上游原样移植）。
        .target(
            name: "AgentSpeedCore",
            dependencies: ["CZstd"],
            path: "PasteDeck/AgentSpeed/Sources/AgentSpeedCore"
        ),
        /// 悬浮仪表模型层：摆放、磁吸、五种仪表数学、铭牌与标题主题（上游原样移植）。
        .target(
            name: "AgentSpeedOrbModel",
            dependencies: ["AgentSpeedCore"],
            path: "PasteDeck/AgentSpeed/Sources/AgentSpeedOrbModel"
        ),
        /// 载具动画：从步行到火箭的运动轨迹、速度线、尾焰与粒子（上游原样移植）。
        .target(
            name: "AgentSpeedHero",
            path: "PasteDeck/AgentSpeed/Sources/AgentSpeedHero"
        ),
        /// PasteDeck 集成层：上游 App 层中与宿主无关的 UI/主题/本地化代码
        /// （Theme、Localization、Orb、Cost、Titles、Orbs、Support）加
        /// PasteDeck 侧的门面与设置适配。
        .target(
            name: "AgentSpeedKit",
            dependencies: ["AgentSpeedCore", "AgentSpeedOrbModel", "AgentSpeedHero"],
            path: "PasteDeck/AgentSpeed/Sources/AgentSpeedKit"
        ),

        // MARK: - Codex 模型路由（纯 Swift 轻量路由引擎，参考 MIT 源码 codex-router v0.6.0）

        /// zstd C 压缩库：Codex 原生 GPT 请求体再压缩（上游 zstd 1.5.7，见 VENDOR.md）。
        .target(
            name: "CZstdCompress",
            path: "PasteDeck/CodexRouter/Sources/CZstdCompress",
            exclude: ["LICENSE", "VENDOR.md"],
            publicHeadersPath: ".",
            cSettings: [
                .define("ZSTD_DISABLE_ASM", to: "1"),
                .define("ZSTD_LEGACY_SUPPORT", to: "0"),
                .define("ZSTD_TRACE", to: "0"),
            ]
        ),
        /// Codex 模型路由核心：端点/模型配置、Codex config.toml 托管切换、
        /// 原生目录捕获与合并发布、本地 Responses 路由分发、SSE/WS 中继与代理。
        .target(
            name: "CodexRouterKit",
            dependencies: ["CZstd", "CZstdCompress"],
            path: "PasteDeck/CodexRouter/Sources/CodexRouterKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        /// 路由守护进程：独立于 PasteDeck 主程序运行的本地路由服务入口。
        .executableTarget(
            name: "pastedeck-codex-router",
            dependencies: ["CodexRouterKit"],
            path: "PasteDeck/CodexRouter/Sources/RouterDaemon",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),

        // MARK: - PasteDeck 主程序

        .executableTarget(
            name: "PasteDeck",
            dependencies: ["Highlightr", "AgentSpeedCore", "AgentSpeedKit", "CodexRouterKit"],
            path: "PasteDeck/PasteDeck",
            resources: [
                .process("Resources/Assets.xcassets"),
                .copy("Resources/BrandLogos")
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "PasteDeckTests",
            dependencies: ["PasteDeck", "CodexRouterKit"],
            path: "PasteDeck/Tests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),

        .testTarget(
            name: "CodexRouterKitTests",
            dependencies: ["CodexRouterKit"],
            path: "PasteDeck/CodexRouter/Tests/CodexRouterKitTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),

        // MARK: - Agent Speed 算法测试（上游原样迁移，共享 spec/ 测试数据集）

        .testTarget(
            name: "AgentSpeedCoreTests",
            dependencies: ["AgentSpeedCore"],
            path: "PasteDeck/AgentSpeed/macos/Tests/AgentSpeedCoreTests"
        ),
        .testTarget(
            name: "AgentSpeedOrbModelTests",
            dependencies: ["AgentSpeedOrbModel", "AgentSpeedCore"],
            path: "PasteDeck/AgentSpeed/macos/Tests/AgentSpeedOrbModelTests"
        ),
        .testTarget(
            name: "AgentSpeedHeroTests",
            dependencies: ["AgentSpeedHero"],
            path: "PasteDeck/AgentSpeed/macos/Tests/AgentSpeedHeroTests"
        ),
        .testTarget(
            name: "AgentSpeedKitTests",
            dependencies: ["AgentSpeedKit"],
            path: "PasteDeck/AgentSpeed/macos/Tests/AgentSpeedKitTests"
        ),
    ]
)
