// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "OpenTDFKit",
    platforms: [
        .iOS(.v16),
        .macOS(.v14),
        .tvOS(.v16),
        .watchOS(.v9),
    ],
    products: [
        .library(
            name: "OpenTDFKit",
            targets: ["OpenTDFKit"]),
    ],
    dependencies: [
    ],
    targets: [
        .target(
            name: "OpenTDFKit",
            dependencies: ["BinaryParser", "CryptoHelper", "KASWebSocket", "NanoTDF"]),
        .testTarget(
            name: "OpenTDFKitTests",
            dependencies: ["OpenTDFKit"]),
    ]
)
