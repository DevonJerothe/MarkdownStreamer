// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MarkdownStreamer",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .tvOS(.v17),
        .watchOS(.v10),
        .visionOS(.v1),
    ],
    products: [
        .library(
            name: "MarkdownStreamer",
            targets: ["MarkdownStreamer"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/JohnSundell/Splash.git", from: "0.16.0"),
    ],
    targets: [
        .target(
            name: "MarkdownStreamer",
            dependencies: ["Splash"]
        ),
        .testTarget(
            name: "MarkdownStreamerTests",
            dependencies: ["MarkdownStreamer"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
