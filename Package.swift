// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Liveflow",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Liveflow", targets: ["Liveflow"])
    ],
    dependencies: [
        .package(url: "https://github.com/shogo4405/HaishinKit.swift.git", from: "2.2.5")
    ],
    targets: [
        .executableTarget(
            name: "Liveflow",
            dependencies: [
                .product(name: "HaishinKit", package: "HaishinKit.swift"),
                .product(name: "RTMPHaishinKit", package: "HaishinKit.swift")
            ],
            path: "Sources/Liveflow",
            exclude: [
                "Rendering/Shaders.metal"
            ]
        )
    ]
)
