import EmulatorAppSDK
import EmulatorDiagnostics
import Foundation

public struct ExternalAppConfiguration: Codable, Equatable, Sendable {
    public let product: String
    public let module: String
    public let registrationType: String

    public init(product: String, module: String, registrationType: String) {
        self.product = product
        self.module = module
        self.registrationType = registrationType
    }
}

public enum ExternalAppConfigurationError: Error, Equatable, CustomStringConvertible {
    case packagePathNotFound(String)
    case configNotFound(String)
    case invalidConfig(String)
    case invalidPackagePath(String)

    public var description: String {
        switch self {
        case .packagePathNotFound(let path):
            return "External app package path does not exist: \(path)"
        case .configNotFound(let path):
            return "EmulatorApp.json was not found at: \(path)"
        case .invalidConfig(let message):
            return "Invalid EmulatorApp.json: \(message)"
        case .invalidPackagePath(let path):
            return "The package path is invalid: \(path)"
        }
    }
}

public struct ExternalRunnerWorkspace: Equatable, Sendable {
    public let rootPath: String
    public let executableName: String
    public let packagePath: String
    public let configuration: ExternalAppConfiguration

    public init(rootPath: String, executableName: String, packagePath: String, configuration: ExternalAppConfiguration) {
        self.rootPath = rootPath
        self.executableName = executableName
        self.packagePath = packagePath
        self.configuration = configuration
    }
}

public enum ExternalAppRunMode: Equatable, Sendable {
    case validate(bluetoothBackend: EmulatorBluetoothBackendMode)
    case run(
        renderer: EmulatorRendererMode,
        autoCloseMilliseconds: Int32?,
        bluetoothBackend: EmulatorBluetoothBackendMode,
        devicePreset: EmulatorDevicePreset?,
        orientation: EmulatorDeviceOrientation?,
        backgroundAfterMilliseconds: Int32?,
        resumeAfterMilliseconds: Int32?,
        rotateAfterMilliseconds: Int32?
    )
    case inspect(
        renderer: EmulatorRendererMode,
        bluetoothBackend: EmulatorBluetoothBackendMode,
        devicePreset: EmulatorDevicePreset?,
        orientation: EmulatorDeviceOrientation?,
        format: EmulatorDiagnosticsFormat
    )
    case trace(
        renderer: EmulatorRendererMode,
        autoCloseMilliseconds: Int32?,
        bluetoothBackend: EmulatorBluetoothBackendMode,
        devicePreset: EmulatorDevicePreset?,
        orientation: EmulatorDeviceOrientation?,
        backgroundAfterMilliseconds: Int32?,
        resumeAfterMilliseconds: Int32?,
        rotateAfterMilliseconds: Int32?,
        format: EmulatorDiagnosticsFormat
    )
    case compatCheck(
        renderer: EmulatorRendererMode?,
        bluetoothBackend: EmulatorBluetoothBackendMode,
        format: EmulatorDiagnosticsFormat
    )
}

public enum ExternalAppRunnerError: Error, Equatable, CustomStringConvertible {
    case unsupportedRenderer(EmulatorRendererMode)

    public var description: String {
        switch self {
        case .unsupportedRenderer(let renderer):
            return "The requested renderer is not supported by this app: \(renderer.rawValue)"
        }
    }
}

public enum EmulatorOnboarding {
    public static let configFileName = "EmulatorApp.json"
    public static let cacheDirectoryName = ".emulator-cache"
    public static let runnerExecutableName = "EmulatorExternalAppRunner"

    public static func loadConfiguration(at packagePath: String, fileManager: FileManager = .default) throws -> ExternalAppConfiguration {
        let normalizedPackagePath = normalizePath(packagePath)
        guard fileManager.fileExists(atPath: normalizedPackagePath) else {
            throw ExternalAppConfigurationError.packagePathNotFound(normalizedPackagePath)
        }

        let configPath = URL(fileURLWithPath: normalizedPackagePath)
            .appendingPathComponent(configFileName)
            .path
        guard fileManager.fileExists(atPath: configPath) else {
            throw ExternalAppConfigurationError.configNotFound(configPath)
        }

        let data = try Data(contentsOf: URL(fileURLWithPath: configPath))
        do {
            return try JSONDecoder().decode(ExternalAppConfiguration.self, from: data)
        } catch {
            throw ExternalAppConfigurationError.invalidConfig(error.localizedDescription)
        }
    }

    public static func prepareRunnerWorkspace(
        foundationPackagePath: String,
        appPackagePath: String,
        fileManager: FileManager = .default
    ) throws -> ExternalRunnerWorkspace {
        let normalizedFoundationPath = normalizePath(foundationPackagePath)
        let normalizedAppPath = normalizePath(appPackagePath)
        let configuration = try loadConfiguration(at: normalizedAppPath, fileManager: fileManager)
        let runnerKey = stableRunnerKey(foundationPath: normalizedFoundationPath, appPath: normalizedAppPath, configuration: configuration)
        let rootPath = URL(fileURLWithPath: normalizedFoundationPath)
            .appendingPathComponent(cacheDirectoryName)
            .appendingPathComponent("runners")
            .appendingPathComponent(runnerKey)
            .path
        let workspace = ExternalRunnerWorkspace(
            rootPath: rootPath,
            executableName: runnerExecutableName,
            packagePath: normalizedAppPath,
            configuration: configuration
        )

        try fileManager.createDirectory(atPath: rootPath, withIntermediateDirectories: true, attributes: nil)
        let packageSource = makePackageFile(
            foundationPackagePath: normalizedFoundationPath,
            appPackagePath: normalizedAppPath,
            configuration: configuration,
            executableName: runnerExecutableName
        )
        let mainSource = makeMainSource(
            configuration: configuration,
            executableName: runnerExecutableName,
            appPackagePath: normalizedAppPath
        )

        try write(packageSource, to: URL(fileURLWithPath: rootPath).appendingPathComponent("Package.swift"), fileManager: fileManager)
        let sourceRoot = URL(fileURLWithPath: rootPath)
            .appendingPathComponent("Sources")
            .appendingPathComponent(runnerExecutableName)
        try fileManager.createDirectory(at: sourceRoot, withIntermediateDirectories: true, attributes: nil)
        try write(mainSource, to: sourceRoot.appendingPathComponent("main.swift"), fileManager: fileManager)

        return workspace
    }

    public static func swiftArguments(
        for mode: ExternalAppRunMode,
        workspace: ExternalRunnerWorkspace
    ) -> [String] {
        switch mode {
        case .validate(let bluetoothBackend):
            return [
                "run",
                "--package-path", workspace.rootPath,
                workspace.executableName,
                "validate",
                "--bluetooth-backend", bluetoothBackend.rawValue,
            ]
        case .inspect(let renderer, let bluetoothBackend, let devicePreset, let orientation, let format):
            var arguments = [
                "run",
                "--package-path", workspace.rootPath,
                workspace.executableName,
                "inspect",
                "--renderer", renderer.rawValue,
                "--bluetooth-backend", bluetoothBackend.rawValue,
                "--format", format.rawValue,
            ]
            if let devicePreset {
                arguments.append(contentsOf: ["--device-preset", devicePreset.rawValue])
            }
            if let orientation {
                arguments.append(contentsOf: ["--orientation", orientation.rawValue])
            }
            return arguments
        case .trace(
            let renderer,
            let autoCloseMilliseconds,
            let bluetoothBackend,
            let devicePreset,
            let orientation,
            let backgroundAfterMilliseconds,
            let resumeAfterMilliseconds,
            let rotateAfterMilliseconds,
            let format
        ):
            var arguments = [
                "run",
                "--package-path", workspace.rootPath,
                workspace.executableName,
                "trace",
                "--renderer", renderer.rawValue,
                "--bluetooth-backend", bluetoothBackend.rawValue,
                "--format", format.rawValue,
            ]
            if let autoCloseMilliseconds {
                arguments.append(contentsOf: ["--autoclose-ms", String(autoCloseMilliseconds)])
            }
            if let devicePreset {
                arguments.append(contentsOf: ["--device-preset", devicePreset.rawValue])
            }
            if let orientation {
                arguments.append(contentsOf: ["--orientation", orientation.rawValue])
            }
            if let backgroundAfterMilliseconds {
                arguments.append(contentsOf: ["--background-after-ms", String(backgroundAfterMilliseconds)])
            }
            if let resumeAfterMilliseconds {
                arguments.append(contentsOf: ["--resume-after-ms", String(resumeAfterMilliseconds)])
            }
            if let rotateAfterMilliseconds {
                arguments.append(contentsOf: ["--rotate-after-ms", String(rotateAfterMilliseconds)])
            }
            return arguments
        case .compatCheck(let renderer, let bluetoothBackend, let format):
            var arguments = [
                "run",
                "--package-path", workspace.rootPath,
                workspace.executableName,
                "compat-check",
                "--bluetooth-backend", bluetoothBackend.rawValue,
                "--format", format.rawValue,
            ]
            if let renderer {
                arguments.append(contentsOf: ["--renderer", renderer.rawValue])
            }
            return arguments
        case .run(
            let renderer,
            let autoCloseMilliseconds,
            let bluetoothBackend,
            let devicePreset,
            let orientation,
            let backgroundAfterMilliseconds,
            let resumeAfterMilliseconds,
            let rotateAfterMilliseconds
        ):
            var arguments = [
                "run",
                "--package-path", workspace.rootPath,
                workspace.executableName,
                "run",
                "--renderer", renderer.rawValue,
                "--bluetooth-backend", bluetoothBackend.rawValue,
            ]
            if let autoCloseMilliseconds {
                arguments.append(contentsOf: ["--autoclose-ms", String(autoCloseMilliseconds)])
            }
            if let devicePreset {
                arguments.append(contentsOf: ["--device-preset", devicePreset.rawValue])
            }
            if let orientation {
                arguments.append(contentsOf: ["--orientation", orientation.rawValue])
            }
            if let backgroundAfterMilliseconds {
                arguments.append(contentsOf: ["--background-after-ms", String(backgroundAfterMilliseconds)])
            }
            if let resumeAfterMilliseconds {
                arguments.append(contentsOf: ["--resume-after-ms", String(resumeAfterMilliseconds)])
            }
            if let rotateAfterMilliseconds {
                arguments.append(contentsOf: ["--rotate-after-ms", String(rotateAfterMilliseconds)])
            }
            return arguments
        }
    }

    public static func normalizePath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private static func write(_ content: String, to url: URL, fileManager: FileManager) throws {
        let existing = try? String(contentsOf: url, encoding: .utf8)
        if existing == content {
            return
        }

        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func stableRunnerKey(
        foundationPath: String,
        appPath: String,
        configuration: ExternalAppConfiguration
    ) -> String {
        let source = "\(foundationPath)|\(appPath)|\(configuration.product)|\(configuration.module)|\(configuration.registrationType)"
        var hash: UInt64 = 14695981039346656037
        for byte in source.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return String(format: "%016llx", hash)
    }

    private static func packageLiteralPath(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/")
    }

    private static func packageIdentity(for path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent.lowercased()
    }

    private static func makePackageFile(
        foundationPackagePath: String,
        appPackagePath: String,
        configuration: ExternalAppConfiguration,
        executableName: String
    ) -> String {
        let foundationPath = packageLiteralPath(foundationPackagePath)
        let appPath = packageLiteralPath(appPackagePath)
        let foundationPackageIdentity = packageIdentity(for: foundationPackagePath)
        let appPackageIdentity = packageIdentity(for: appPackagePath)
        return """
        // swift-tools-version: 6.3
        import PackageDescription

        let package = Package(
            name: "\(executableName)",
            dependencies: [
                .package(path: "\(foundationPath)"),
                .package(path: "\(appPath)")
            ],
            targets: [
                .executableTarget(
                    name: "\(executableName)",
                    dependencies: [
                        .product(name: "EmulatorOnboarding", package: "\(foundationPackageIdentity)"),
                        .product(name: "\(configuration.product)", package: "\(appPackageIdentity)")
                    ]
                )
            ]
        )
        """
    }

    private static func makeMainSource(
        configuration: ExternalAppConfiguration,
        executableName: String,
        appPackagePath: String
    ) -> String {
        #"""
        import EmulatorOnboarding
        import \#(configuration.module)

        @main
        struct \#(executableName) {
            static func main() throws {
                try ExternalRunnerSupport.run(
                    registration: \#(configuration.registrationType).self,
                    executableName: "\#(executableName)",
                    appPackageRootPath: "\#(appPackagePath.replacingOccurrences(of: "\\", with: "/"))"
                )
            }
        }
        """#
    }
}
