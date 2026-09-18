// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SciToolbox",
    platforms: [.macOS("15.0")],
    targets: [
        .executableTarget(
            name: "SciToolbox",
            path: "Sources/SciToolbox",
            resources: [
                .copy("Resources")
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "SciToolboxTests",
            dependencies: ["SciToolbox"],
            path: "Tests/SciToolboxTests",
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
