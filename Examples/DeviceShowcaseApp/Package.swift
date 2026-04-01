// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "DeviceShowcaseAppPackage",
    products: [
        .library(name: "DeviceShowcaseApp", targets: ["DeviceShowcaseApp"]),
    ],
    dependencies: [
        .package(path: "../.."),
    ],
    targets: [
        .target(
            name: "DeviceShowcaseApp",
            dependencies: [
                .product(name: "EmulatorAppSDK", package: "iphone_emulator"),
            ]
        ),
    ]
)
