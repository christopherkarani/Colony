// swift-tools-version: 6.2

import Foundation
import PackageDescription

let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let useLocalAllDeps = ProcessInfo.processInfo.environment["AISTACK_USE_LOCAL_DEPS"] == "1"
let useLocalHivePath = useLocalAllDeps || ProcessInfo.processInfo.environment["COLONY_USE_LOCAL_HIVE_PATH"] == "1"
let useLocalSwarmPath = useLocalAllDeps || ProcessInfo.processInfo.environment["COLONY_USE_LOCAL_SWARM_PATH"] == "1"
let useLocalMembranePath = useLocalAllDeps || ProcessInfo.processInfo.environment["COLONY_USE_LOCAL_MEMBRANE_PATH"] == "1"
let useLocalConduitPath = useLocalAllDeps || ProcessInfo.processInfo.environment["COLONY_USE_LOCAL_CONDUIT_PATH"] == "1"

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
            ? .package(path: packageRoot.appendingPathComponent("../Hive").path)
            : .package(
                url: "https://github.com/christopherkarani/Hive",
                exact: "0.1.8"
            ),
        // Swarm agent framework — @Tool macros, multi-agent orchestration, Wax memory, Conduit model backends.
        useLocalSwarmPath
            ? .package(
                path: packageRoot.appendingPathComponent("../Swarm").path,
                traits: [
                    .trait(name: "membrane"),
                ]
            )
            : .package(
                url: "https://github.com/christopherkarani/Swarm.git",
                exact: "0.4.6",
                traits: [
                    .trait(name: "membrane"),
                ]
            ),
        useLocalMembranePath
            ? .package(path: packageRoot.appendingPathComponent("../Membrane").path)
            : .package(
                url: "https://github.com/christopherkarani/Membrane.git",
                exact: "0.1.2"
            ),
        useLocalConduitPath
            ? .package(
                path: packageRoot.appendingPathComponent("../Conduit").path,
                traits: [
                    .trait(name: "OpenAI"),
                    .trait(name: "OpenRouter"),
                    .trait(name: "Anthropic"),
                ]
            )
            : .package(
                url: "https://github.com/christopherkarani/Conduit",
                exact: "0.3.10",
                traits: [
                    .trait(name: "OpenAI"),
                    .trait(name: "OpenRouter"),
                    .trait(name: "Anthropic"),
                ]
            ),
    ],
    targets: [
        .target(
            name: "ColonyCore",
            dependencies: [
                .product(name: "HiveCore", package: "Hive"),
            ]
        ),
        .target(
            name: "Colony",
            dependencies: [
                "ColonyCore",
                .product(name: "HiveCore", package: "Hive"),
                .product(name: "HiveCheckpointWax", package: "Hive"),
                .product(name: "Swarm", package: "Swarm"),
                .product(name: "Membrane", package: "Membrane"),
                .product(name: "MembraneWax", package: "Membrane"),
                .product(name: "ConduitAdvanced", package: "Conduit"),
            ]
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
            dependencies: ["Colony"]
        ),
        .executableTarget(
            name: "DeepResearchApp",
            dependencies: ["Colony"],
            path: "Sources/DeepResearchApp"
        ),
        .testTarget(
            name: "ColonyTests",
            dependencies: [
                "Colony",
                .product(name: "Swarm", package: "Swarm"),
                .product(name: "Membrane", package: "Membrane"),
            ]
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
