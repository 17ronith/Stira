// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Stira",
    platforms: [.macOS(.v14)],
    targets: [
        // Library containing all app logic and UI — previews work in library targets
        .target(
            name: "StiraCore",
            path: "Sources/Stira"
        ),
        // Executable: just calls StiraApp.main() to start the SwiftUI run loop
        .executableTarget(
            name: "Stira",
            dependencies: ["StiraCore"],
            path: "Sources/StiraApp"
        ),
        .executableTarget(
            name: "StiraExtensionBridge",
            path: "Sources/StiraExtensionBridge"
        ),
    ]
)
