// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Stira",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Stira",
            path: "Sources/Stira"
        ),
        .executableTarget(
            name: "StiraExtensionBridge",
            path: "Sources/StiraExtensionBridge"
        ),
    ]
)
