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
            // Resources 由 build.sh 手动拷进 .app（tools 二进制、AppIcon、token），
            // SwiftPM 不参与这部分打包；不排除的话每次编译都会报 unhandled files
            // 和 libgif 的失效符号链接。
            exclude: ["Resources"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreServices"),
                .linkedFramework("ServiceManagement")
            ]
        )
    ]
)
