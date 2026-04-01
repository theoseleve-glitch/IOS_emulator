import EmulatorAppSDK
import EmulatorDiagnostics
import EmulatorOnboarding
import Foundation

enum ExternalAppCommandRunner {
    static func run(arguments: [String], foundationPackagePath: String) throws {
        guard let subcommand = arguments.first else {
            throw ExternalAppCommandError.usage
        }

        switch subcommand {
        case "validate":
            let options = try parseOptions(arguments: Array(arguments.dropFirst()), requiresRenderer: false)
            try execute(
                mode: .validate(bluetoothBackend: options.bluetoothBackendMode),
                options: options,
                foundationPackagePath: foundationPackagePath
            )
        case "run":
            let options = try parseOptions(arguments: Array(arguments.dropFirst()), requiresRenderer: true)
            try execute(
                mode: .run(
                    renderer: try unwrapRenderer(options.renderer),
                    autoCloseMilliseconds: options.autoCloseMilliseconds,
                    bluetoothBackend: options.bluetoothBackendMode,
                    devicePreset: options.devicePreset,
                    orientation: options.orientation,
                    backgroundAfterMilliseconds: options.backgroundAfterMilliseconds,
                    resumeAfterMilliseconds: options.resumeAfterMilliseconds,
                    rotateAfterMilliseconds: options.rotateAfterMilliseconds
                ),
                options: options,
                foundationPackagePath: foundationPackagePath
            )
        case "inspect":
            let options = try parseOptions(arguments: Array(arguments.dropFirst()), requiresRenderer: true)
            try execute(
                mode: .inspect(
                    renderer: try unwrapRenderer(options.renderer),
                    bluetoothBackend: options.bluetoothBackendMode,
                    devicePreset: options.devicePreset,
                    orientation: options.orientation,
                    format: options.format
                ),
                options: options,
                foundationPackagePath: foundationPackagePath
            )
        case "trace":
            let options = try parseOptions(arguments: Array(arguments.dropFirst()), requiresRenderer: true)
            try execute(
                mode: .trace(
                    renderer: try unwrapRenderer(options.renderer),
                    autoCloseMilliseconds: options.autoCloseMilliseconds,
                    bluetoothBackend: options.bluetoothBackendMode,
                    devicePreset: options.devicePreset,
                    orientation: options.orientation,
                    backgroundAfterMilliseconds: options.backgroundAfterMilliseconds,
                    resumeAfterMilliseconds: options.resumeAfterMilliseconds,
                    rotateAfterMilliseconds: options.rotateAfterMilliseconds,
                    format: options.format
                ),
                options: options,
                foundationPackagePath: foundationPackagePath
            )
        case "compat-check":
            let options = try parseOptions(arguments: Array(arguments.dropFirst()), requiresRenderer: false)
            try execute(
                mode: .compatCheck(
                    renderer: options.renderer,
                    bluetoothBackend: options.bluetoothBackendMode,
                    format: options.format
                ),
                options: options,
                foundationPackagePath: foundationPackagePath
            )
        default:
            throw ExternalAppCommandError.usage
        }
    }

    private static func execute(
        mode: ExternalAppRunMode,
        options: ParsedOptions,
        foundationPackagePath: String
    ) throws {
        let workspace = try EmulatorOnboarding.prepareRunnerWorkspace(
            foundationPackagePath: foundationPackagePath,
            appPackagePath: options.packagePath
        )
        let swiftExecutable = resolveSwiftExecutable()
        let arguments = EmulatorOnboarding.swiftArguments(for: mode, workspace: workspace)
        let result = try runProcess(
            executable: swiftExecutable,
            arguments: arguments,
            currentDirectory: foundationPackagePath,
            timeout: mode.timeout
        )

        if !result.output.isEmpty {
            print(result.output)
        }

        guard result.exitCode == 0 else {
            throw ExternalAppCommandError.commandFailed(result.output.isEmpty ? "Generated runner failed with exit code \(result.exitCode)." : result.output)
        }
    }

    private static func unwrapRenderer(_ renderer: EmulatorRendererMode?) throws -> EmulatorRendererMode {
        guard let renderer else {
            throw ExternalAppCommandError.usage
        }

        return renderer
    }

    private static func parseOptions(arguments: [String], requiresRenderer: Bool) throws -> ParsedOptions {
        var packagePath: String?
        var renderer: EmulatorRendererMode?
        var autoCloseMilliseconds: Int32?
        var bluetoothBackendMode: EmulatorBluetoothBackendMode = .auto
        var devicePreset: EmulatorDevicePreset?
        var orientation: EmulatorDeviceOrientation?
        var backgroundAfterMilliseconds: Int32?
        var resumeAfterMilliseconds: Int32?
        var rotateAfterMilliseconds: Int32?
        var format: EmulatorDiagnosticsFormat = .text
        var index = 0

        while index < arguments.count {
            switch arguments[index] {
            case "--package-path":
                guard index + 1 < arguments.count else {
                    throw ExternalAppCommandError.usage
                }
                packagePath = arguments[index + 1]
                index += 2
            case "--renderer":
                guard index + 1 < arguments.count else {
                    throw ExternalAppCommandError.usage
                }
                guard let parsed = EmulatorRendererMode(rawValue: arguments[index + 1]) else {
                    throw ExternalAppCommandError.invalidRenderer(arguments[index + 1])
                }
                renderer = parsed
                index += 2
            case "--autoclose-ms":
                guard index + 1 < arguments.count else {
                    throw ExternalAppCommandError.usage
                }
                guard let parsed = Int32(arguments[index + 1]) else {
                    throw ExternalAppCommandError.invalidAutoClose(arguments[index + 1])
                }
                autoCloseMilliseconds = parsed
                index += 2
            case "--bluetooth-backend":
                guard index + 1 < arguments.count else {
                    throw ExternalAppCommandError.usage
                }
                guard let parsed = EmulatorBluetoothBackendMode(rawValue: arguments[index + 1]) else {
                    throw ExternalAppCommandError.invalidBluetoothBackend(arguments[index + 1])
                }
                bluetoothBackendMode = parsed
                index += 2
            case "--device-preset":
                guard index + 1 < arguments.count else {
                    throw ExternalAppCommandError.usage
                }
                guard let parsed = EmulatorDevicePreset(rawValue: arguments[index + 1]) else {
                    throw ExternalAppCommandError.invalidDevicePreset(arguments[index + 1])
                }
                devicePreset = parsed
                index += 2
            case "--orientation":
                guard index + 1 < arguments.count else {
                    throw ExternalAppCommandError.usage
                }
                guard let parsed = EmulatorDeviceOrientation(rawValue: arguments[index + 1]) else {
                    throw ExternalAppCommandError.invalidOrientation(arguments[index + 1])
                }
                orientation = parsed
                index += 2
            case "--background-after-ms":
                guard index + 1 < arguments.count else {
                    throw ExternalAppCommandError.usage
                }
                guard let parsed = Int32(arguments[index + 1]) else {
                    throw ExternalAppCommandError.invalidSimulationDelay(arguments[index + 1])
                }
                backgroundAfterMilliseconds = parsed
                index += 2
            case "--resume-after-ms":
                guard index + 1 < arguments.count else {
                    throw ExternalAppCommandError.usage
                }
                guard let parsed = Int32(arguments[index + 1]) else {
                    throw ExternalAppCommandError.invalidSimulationDelay(arguments[index + 1])
                }
                resumeAfterMilliseconds = parsed
                index += 2
            case "--rotate-after-ms":
                guard index + 1 < arguments.count else {
                    throw ExternalAppCommandError.usage
                }
                guard let parsed = Int32(arguments[index + 1]) else {
                    throw ExternalAppCommandError.invalidSimulationDelay(arguments[index + 1])
                }
                rotateAfterMilliseconds = parsed
                index += 2
            case "--format":
                guard index + 1 < arguments.count else {
                    throw ExternalAppCommandError.usage
                }
                guard let parsed = EmulatorDiagnosticsFormat(rawValue: arguments[index + 1]) else {
                    throw ExternalAppCommandError.invalidFormat(arguments[index + 1])
                }
                format = parsed
                index += 2
            default:
                throw ExternalAppCommandError.usage
            }
        }

        guard let packagePath else {
            throw ExternalAppCommandError.usage
        }

        if requiresRenderer && renderer == nil {
            throw ExternalAppCommandError.usage
        }

        return ParsedOptions(
            packagePath: packagePath,
            renderer: renderer,
            autoCloseMilliseconds: autoCloseMilliseconds,
            bluetoothBackendMode: bluetoothBackendMode,
            devicePreset: devicePreset,
            orientation: orientation,
            backgroundAfterMilliseconds: backgroundAfterMilliseconds,
            resumeAfterMilliseconds: resumeAfterMilliseconds,
            rotateAfterMilliseconds: rotateAfterMilliseconds,
            format: format
        )
    }

    private static func resolveSwiftExecutable() -> String {
        #if os(Windows)
        let executableName = "swift.exe"
        #else
        let executableName = "swift"
        #endif

        if let resolved = resolveOnPath(named: executableName) {
            return resolved
        }

        return executableName
    }

    private static func resolveOnPath(named executableName: String) -> String? {
        let environment = ProcessInfo.processInfo.environment
        let pathKey = environment.keys.first(where: { $0.caseInsensitiveCompare("PATH") == .orderedSame }) ?? "PATH"
        #if os(Windows)
        let separator = ";"
        #else
        let separator = ":"
        #endif

        for entry in (environment[pathKey] ?? "").split(separator: Character(separator)).map(String.init) where !entry.isEmpty {
            let candidate = URL(fileURLWithPath: entry).appendingPathComponent(executableName).path
            if FileManager.default.isExecutableFile(atPath: candidate) || FileManager.default.fileExists(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }

    private static func runProcess(
        executable: String,
        arguments: [String],
        currentDirectory: String,
        timeout: TimeInterval
    ) throws -> ProcessResult {
        let process = Process()
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("emulator-app-command-\(UUID().uuidString).log")
        _ = FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let outputHandle = try FileHandle(forWritingTo: outputURL)

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = outputHandle
        process.standardError = outputHandle

        try process.run()

        let waitGroup = DispatchGroup()
        waitGroup.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            process.waitUntilExit()
            waitGroup.leave()
        }

        if waitGroup.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            _ = waitGroup.wait(timeout: .now() + 5)
        }

        try outputHandle.close()
        let data = try Data(contentsOf: outputURL)
        try? FileManager.default.removeItem(at: outputURL)
        return ProcessResult(
            exitCode: process.terminationStatus,
            output: String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

private struct ParsedOptions {
    let packagePath: String
    let renderer: EmulatorRendererMode?
    let autoCloseMilliseconds: Int32?
    let bluetoothBackendMode: EmulatorBluetoothBackendMode
    let devicePreset: EmulatorDevicePreset?
    let orientation: EmulatorDeviceOrientation?
    let backgroundAfterMilliseconds: Int32?
    let resumeAfterMilliseconds: Int32?
    let rotateAfterMilliseconds: Int32?
    let format: EmulatorDiagnosticsFormat
}

private struct ProcessResult {
    let exitCode: Int32
    let output: String
}

private enum ExternalAppCommandError: Error, CustomStringConvertible {
    case usage
    case invalidRenderer(String)
    case invalidAutoClose(String)
    case invalidBluetoothBackend(String)
    case invalidDevicePreset(String)
    case invalidOrientation(String)
    case invalidSimulationDelay(String)
    case invalidFormat(String)
    case commandFailed(String)

    var description: String {
        switch self {
        case .usage:
            return "Usage: swift run EmulatorHost app <validate|run|inspect|trace|compat-check> --package-path <path> [--renderer <text|win32>] [--format <text|json>] [--autoclose-ms <n>] [--bluetooth-backend <auto|mock|winrt>] [--device-preset <phoneCompact|phoneTall|tablet>] [--orientation <portrait|landscape>] [--background-after-ms <n>] [--resume-after-ms <n>] [--rotate-after-ms <n>]"
        case .invalidRenderer(let value):
            return "Unsupported renderer: \(value)"
        case .invalidAutoClose(let value):
            return "Invalid auto-close value: \(value)"
        case .invalidBluetoothBackend(let value):
            return "Invalid Bluetooth backend: \(value)"
        case .invalidDevicePreset(let value):
            return "Invalid device preset: \(value)"
        case .invalidOrientation(let value):
            return "Invalid orientation: \(value)"
        case .invalidSimulationDelay(let value):
            return "Invalid simulation delay: \(value)"
        case .invalidFormat(let value):
            return "Unsupported diagnostics format: \(value)"
        case .commandFailed(let output):
            return output
        }
    }
}

private extension ExternalAppRunMode {
    var timeout: TimeInterval {
        switch self {
        case .validate:
            return 180
        case .inspect, .compatCheck:
            return 180
        case .trace(let renderer, let autoCloseMilliseconds, _, _, _, _, _, _, _):
            switch renderer {
            case .text:
                return 180
            case .win32:
                let autoClose = max(1500, Int(autoCloseMilliseconds ?? 1500))
                return TimeInterval(autoClose) / 1000.0 + 45
            }
        case .run(let renderer, let autoCloseMilliseconds, _, _, _, _, _, _):
            switch renderer {
            case .text:
                return 180
            case .win32:
                let autoClose = max(1500, Int(autoCloseMilliseconds ?? 1500))
                return TimeInterval(autoClose) / 1000.0 + 45
            }
        }
    }
}
