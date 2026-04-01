// swift-tools-version: 6.3
import Foundation
import PackageDescription

func latestWindowsSDKCPPWinRTInclude() -> String? {
    let root = URL(fileURLWithPath: #"C:\Program Files (x86)\Windows Kits\10\Include"#)
    let fileManager = FileManager.default
    guard let entries = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
        return nil
    }

    let candidates = entries
        .filter { $0.hasDirectoryPath }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

    for candidate in candidates.reversed() {
        let cppwinrtPath = candidate.appendingPathComponent("cppwinrt").path
        if fileManager.fileExists(atPath: cppwinrtPath) {
            return cppwinrtPath
        }
    }

    return nil
}

func bluetoothWinRTCXXSettings() -> [CXXSetting] {
    guard ProcessInfo.processInfo.operatingSystemVersionString.contains("Windows") || ProcessInfo.processInfo.environment["OS"] == "Windows_NT" else {
        return []
    }

    var settings: [CXXSetting] = [
        .unsafeFlags(["-std=c++20"]),
    ]
    if let cppwinrtPath = latestWindowsSDKCPPWinRTInclude() {
        settings.append(.unsafeFlags(["-I\(cppwinrtPath)"]))
    }
    return settings
}

let package = Package(
    name: "iPhoneEmulatorFoundation",
    products: [
        .executable(name: "EmulatorHost", targets: ["EmulatorHost"]),
        .library(name: "RuntimeCore", targets: ["RuntimeCore"]),
        .library(name: "RuntimePOSIX", targets: ["RuntimePOSIX"]),
        .library(name: "RuntimeWin32", targets: ["RuntimeWin32"]),
        .library(name: "RuntimeFFI", targets: ["RuntimeFFI"]),
        .library(name: "RuntimeObjCExperiment", targets: ["RuntimeObjCExperiment"]),
        .library(name: "RendererCore", targets: ["RendererCore"]),
        .library(name: "RendererText", targets: ["RendererText"]),
        .library(name: "RendererWin32", targets: ["RendererWin32"]),
        .library(name: "EmulatorAppSDK", targets: ["EmulatorAppSDK"]),
        .library(name: "EmulatorDiagnostics", targets: ["EmulatorDiagnostics"]),
        .library(name: "EmulatorOnboarding", targets: ["EmulatorOnboarding"]),
        .library(name: "SmokeApp", targets: ["SmokeApp"]),
    ],
    targets: [
        .target(
            name: "RuntimeCore"
        ),
        .target(
            name: "RuntimePOSIX",
            dependencies: ["RuntimeCore"]
        ),
        .target(
            name: "RuntimeWin32",
            dependencies: ["RuntimeCore"]
        ),
        .target(
            name: "CRuntimeShim",
            path: "Sources/CRuntimeShim",
            publicHeadersPath: "include"
        ),
        .target(
            name: "RuntimeFFI",
            dependencies: ["RuntimeCore", "CRuntimeShim"]
        ),
        .target(
            name: "CObjCExperimentShim",
            path: "Sources/CObjCExperimentShim",
            publicHeadersPath: "include"
        ),
        .target(
            name: "RuntimeObjCExperiment",
            dependencies: ["RuntimeCore", "CObjCExperimentShim"]
        ),
        .target(
            name: "RendererCore"
        ),
        .target(
            name: "EmulatorAppSDK",
            dependencies: ["RendererCore", "CBluetoothWinRTShim"]
        ),
        .target(
            name: "EmulatorDiagnostics",
            dependencies: ["EmulatorAppSDK", "RendererCore"]
        ),
        .target(
            name: "EmulatorOnboarding",
            dependencies: [
                "EmulatorAppSDK",
                "EmulatorDiagnostics",
                "RendererText",
                .target(name: "RendererWin32", condition: .when(platforms: [.windows])),
            ]
        ),
        .target(
            name: "CBluetoothWinRTShim",
            path: "Sources/CBluetoothWinRTShim",
            publicHeadersPath: "include",
            cxxSettings: bluetoothWinRTCXXSettings(),
            linkerSettings: [
                .linkedLibrary("ole32", .when(platforms: [.windows])),
                .linkedLibrary("windowsapp", .when(platforms: [.windows])),
            ]
        ),
        .target(
            name: "RendererText",
            dependencies: ["RendererCore"]
        ),
        .target(
            name: "CRendererWin32Shim",
            path: "Sources/CRendererWin32Shim",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedLibrary("d2d1", .when(platforms: [.windows])),
                .linkedLibrary("dwrite", .when(platforms: [.windows])),
                .linkedLibrary("windowscodecs", .when(platforms: [.windows])),
                .linkedLibrary("ole32", .when(platforms: [.windows])),
                .linkedLibrary("user32", .when(platforms: [.windows])),
                .linkedLibrary("gdi32", .when(platforms: [.windows])),
                .linkedLibrary("shcore", .when(platforms: [.windows])),
            ]
        ),
        .target(
            name: "RendererWin32",
            dependencies: ["RendererCore", "EmulatorAppSDK", "CRendererWin32Shim"]
        ),
        .target(
            name: "SmokeApp",
            dependencies: ["RuntimeCore", "RendererCore", "EmulatorAppSDK"]
        ),
        .executableTarget(
            name: "EmulatorHost",
            dependencies: ["RuntimeCore", "RuntimePOSIX", "RuntimeWin32", "RuntimeFFI", "RuntimeObjCExperiment", "RendererCore", "RendererText", "RendererWin32", "EmulatorAppSDK", "EmulatorDiagnostics", "EmulatorOnboarding", "SmokeApp"]
        ),
        .testTarget(
            name: "RuntimeCoreTests",
            dependencies: ["RuntimeCore"]
        ),
        .testTarget(
            name: "RuntimePOSIXTests",
            dependencies: ["RuntimeCore", "RuntimePOSIX"]
        ),
        .testTarget(
            name: "RuntimeWin32Tests",
            dependencies: ["RuntimeCore", "RuntimeWin32"]
        ),
        .testTarget(
            name: "RuntimeFFITests",
            dependencies: ["RuntimeFFI"]
        ),
        .testTarget(
            name: "RuntimeObjCExperimentTests",
            dependencies: ["RuntimeObjCExperiment"]
        ),
        .testTarget(
            name: "RendererCoreTests",
            dependencies: ["RendererCore"]
        ),
        .testTarget(
            name: "RendererTextTests",
            dependencies: ["RendererCore", "RendererText", "SmokeApp"]
        ),
        .testTarget(
            name: "EmulatorAppSDKTests",
            dependencies: ["EmulatorAppSDK"],
            resources: [.process("Fixtures")]
        ),
        .testTarget(
            name: "EmulatorOnboardingTests",
            dependencies: ["EmulatorOnboarding"]
        ),
        .testTarget(
            name: "EmulatorDiagnosticsTests",
            dependencies: ["EmulatorDiagnostics"]
        ),
        .testTarget(
            name: "SmokeAppTests",
            dependencies: ["SmokeApp"]
        ),
        .testTarget(
            name: "EmulatorHostIntegrationTests"
        ),
    ]
)
