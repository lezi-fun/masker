// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Masker",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "MaskerCore",
            dependencies: []
        ),
        .executableTarget(
            name: "Masker",
            dependencies: [
                .target(name: "MaskerCore"),
            ]
        ),
        .executableTarget(
            name: "Test",
            dependencies: [
                .target(name: "MaskerCore"),
            ]
        ),
    ]
)
