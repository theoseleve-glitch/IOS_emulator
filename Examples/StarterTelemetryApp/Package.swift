// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "StarterTelemetryAppPackage",
    products: [
        .library(name: "StarterTelemetryApp", targets: ["StarterTelemetryApp"])
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .target(
            name: "StarterTelemetryApp",
            dependencies: [
                .product(name: "EmulatorAppSDK", package: "iphone_emulator")
            ],
            resources: [
                .process("Resources")
            ]
        )
    ]
)
