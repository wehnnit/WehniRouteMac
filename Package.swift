// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "WehniRoute",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "WehniRoute", targets: ["WehniRouteApp"]),
    ],
    targets: [
        .target(
            name: "WehniRouteCore",
            path: "Sources/WehniRouteCore"
        ),
        .executableTarget(
            name: "WehniRouteApp",
            dependencies: ["WehniRouteCore"],
            path: "Sources/WehniRouteApp"
        ),
        .testTarget(
            name: "WehniRouteCoreTests",
            dependencies: ["WehniRouteCore"],
            path: "Tests/WehniRouteCoreTests"
        ),
    ]
)
