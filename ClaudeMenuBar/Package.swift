// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudeMenuBar",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "ClaudeMenuBar", targets: ["ClaudeMenuBar"])
    ],
    targets: [
        .executableTarget(
            name: "ClaudeMenuBar",
            path: "ClaudeMenuBar",
            resources: [
                .process("Assets.xcassets")
            ]
        )
    ]
)
