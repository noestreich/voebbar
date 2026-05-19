// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VOEBBMenu",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "VOEBBMenu",
            path: "Sources/VOEBBMenu"
        ),
    ]
)
