// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SpaceSnifferExplorerBridge",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ExplorerDomain", targets: ["ExplorerDomain"]),
        .executable(name: "ExplorerBackend", targets: ["ExplorerBackend"])
    ],
    dependencies: [
        .package(path: "../SpaceSnifferScanEngine"),
        .package(path: "../SpaceSnifferWindows")
    ],
    targets: [
        .target(name: "ExplorerDomain", dependencies: [
            .product(name: "SpaceSnifferScanEngine", package: "SpaceSnifferScanEngine")
        ]),
        .executableTarget(name: "ExplorerBackend", dependencies: [
            "ExplorerDomain",
            .product(name: "WindowsScanCore", package: "SpaceSnifferWindows", condition: .when(platforms: [.windows]))
        ]),
        .testTarget(name: "ExplorerDomainTests", dependencies: ["ExplorerDomain"])
    ]
)
