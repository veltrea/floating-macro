// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "FloatingMacro",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "FloatingMacroCore", targets: ["FloatingMacroCore"]),
        .executable(name: "fmcli", targets: ["FloatingMacroCLI"]),
        .executable(name: "FloatingMacro", targets: ["FloatingMacroApp"]),
        .executable(name: "fm-test-target", targets: ["FMTestTarget"]),
    ],
    targets: [
        .target(
            name: "FloatingMacroCore",
            path: "Sources/FloatingMacroCore",
            resources: [
                .process("Resources/agent_prompts.json"),
                // Use `.copy` so the subdirectory layout is preserved in
                // the bundle. `.process` would flatten everything to the
                // bundle root, breaking Bundle.module.urls(subdirectory:).
                .copy("Resources/seedPresets"),
            ]
        ),
        .executableTarget(
            name: "FloatingMacroCLI",
            dependencies: ["FloatingMacroCore"],
            path: "Sources/FloatingMacroCLI"
        ),
        .executableTarget(
            name: "FloatingMacroApp",
            dependencies: ["FloatingMacroCore"],
            path: "Sources/FloatingMacroApp",
            resources: [
                .copy("Resources/lucide"),
                // .lproj directories declare to macOS that this app supports
                // these languages, so system-provided menus (Cut/Copy/Paste,
                // text substitutions, etc.) are localized to match.
                .process("Resources/en.lproj"),
                .process("Resources/ja.lproj"),
            ]
        ),
        .executableTarget(
            name: "FMTestTarget",
            dependencies: ["FloatingMacroCore"],
            path: "Sources/FMTestTarget"
        ),
        .testTarget(
            name: "FloatingMacroCoreTests",
            dependencies: ["FloatingMacroCore"],
            path: "Tests/FloatingMacroCoreTests"
        ),
    ]
)
