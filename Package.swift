// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "YeOldBackupCore",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "YeOldBackupCore", targets: ["YeOldBackupCore"])
    ],
    targets: [
        .target(
            name: "YeOldBackupCore",
            path: "YeOldBackup",
            exclude: [
                "Assets.xcassets",
                "Helpers",
                "Info.plist",
                "Preview Content",
                "YeOldBackup.entitlements",
                "YeOldBackupApp.swift",
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
            name: "YeOldBackupCoreTests",
            dependencies: ["YeOldBackupCore"],
            path: "Tests/YeOldBackupCoreTests",
            resources: [
                .copy("Fixtures")
            ]
        )
    ]
)
