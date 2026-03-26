// swift-tools-version: 6.2

import Foundation
import PackageDescription

let useLocalSwarmPath = ProcessInfo.processInfo.environment["COLONY_USE_LOCAL_SWARM_PATH"] == "1"

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
    ],
    dependencies: [
        // Production default: always resolve Swarm from GitHub.
        // Local path usage is opt-in for development only and must not be relied on for release manifests.
        useLocalSwarmPath
            ? .package(path: "../Swarm")
            : .package(url: "https://github.com/christopherkarani/Swarm.git", exact: "0.4.7"),
    ],
    targets: [
        .target(
            name: "ColonyCore",
            dependencies: [
                .product(name: "Swarm", package: "Swarm"),
            ],
            exclude: ["CLAUDE.md"]
        ),
        .target(
            name: "Colony",
            dependencies: [
                "ColonyCore",
                .product(name: "Swarm", package: "Swarm"),
            ],
            exclude: ["CLAUDE.md"]
        ),
        .target(
            name: "ColonyControlPlane",
            dependencies: [
                "Colony",
                "ColonyCore",
            ]
        ),
        .executableTarget(
            name: "ColonyResearchAssistantExample",
            dependencies: ["Colony"],
            exclude: ["CLAUDE.md"],
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
            dependencies: ["ColonyResearchAssistantExample"],
            exclude: ["CLAUDE.md", ".DS_Store"]
        ),
        .testTarget(
            name: "ColonyControlPlaneTests",
            dependencies: ["ColonyControlPlane"]
        ),
    ]
)
