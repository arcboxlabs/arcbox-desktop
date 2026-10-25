// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "RunnerAgentClient",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "RunnerAgentClient", targets: ["RunnerAgentClient"])
    ],
    dependencies: [
        .package(url: "https://github.com/grpc/grpc-swift-nio-transport.git", from: "1.2.0"),
        .package(url: "https://github.com/grpc/grpc-swift-protobuf.git", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.35.0"),
    ],
    targets: [
        .target(
            name: "RunnerAgentClient",
            dependencies: [
                .product(name: "GRPCNIOTransportHTTP2TransportServices", package: "grpc-swift-nio-transport"),
                .product(name: "GRPCProtobuf", package: "grpc-swift-protobuf"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ]
        ),
        .testTarget(
            name: "RunnerAgentClientTests",
            dependencies: ["RunnerAgentClient"]
        ),
    ]
)
