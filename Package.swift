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
    dependencies: [
        // Phase 5: To deliver images for the Web Panel in WebP format, use libwebp with Swift Package Manager (SPM).
        // Link via BSD-3-clause. macOS's ImageIO supports WebP decoding.
        // Only encode not supported.
        .package(url: "https://github.com/SDWebImage/libwebp-Xcode.git", from: "1.5.0"),
        // Test: Try irregular aspect ratio cards strong WaterfallGrid (Pinterest-like).
        // Previous ExyteGrid/WaterfallGrids have a problem where they get squished into narrow strips.
        .package(url: "https://github.com/paololeonardi/WaterfallGrid.git", from: "1.1.0"),
    ],
    targets: [
        .target(
            name: "FloatingMacroCore",
            path: "Sources/FloatingMacroCore",
            resources: [
                .process("Resources/agent_prompts.json"),
                .process("Resources/tool_descriptions.json"),
                // Use `.copy` so the subdirectory layout is preserved in
                // the bundle. `.process` would flatten everything to the
                // bundle root, breaking Bundle.module.urls(subdirectory:).
                .copy("Resources/seedPresets"),
                // Phase 5: Static Assets for Web Panel Delivery (HTML/CSS/JS).
                // Copy to preserve directory structure. Server is Bundle.module.
                // Return 200 after reading from.
                .copy("Resources/webpanel"),
            ]
        ),
        .executableTarget(
            name: "FloatingMacroCLI",
            dependencies: ["FloatingMacroCore"],
            path: "Sources/FloatingMacroCLI"
        ),
        .executableTarget(
            name: "FloatingMacroApp",
            dependencies: [
                "FloatingMacroCore",
                // Phase 5: libwebp is used by the WebPanelIconRenderer as a WebP encoder.
                .product(name: "libwebp", package: "libwebp-Xcode"),
                // Prototype: Responsive Grid Verification #3 (paololeonardi/WaterfallGrid)
                .product(name: "WaterfallGrid", package: "WaterfallGrid"),
            ],
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
