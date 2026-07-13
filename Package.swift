// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BookmarkBridge",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "BookmarkBridgeCore", targets: ["BookmarkBridgeCore"]),
        .executable(name: "BookmarkBridge", targets: ["BookmarkBridge"]),
        .executable(name: "BookmarkBridgeChecks", targets: ["BookmarkBridgeChecks"]),
    ],
    targets: [
        .target(name: "BookmarkBridgeCore"),
        .executableTarget(
            name: "BookmarkBridge",
            dependencies: ["BookmarkBridgeCore"]
        ),
        .executableTarget(
            name: "BookmarkBridgeChecks",
            dependencies: ["BookmarkBridgeCore"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
