// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ArcBoxAuth",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "ArcBoxAuth", targets: ["ArcBoxAuth"])
    ],
    targets: [
        .target(name: "ArcBoxAuth"),
        .testTarget(
            name: "ArcBoxAuthTests",
            dependencies: ["ArcBoxAuth"]
        ),
    ]
)
