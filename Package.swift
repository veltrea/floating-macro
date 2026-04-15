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
    ],
    targets: [
        .target(
            name: "FloatingMacroCore",
            path: "Sources/FloatingMacroCore"
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
        .testTarget(
            name: "FloatingMacroCoreTests",
            dependencies: ["FloatingMacroCore"],
            path: "Tests/FloatingMacroCoreTests"
        ),
    ]
)
