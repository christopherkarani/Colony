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
            : .package(
                url: "https://github.com/christopherkarani/Hive",
                revision: "3bec1b2b8f2c3b2f24765656e83f31c27b9ff4f2"
            ),
        // Swarm agent framework — @Tool macros, multi-agent orchestration, Wax memory, Conduit model backends.
        .package(
            url: "https://github.com/christopherkarani/Swarm.git",
            exact: "0.4.0"
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
                .product(name: "Swarm", package: "Swarm"),
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
            dependencies: ["Colony"]
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
