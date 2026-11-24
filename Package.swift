// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "MacSpaceSniffer", platforms: [.macOS(.v14)],
    products: [.executable(name: "MacSpaceSniffer", targets: ["MacSpaceSniffer"]),
               .executable(name: "MacScanBridge", targets: ["MacScanBridge"]),
               .library(name:"MacPreviewSupport",type:.dynamic,targets:["MacPreviewSupport"])],
    dependencies: [.package(path: "Packages/SpaceSnifferScanEngine")],
    targets: [
        .target(name: "SpaceSnifferCore", dependencies: [.product(name: "SpaceSnifferScanEngine", package: "spacesnifferscanengine")]),
        .target(name: "SpaceSnifferAutomation", dependencies: ["SpaceSnifferCore"]),
        .target(name: "SnifferTestSupport", dependencies: ["SpaceSnifferCore"], path: "Tests/TestSupport"),
        .target(name:"MacPreviewSupport"),
        .executableTarget(name: "MacScanBridge", dependencies: ["SpaceSnifferCore"]),
        .executableTarget(name: "MacSpaceSniffer", dependencies: ["SpaceSnifferCore", "SpaceSnifferAutomation"]),
        .testTarget(name: "MacSpaceSnifferTests", dependencies: ["MacSpaceSniffer", "SnifferTestSupport"]),
        .testTarget(name: "SpaceSnifferCoreTests", dependencies: ["SpaceSnifferCore", "SnifferTestSupport"]),
        .testTarget(name: "SpaceSnifferAutomationTests", dependencies: ["SpaceSnifferAutomation", "SpaceSnifferCore", "SnifferTestSupport"])
    ]
)
