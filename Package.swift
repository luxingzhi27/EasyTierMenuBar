// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "EasyTierMenuBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "EasyTierMenuBar", targets: ["EasyTierMenuBar"])
    ],
    targets: [
        .executableTarget(
            name: "EasyTierMenuBar",
            path: "Sources/EasyTierMenuBar"
        ),
        .testTarget(
            name: "EasyTierMenuBarTests",
            dependencies: ["EasyTierMenuBar"],
            path: "Tests/EasyTierMenuBarTests"
        )
    ]
)
