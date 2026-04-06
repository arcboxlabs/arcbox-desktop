// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DockerClient",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "DockerClient", targets: ["DockerClient"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-openapi-generator", from: "1.10.0"),
        .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.10.0"),
        .package(url: "https://github.com/swift-server/swift-openapi-async-http-client", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "DockerClient",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIAsyncHTTPClient", package: "swift-openapi-async-http-client"),
            ],
            plugins: [
                .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")
            ]
        )
    ]
)
