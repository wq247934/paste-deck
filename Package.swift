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
    targets: [
        .executableTarget(
            name: "PasteDeck",
            path: "PasteDeck/PasteDeck"
        )
    ]
)
