// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ProcessSupport",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "ProcessSupport", targets: ["ProcessSupport"]),
        .library(name: "ProcessSupportTesting", targets: ["ProcessSupportTesting"]),
    ],
    targets: [
        .target(name: "ProcessSupport"),
        // Fake executables for tests of code that launches processes. Deliberately independent
        // of `ProcessSupport`: a fixture that waited on the primitives under test would hang
        // with them instead of failing the test.
        .target(name: "ProcessSupportTesting"),
        .testTarget(
            name: "ProcessSupportTests",
            dependencies: ["ProcessSupport", "ProcessSupportTesting"]
        ),
    ]
)
