// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClipOCR",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "ClipOCR", targets: ["ClipOCR"])],
    targets: [
        .target(name: "ClipOCRCore"),
        .executableTarget(name: "ClipOCR", dependencies: ["ClipOCRCore"]),
        .testTarget(name: "ClipOCRCoreTests", dependencies: ["ClipOCRCore"])
    ],
    swiftLanguageVersions: [.v5]
)
