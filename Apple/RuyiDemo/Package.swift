// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RuyiDemo",
    platforms: [
        .macOS(.v13),
        .iOS(.v16)
    ],
    dependencies: [
        .package(name: "Ruyi", path: "../../")
    ],
    targets: [
        // macOS CLI/SPM fallback. Prefer RuyiDemo.xcodeproj schemes in Xcode.
        .executableTarget(
            name: "RuyiDemo",
            dependencies: [
                .product(name: "Ruyi", package: "Ruyi")
            ],
            path: "Sources",
            exclude: [
                "RuyiDemo-iOS",
                "RuyiDemo-tvOS",
                "RuyiDemo-watchOS",
                "RuyiDemo-visionOS"
            ],
            resources: [
                .copy("RuyiDemo-macOS/Resources/Icons")
            ]
        )
    ]
)
