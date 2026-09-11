// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HermexWatchRoot",
    platforms: [
        .macOS(.v14),
        .watchOS(.v11),
    ],
    products: [
        .library(name: "HermexWatchRoot", targets: ["HermexWatchRoot"]),
    ],
    targets: [
        .target(name: "HermexWatchRoot"),
        .testTarget(name: "HermexWatchRootTests", dependencies: ["HermexWatchRoot"]),
    ],
    swiftLanguageModes: [.v5]
)
