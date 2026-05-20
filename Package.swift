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
        // Phase 5: Web Panel の画像配信を WebP で行うため、libwebp を SPM
        // 経由でリンクする (BSD-3-clause)。macOS の ImageIO は WebP デコード
        // のみで encode 未対応のため。
        .package(url: "https://github.com/SDWebImage/libwebp-Xcode.git", from: "1.5.0"),
        // 試作: 不規則アスペクト比のカードに強い WaterfallGrid (Pinterest 風) を試す。
        // 既出の ExyteGrid / WaterfallGrids は aspectRatio が細い帯に潰れる症状あり。
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
                // Phase 5: Web Panel 配信用の静的アセット (HTML/CSS/JS)。
                // ディレクトリ構造を残すため .copy。サーバーは Bundle.module
                // から読み出して 200 で返す。
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
                // Phase 5: libwebp は WebPanelIconRenderer の WebP encoder で利用。
                .product(name: "libwebp", package: "libwebp-Xcode"),
                // 試作: レスポンシブグリッド検証 #3 (paololeonardi/WaterfallGrid)
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
