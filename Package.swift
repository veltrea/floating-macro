// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "FloatingMacro",
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
            ]
        ),
        .testTarget(
            name: "FloatingMacroCoreTests",
            dependencies: ["FloatingMacroCore"],
            path: "Tests/FloatingMacroCoreTests"
        ),
    ]
)
