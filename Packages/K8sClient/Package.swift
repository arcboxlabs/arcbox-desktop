// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "K8sClient",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "K8sClient", targets: ["K8sClient"])
    ],
    targets: [
        .target(name: "K8sClient")
    ]
)
