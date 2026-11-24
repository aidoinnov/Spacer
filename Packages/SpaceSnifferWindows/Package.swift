// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "SpaceSnifferWindows", products: [
    .executable(name: "WindowsScan", targets: ["WindowsScan"]),
    .library(name:"WindowsScanCore",targets:["WindowsScanCore"])
], dependencies: [.package(path: "../SpaceSnifferScanEngine")], targets: [
    .target(name: "WindowsDirectoryIO", publicHeadersPath: "include"),
    .target(name: "WindowsScanCore", dependencies: ["WindowsDirectoryIO", .product(name: "SpaceSnifferScanEngine", package: "SpaceSnifferScanEngine")]),
    .executableTarget(name: "WindowsScan", dependencies: ["WindowsScanCore", .product(name: "SpaceSnifferScanEngine", package: "SpaceSnifferScanEngine")]),
    .testTarget(name: "WindowsScanCoreTests", dependencies: ["WindowsScanCore", .product(name: "SpaceSnifferScanEngine", package: "SpaceSnifferScanEngine")])
])
