// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Ruyi",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
        .tvOS(.v13),
        .watchOS(.v7),
        .visionOS(.v1)
    ],
    products: [
        .library(name: "Ruyi", targets: ["Ruyi"])
    ],
    dependencies: [
        // SVG-trimmed ThorVG binary (CPU + SVG + C API). Personal fork — not official Lottie package.
        .package(url: "https://github.com/vnixx/thorvg.swift.git", from: "0.0.3")
    ],
    targets: [
        .target(
            name: "Ruyi",
            dependencies: [
                .product(name: "ThorVG", package: "thorvg.swift")
            ],
            path: "Apple/Sources/Ruyi",
            linkerSettings: [
                .linkedLibrary("c++")
            ]
        ),
        .testTarget(
            name: "RuyiTests",
            dependencies: ["Ruyi"],
            path: "Apple/Tests/RuyiTests",
            resources: [
                .copy("Resources/sample.svg")
            ]
        )
    ]
)
