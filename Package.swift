// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EvenToggle",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "EvenToggle",
            path: "Sources/EvenToggle"
        )
    ]
)
