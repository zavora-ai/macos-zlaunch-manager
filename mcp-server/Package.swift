// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "zlm-mcp-server",
    platforms: [.macOS(.v14)],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "zlm-mcp-server",
            path: "Sources"
        ),
    ]
)
