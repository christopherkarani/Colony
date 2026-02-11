// swift-tools-version: 6.2

import Foundation
import PackageDescription

let useLocalHivePath = ProcessInfo.processInfo.environment["COLONY_USE_LOCAL_HIVE_PATH"] == "1"

let package = Package(
    name: "Colony",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "Colony", targets: ["Colony"]),
        .library(name: "ColonyCore", targets: ["ColonyCore"]),
        .library(name: "ColonyControlPlane", targets: ["ColonyControlPlane"]),
        .executable(name: "ColonyResearchAssistantExample", targets: ["ColonyResearchAssistantExample"]),
        .executable(name: "DeepResearchApp", targets: ["DeepResearchApp"]),
    ],
    dependencies: [
        // Default: remote pinned Hive dependency.
        // Local fallback: set COLONY_USE_LOCAL_HIVE_PATH=1 for offline/dev workflows.
        useLocalHivePath
            ? .package(path: ".deps/Hive/Sources/Hive")
            : .package(url: "https://github.com/christopherkarani/Hive.git", exact: "0.1.2"),
    ],
    targets: [
        .target(
            name: "ColonyCore",
            dependencies: [
                .product(name: "HiveCore", package: "Hive"),
            ],
            exclude: ["CLAUDE.md"]
        ),
        .target(
            name: "Colony",
            dependencies: [
                "ColonyCore",
                .product(name: "HiveCore", package: "Hive"),
            ],
            exclude: ["CLAUDE.md"]
        ),
        .target(
            name: "ColonyControlPlane",
            dependencies: [
                "Colony",
                "ColonyCore",
                .product(name: "HiveCore", package: "Hive"),
            ]
        ),
        .executableTarget(
            name: "ColonyResearchAssistantExample",
            dependencies: ["Colony"],
            exclude: ["CLAUDE.md"],
        ),
        .executableTarget(
            name: "DeepResearchApp",
            dependencies: ["Colony"],
            path: "Sources/DeepResearchApp",
            exclude: [
                "Models/CLAUDE.md",
                "ViewModels/CLAUDE.md",
                "Views/CLAUDE.md",
            ]
        ),
        .testTarget(
            name: "ColonyTests",
            dependencies: ["Colony"],
            exclude: ["CLAUDE.md"]
        ),
        .testTarget(
            name: "ColonyExecutionHardeningTests",
            dependencies: ["Colony"]
        ),
        .testTarget(
            name: "ColonyResearchAssistantExampleTests",
            dependencies: ["ColonyResearchAssistantExample"]
        ),
        .testTarget(
            name: "ColonyControlPlaneTests",
            dependencies: ["ColonyControlPlane"]
        ),
    ]
)
