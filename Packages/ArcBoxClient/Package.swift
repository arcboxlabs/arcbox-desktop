// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ArcBoxClient",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(name: "ArcBoxClient", targets: ["ArcBoxClient"]),
    ],
    dependencies: [
        .package(url: "https://github.com/grpc/grpc-swift-nio-transport.git", from: "1.0.0"),
        .package(url: "https://github.com/grpc/grpc-swift-protobuf.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.28.1"),
        .package(url: "https://github.com/getsentry/sentry-cocoa.git", from: "9.7.0"),
    ],
    targets: [
        .target(
            name: "ArcBoxClient",
            dependencies: [
                .product(name: "GRPCNIOTransportHTTP2Posix", package: "grpc-swift-nio-transport"),
                .product(name: "GRPCProtobuf", package: "grpc-swift-protobuf"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                .product(name: "Sentry", package: "sentry-cocoa"),
            ]
        ),
        .testTarget(
            name: "ArcBoxClientTests",
            dependencies: ["ArcBoxClient"]
        ),
    ]
)
