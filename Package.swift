// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Shoutou",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Shoutou", targets: ["Shoutou"])
    ],
    targets: [
        .target(
            name: "ShoutouCore",
            path: "Sources/ShoutouCore"
        ),
        .executableTarget(
            name: "Shoutou",
            dependencies: ["ShoutouCore"],
            path: "Sources/Shoutou"
        ),
        .testTarget(
            name: "ShoutouCoreTests",
            dependencies: ["ShoutouCore"],
            path: "Tests/ShoutouCoreTests"
        )
    ]
)
