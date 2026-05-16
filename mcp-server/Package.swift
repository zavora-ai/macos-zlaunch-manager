// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "lm-mcp-server",
    platforms: [.macOS(.v14)],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "lm-mcp-server",
            path: "Sources"
        ),
    ]
)
