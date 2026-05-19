// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "WireStub",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
    ],
    products: [
        .library(name: "WireStubCore", targets: ["WireStubCore"]),
        .library(name: "WireStubHAR", targets: ["WireStubHAR"]),
        .library(name: "WireStubServer", targets: ["WireStubServer"]),
        .library(name: "WireStubURLProtocol", targets: ["WireStubURLProtocol"]),
        .library(name: "WireStubXCTest", targets: ["WireStubXCTest"]),
        .executable(name: "wirestub", targets: ["WireStubCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swhitty/FlyingFox.git", from: "0.26.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "WireStubCore",
            dependencies: [],
            path: "Sources/WireStubCore"
        ),
        .testTarget(
            name: "WireStubCoreTests",
            dependencies: ["WireStubCore"],
            path: "Tests/WireStubCoreTests"
        ),

        .target(
            name: "WireStubHAR",
            dependencies: ["WireStubCore"],
            path: "Sources/WireStubHAR"
        ),
        .testTarget(
            name: "WireStubHARTests",
            dependencies: ["WireStubHAR", "WireStubCore"],
            path: "Tests/WireStubHARTests",
            resources: [
                .copy("HARFixtures")
            ]
        ),

        .target(
            name: "WireStubServer",
            dependencies: [
                "WireStubCore",
                .product(name: "FlyingFox", package: "FlyingFox"),
                .product(name: "FlyingSocks", package: "FlyingFox"),
            ],
            path: "Sources/WireStubServer"
        ),
        .testTarget(
            name: "WireStubServerTests",
            dependencies: ["WireStubServer", "WireStubCore"],
            path: "Tests/WireStubServerTests"
        ),

        .target(
            name: "WireStubURLProtocol",
            dependencies: ["WireStubCore"],
            path: "Sources/WireStubURLProtocol"
        ),
        .testTarget(
            name: "WireStubURLProtocolTests",
            dependencies: ["WireStubURLProtocol", "WireStubCore", "WireStubServer"],
            path: "Tests/WireStubURLProtocolTests"
        ),

        .target(
            name: "WireStubXCTest",
            dependencies: ["WireStubCore", "WireStubServer"],
            path: "Sources/WireStubXCTest"
        ),
        .testTarget(
            name: "WireStubXCTestSupportTests",
            dependencies: ["WireStubXCTest", "WireStubServer", "WireStubCore"],
            path: "Tests/WireStubXCTestSupportTests"
        ),

        .executableTarget(
            name: "WireStubCLI",
            dependencies: [
                "WireStubHAR",
                "WireStubCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/WireStubCLI"
        ),
        .testTarget(
            name: "WireStubCLITests",
            dependencies: ["WireStubCLI", "WireStubHAR", "WireStubCore"],
            path: "Tests/WireStubCLITests"
        ),

        .testTarget(
            name: "WireStubArchitectureTests",
            dependencies: ["WireStubCore", "WireStubServer", "WireStubURLProtocol", "WireStubXCTest"],
            path: "Tests/WireStubArchitectureTests"
        ),
    ]
)
