// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "SpaceSnifferScanEngine",
    products: [.library(name: "SpaceSnifferScanEngine", targets: ["SpaceSnifferScanEngine"])],
    targets: [
        .target(name: "SpaceSnifferScanEngine"),
        .testTarget(name: "SpaceSnifferScanEngineTests", dependencies: ["SpaceSnifferScanEngine"])
    ]
)
