// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Spare",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "spare", targets: ["spare"]),
        .executable(name: "SpareApp", targets: ["SpareApp"]),
    ],
    targets: [
        .target(name: "SpareCore"),
        .target(name: "SpareCLI", dependencies: ["SpareCore"]),
        .executableTarget(name: "spare", dependencies: ["SpareCLI", "SpareCore"]),
        .executableTarget(name: "SpareApp", dependencies: ["SpareCore"]),
        .target(name: "SpareTestSupport", dependencies: ["SpareCore"]),
        .testTarget(name: "SpareCoreTests", dependencies: ["SpareCore", "SpareTestSupport"]),
        .testTarget(name: "SpareAppTests", dependencies: ["SpareApp", "SpareCore", "SpareTestSupport"]),
        .testTarget(name: "SpareCLITests", dependencies: ["SpareCLI", "SpareCore", "SpareTestSupport"]),
    ]
)
