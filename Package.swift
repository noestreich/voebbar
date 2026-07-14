// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VOEBBMenu",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "VOEBBKit", targets: ["VOEBBKit"]),
    ],
    targets: [
        .target(
            name: "VOEBBKit",
            path: "Sources/VOEBBKit"
        ),
        .executableTarget(
            name: "VOEBBMenu",
            dependencies: ["VOEBBKit"],
            path: "Sources/VOEBBMenu"
        ),
    ]
)
