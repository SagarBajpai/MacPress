// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ScreenCompressor",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ScreenCompressor", targets: ["ScreenCompressor"])],
    targets: [
        .executableTarget(name: "ScreenCompressor", path: "ScreenCompressor"),
        .testTarget(name: "ScreenCompressorTests", dependencies: ["ScreenCompressor"], path: "ScreenCompressorTests")
    ]
)
