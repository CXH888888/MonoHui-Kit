// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "QuickActions",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "QuickActions", targets: ["QuickActions"])
    ],
    targets: [
        .executableTarget(
            name: "QuickActions",
            path: "Sources/App",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreServices"),
                .linkedFramework("ServiceManagement")
            ]
        )
    ]
)
