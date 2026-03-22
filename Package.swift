// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LabTetherAgent",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "LabTetherAgent",
            path: "Sources/LabTetherAgent",
            exclude: ["CLAUDE.md", "Resources/Info.plist"],
            resources: [
                .copy("Resources/Fonts"),
                .process("Resources/en.lproj"),
                .process("Resources/es.lproj"),
            ]
        ),
        .testTarget(
            name: "LabTetherAgentTests",
            dependencies: ["LabTetherAgent"],
            path: "Tests/LabTetherAgentTests"
        ),
    ]
)
