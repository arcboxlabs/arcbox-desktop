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
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.2.2")
    ],
    targets: [
        .target(name: "K8sClient", dependencies: ["Yams"])
    ]
)
