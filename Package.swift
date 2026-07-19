// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "wharfside-rules",
    platforms: [
        .macOS(.v15)  // Core has no FoundationModels dependency; only the
                      // (future) RulebookFoundationModels target needs macOS 26.
    ],
    products: [
        .library(name: "RulebookCore", targets: ["RulebookCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto", from: "3.0.0")
    ],
    targets: [
        .target(
            name: "RulebookCore",
            dependencies: [.product(name: "Crypto", package: "swift-crypto")],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "RulebookCoreTests",
            dependencies: ["RulebookCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
