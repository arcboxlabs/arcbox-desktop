// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PlatformClient",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "PlatformClient", targets: ["PlatformClient"])
    ],
    dependencies: [
        .package(path: "../ArcBoxAuth")
    ],
    targets: [
        .target(
            name: "PlatformClient",
            dependencies: ["ArcBoxAuth"]
        ),
        .testTarget(
            name: "PlatformClientTests",
            dependencies: ["PlatformClient"]
        ),
    ]
)
