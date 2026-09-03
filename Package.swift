// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Livestreamer",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Livestreamer", targets: ["Livestreamer"])
    ],
    dependencies: [
        .package(url: "https://github.com/shogo4405/HaishinKit.swift.git", from: "2.2.5")
    ],
    targets: [
        .executableTarget(
            name: "Livestreamer",
            dependencies: [
                .product(name: "HaishinKit", package: "HaishinKit.swift"),
                .product(name: "RTMPHaishinKit", package: "HaishinKit.swift")
            ],
            path: "Sources/Livestreamer",
            exclude: [
                "Rendering/Shaders.metal"
            ]
        )
    ]
)
