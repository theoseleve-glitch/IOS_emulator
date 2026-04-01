// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "BluetoothTelemetryAppPackage",
    products: [
        .library(name: "BluetoothTelemetryApp", targets: ["BluetoothTelemetryApp"]),
    ],
    dependencies: [
        .package(path: "../../"),
    ],
    targets: [
        .target(
            name: "BluetoothTelemetryApp",
            dependencies: [
                .product(name: "EmulatorAppSDK", package: "iphone_emulator"),
            ]
        ),
    ]
)
