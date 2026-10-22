// swift-tools-version:6.0
// Visual prototype of the Spare app (mock data, no disk access). Not part of the main package.
import PackageDescription

let package = Package(
    name: "SpareProto",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "SpareProto"),
    ]
)
