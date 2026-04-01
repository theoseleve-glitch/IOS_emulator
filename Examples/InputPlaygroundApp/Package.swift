// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "InputPlaygroundAppPackage",
    products: [
        .library(name: "InputPlaygroundApp", targets: ["InputPlaygroundApp"]),
    ],
    dependencies: [
        .package(path: "../.."),
    ],
    targets: [
        .target(
            name: "InputPlaygroundApp",
            dependencies: [
                .product(name: "EmulatorAppSDK", package: "iphone_emulator"),
            ]
        ),
    ]
)
