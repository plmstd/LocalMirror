// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "LocalMirrorCore",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "LocalMirrorCore", targets: ["LocalMirrorCore"])
    ],
    targets: [
        .target(
            name: "LocalMirrorCore",
            path: "LocalMirror",
            exclude: [
                "Assets.xcassets",
                "Helpers",
                "Info.plist",
                "Preview Content",
                "LocalMirror.entitlements",
                "LocalMirrorApp.swift",
                "ContentView.swift",
                "App"
            ],
            sources: [
                "Core",
                "Services",
                "Storage"
            ]
        ),
        .testTarget(
            name: "LocalMirrorCoreTests",
            dependencies: ["LocalMirrorCore"],
            path: "Tests/LocalMirrorCoreTests",
            resources: [
                .copy("Fixtures")
            ]
        )
    ]
)
