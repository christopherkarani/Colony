// swift-tools-version: 6.2

import PackageDescription

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
        .package(url: "https://github.com/christopherkarani/Hive", exact: "0.1.5"),
        .package(
            url: "https://github.com/christopherkarani/Conduit",
            exact: "0.3.3",
            traits: ["OpenAI", "OpenRouter", "Anthropic"]
        ),
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
                .product(name: "HiveConduit", package: "Hive"),
                .product(name: "Conduit", package: "Conduit"),
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
