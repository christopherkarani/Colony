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
    ],
    dependencies: [
        .package(path: "../hive"),
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
            ]
        ),
        .testTarget(
            name: "ColonyTests",
            dependencies: ["Colony"]
        ),
    ]
)

