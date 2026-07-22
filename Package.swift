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
            // These two files are copied into the real .app layout by
            // scripts/build-app.sh rather than into the SwiftPM resource bundle.
            exclude: ["Resources/Info.plist", "Resources/AppIcon.icns"],
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
