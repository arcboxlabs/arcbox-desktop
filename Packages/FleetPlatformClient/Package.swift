// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "FleetPlatformClient",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "FleetPlatformClient", targets: ["FleetPlatformClient"])
    ],
    dependencies: [
        .package(path: "../ArcBoxAuth")
    ],
    targets: [
        .target(
            name: "FleetPlatformClient",
            dependencies: ["ArcBoxAuth"]
        ),
        .testTarget(
            name: "FleetPlatformClientTests",
            dependencies: ["FleetPlatformClient"]
        ),
    ]
)
