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
    targets: [
        .target(
            name: "CThorVG",
            path: "Sources/CThorVG",
            publicHeadersPath: "include",
            cxxSettings: [
                .define("TVG_STATIC"),
                .headerSearchPath("include"),
                .headerSearchPath("src/common"),
                .headerSearchPath("src/renderer"),
                .headerSearchPath("src/renderer/cpu_engine"),
                .headerSearchPath("src/loaders"),
                .headerSearchPath("src/loaders/svg"),
                .headerSearchPath("src/loaders/raw"),
                .headerSearchPath("src/bindings/capi")
            ],
            linkerSettings: [
                .linkedLibrary("c++")
            ]
        ),
        .target(
            name: "Ruyi",
            dependencies: ["CThorVG"],
            path: "Sources/Ruyi"
        ),
        .testTarget(
            name: "RuyiTests",
            dependencies: ["Ruyi"],
            path: "Tests/RuyiTests",
            resources: [
                .copy("Resources/sample.svg")
            ]
        )
    ],
    cxxLanguageStandard: .cxx17
)
