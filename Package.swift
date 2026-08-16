// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SephiriaOptimizer",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SephiriaOptimizer", targets: ["SephiriaOptimizerApp"])
    ],
    targets: [
        .executableTarget(
            name: "SephiriaOptimizerApp",
            resources: [.process("Resources")],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Vision")
            ]
        ),
        .testTarget(
            name: "SephiriaOptimizerTests",
            dependencies: ["SephiriaOptimizerApp"]
        )
    ]
)
