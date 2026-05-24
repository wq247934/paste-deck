// swift-tools-version: 5.9
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
        .executableTarget(
            name: "PasteDeck",
            dependencies: ["Highlightr"],
            path: "PasteDeck/PasteDeck"
        )
    ]
)
