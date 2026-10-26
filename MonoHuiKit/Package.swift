// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MonoHuiKit",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MonoHuiKit", targets: ["MonoHuiKit"])
    ],
    targets: [
        .executableTarget(
            name: "MonoHuiKit",
            path: "Sources/App",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreServices"),
                .linkedFramework("ServiceManagement")
            ]
        )
    ]
)
