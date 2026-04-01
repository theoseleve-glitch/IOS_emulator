import Foundation
#if os(Windows)
import WinSDK
#endif

public enum EmulatorCapability: String, CaseIterable, Codable, Hashable, Sendable {
    case bluetooth
    case storage
    case network
    case clock
    case logging
    case clipboard
}

public enum EmulatorCapabilityAvailability: String, Codable, Equatable, Sendable {
    case available
    case degraded
    case unavailable
}

public struct EmulatorCapabilityStatus: Equatable, Sendable {
    public let capability: EmulatorCapability
    public let availability: EmulatorCapabilityAvailability
    public let message: String

    public init(
        capability: EmulatorCapability,
        availability: EmulatorCapabilityAvailability,
        message: String
    ) {
        self.capability = capability
        self.availability = availability
        self.message = message
    }
}

public struct EmulatorCapabilityValidationReport: Equatable, Sendable {
    public let rendererMode: EmulatorRendererMode
    public let statuses: [EmulatorCapabilityStatus]

    public init(rendererMode: EmulatorRendererMode, statuses: [EmulatorCapabilityStatus]) {
        self.rendererMode = rendererMode
        self.statuses = statuses.sorted { $0.capability.rawValue < $1.capability.rawValue }
    }

    public var unavailableCapabilities: [EmulatorCapabilityStatus] {
        statuses.filter { $0.availability == .unavailable }
    }

    public var launchable: Bool {
        unavailableCapabilities.isEmpty
    }
}

public enum EmulatorHostServiceError: Error, Equatable, CustomStringConvertible {
    case unavailable(String)
    case invalidStorageKey(String)
    case ioFailure(String)
    case networkFailure(String)
    case clipboardFailure(String)

    public var description: String {
        switch self {
        case .unavailable(let message),
             .ioFailure(let message),
             .networkFailure(let message),
             .clipboardFailure(let message):
            return message
        case .invalidStorageKey(let key):
            return "Invalid storage key: \(key)"
        }
    }
}

public enum EmulatorLogLevel: String, Codable, Equatable, Sendable {
    case debug
    case info
    case warning
    case error
}

public protocol EmulatorClockService: Sendable {
    var now: Date { get }
    func monotonicTimeMilliseconds() -> UInt64
}

public protocol EmulatorStorageService: Sendable {
    var rootPath: String { get }
    func readData(forKey key: String) throws -> Data?
    func writeData(_ data: Data, forKey key: String) throws
    func readString(forKey key: String) throws -> String?
    func writeString(_ value: String, forKey key: String) throws
}

public protocol EmulatorNetworkService: Sendable {
    func fetch(url: URL) throws -> Data
}

public protocol EmulatorLoggingService: Sendable {
    func log(_ level: EmulatorLogLevel, _ message: String)
}

public protocol EmulatorClipboardService: Sendable {
    func readText() throws -> String?
    func writeText(_ text: String) throws
}

public final class EmulatorHostServices: @unchecked Sendable {
    public let clock: any EmulatorClockService
    public let storage: any EmulatorStorageService
    public let network: any EmulatorNetworkService
    public let logging: any EmulatorLoggingService
    public let clipboard: any EmulatorClipboardService
    public let bluetooth: any EmulatorBluetoothService
    public let invalidation: any EmulatorUIInvalidationService
    public let diagnostics: any EmulatorDiagnosticsService

    private let statusesByCapability: [EmulatorCapability: EmulatorCapabilityStatus]

    public init(
        clock: any EmulatorClockService,
        storage: any EmulatorStorageService,
        network: any EmulatorNetworkService,
        logging: any EmulatorLoggingService,
        clipboard: any EmulatorClipboardService,
        bluetooth: any EmulatorBluetoothService,
        invalidation: any EmulatorUIInvalidationService,
        diagnostics: any EmulatorDiagnosticsService,
        statuses: [EmulatorCapabilityStatus]
    ) {
        self.clock = clock
        self.storage = storage
        self.network = network
        self.logging = logging
        self.clipboard = clipboard
        self.bluetooth = bluetooth
        self.invalidation = invalidation
        self.diagnostics = diagnostics
        self.statusesByCapability = Dictionary(uniqueKeysWithValues: statuses.map { ($0.capability, $0) })
    }

    public func status(for capability: EmulatorCapability) -> EmulatorCapabilityStatus? {
        statusesByCapability[capability]
    }

    public static func defaults(
        appID: String = "emulator.defaults",
        rendererMode: EmulatorRendererMode = .text,
        foundationRootPath: String = FileManager.default.currentDirectoryPath,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bluetoothBackendMode: EmulatorBluetoothBackendMode = .auto
    ) -> EmulatorHostServices {
        let manifest = EmulatorAppManifest(
            appID: appID,
            displayName: "Defaults",
            supportedRenderers: [rendererMode]
        )
        let registry = EmulatorHostServiceRegistry(
            rendererMode: rendererMode,
            foundationRootPath: foundationRootPath,
            environment: environment,
            bluetoothBackendMode: bluetoothBackendMode
        )
        return (try? registry.makeServices(for: manifest))
            ?? EmulatorHostServices(
                clock: SystemClockService(),
                storage: FileStorageService(rootPath: FileManager.default.temporaryDirectory.appendingPathComponent(appID).path),
                network: SimpleNetworkService(),
                logging: StructuredLoggingService(appID: appID, logFilePath: nil),
                clipboard: NoopClipboardService(),
                bluetooth: UnavailableBluetoothService(backendMode: bluetoothBackendMode, message: "Bluetooth is unavailable in default services."),
                invalidation: NoopUIInvalidationService(),
                diagnostics: NoopDiagnosticsService(),
                statuses: []
            )
    }
}

public enum EmulatorHostServiceRegistryError: Error, Equatable, CustomStringConvertible {
    case unavailableRequiredCapabilities(renderer: EmulatorRendererMode, statuses: [EmulatorCapabilityStatus])

    public var description: String {
        switch self {
        case .unavailableRequiredCapabilities(let renderer, let statuses):
            let details = statuses
                .map { "\($0.capability.rawValue)=\($0.message)" }
                .joined(separator: ", ")
            return "Renderer \(renderer.rawValue) is missing required capabilities: \(details)"
        }
    }
}

public final class EmulatorHostServiceRegistry: @unchecked Sendable {
    private let rendererMode: EmulatorRendererMode
    private let foundationRootPath: String
    private let environment: [String: String]
    private let fileManager: FileManager
    private let bluetoothBackendMode: EmulatorBluetoothBackendMode

    public init(
        rendererMode: EmulatorRendererMode,
        foundationRootPath: String = FileManager.default.currentDirectoryPath,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default,
        bluetoothBackendMode: EmulatorBluetoothBackendMode = .auto
    ) {
        self.rendererMode = rendererMode
        self.foundationRootPath = foundationRootPath
        self.environment = environment
        self.fileManager = fileManager
        self.bluetoothBackendMode = bluetoothBackendMode
    }

    public func validationReport(for manifest: EmulatorAppManifest) -> EmulatorCapabilityValidationReport {
        let statuses = manifest.requiredCapabilities.map { capabilityStatus(for: $0, manifest: manifest) }
        return EmulatorCapabilityValidationReport(rendererMode: rendererMode, statuses: statuses)
    }

    public func makeServices(
        for manifest: EmulatorAppManifest,
        invalidationService: (any EmulatorUIInvalidationService)? = nil,
        diagnosticsService: (any EmulatorDiagnosticsService)? = nil
    ) throws -> EmulatorHostServices {
        let report = validationReport(for: manifest)
        guard report.launchable else {
            throw EmulatorHostServiceRegistryError.unavailableRequiredCapabilities(
                renderer: rendererMode,
                statuses: report.unavailableCapabilities
            )
        }

        let appDataRoot = resolveAppDataRoot(for: manifest.appID)
        try fileManager.createDirectory(atPath: appDataRoot, withIntermediateDirectories: true, attributes: nil)
        let logFilePath = URL(fileURLWithPath: appDataRoot).appendingPathComponent("host.log").path
        let bluetoothService = makeBluetoothService(for: manifest)

        return EmulatorHostServices(
            clock: SystemClockService(),
            storage: FileStorageService(rootPath: appDataRoot, fileManager: fileManager),
            network: SimpleNetworkService(),
            logging: StructuredLoggingService(appID: manifest.appID, logFilePath: logFilePath),
            clipboard: clipboardService(),
            bluetooth: bluetoothService,
            invalidation: invalidationService ?? NoopUIInvalidationService(),
            diagnostics: diagnosticsService ?? NoopDiagnosticsService(),
            statuses: report.statuses
        )
    }

    public func firstLaunchableRenderer(for manifest: EmulatorAppManifest) -> EmulatorRendererMode? {
        let orderedRenderers = preferredRendererOrder(for: manifest)
        for renderer in orderedRenderers {
            let registry = EmulatorHostServiceRegistry(
                rendererMode: renderer,
                foundationRootPath: foundationRootPath,
                environment: environment,
                fileManager: fileManager,
                bluetoothBackendMode: bluetoothBackendMode
            )
            if registry.validationReport(for: manifest).launchable {
                return renderer
            }
        }

        return nil
    }

    private func preferredRendererOrder(for manifest: EmulatorAppManifest) -> [EmulatorRendererMode] {
        let all = Array(manifest.supportedRenderers).sorted { $0.rawValue < $1.rawValue }
        if let preferredIndex = all.firstIndex(of: manifest.defaultRenderer) {
            var ordered = all
            let preferred = ordered.remove(at: preferredIndex)
            ordered.insert(preferred, at: 0)
            return ordered
        }

        return all
    }

    private func capabilityStatus(for capability: EmulatorCapability, manifest: EmulatorAppManifest) -> EmulatorCapabilityStatus {
        switch capability {
        case .clock:
            return EmulatorCapabilityStatus(
                capability: capability,
                availability: .available,
                message: "Monotonic and wall clock access is available."
            )
        case .storage:
            return EmulatorCapabilityStatus(
                capability: capability,
                availability: .available,
                message: "App-scoped storage is available under \(resolveAppDataRoot(for: manifest.appID))."
            )
        case .logging:
            return EmulatorCapabilityStatus(
                capability: capability,
                availability: .available,
                message: "Structured stdout and file logging is available."
            )
        case .network:
            return EmulatorCapabilityStatus(
                capability: capability,
                availability: .available,
                message: "Basic HTTP fetch support is available."
            )
        case .clipboard:
            switch rendererMode {
            case .win32:
                #if os(Windows)
                return EmulatorCapabilityStatus(
                    capability: capability,
                    availability: .available,
                    message: "Windows clipboard access is available."
                )
                #else
                return EmulatorCapabilityStatus(
                    capability: capability,
                    availability: .unavailable,
                    message: "Clipboard requires a native Windows host."
                )
                #endif
            case .text:
                return EmulatorCapabilityStatus(
                    capability: capability,
                    availability: .degraded,
                    message: "Clipboard is stubbed in text renderer mode."
                )
            }
        case .bluetooth:
            let resolution = resolveBluetoothBackend()
            switch resolution.status {
            case .available:
                return EmulatorCapabilityStatus(
                    capability: capability,
                    availability: .available,
                    message: "Bluetooth uses the \(resolution.backend.rawValue) backend."
                )
            case .degraded:
                return EmulatorCapabilityStatus(
                    capability: capability,
                    availability: .degraded,
                    message: resolution.message
                )
            case .unavailable:
                return EmulatorCapabilityStatus(
                    capability: capability,
                    availability: .unavailable,
                    message: resolution.message
                )
            }
        }
    }

    private func makeBluetoothService(for manifest: EmulatorAppManifest) -> any EmulatorBluetoothService {
        let resolution = resolveBluetoothBackend()
        switch resolution.backend {
        case .mock:
            return MockBluetoothService()
        case .winrt:
            if let service = WinRTBluetoothService() {
                return service
            }
            return UnavailableBluetoothService(backendMode: .winrt, message: resolution.message)
        case .auto:
            if let service = WinRTBluetoothService(), resolution.status == .available {
                return service
            }
            return MockBluetoothService()
        }
    }

    private func resolveBluetoothBackend() -> BluetoothBackendResolution {
        switch bluetoothBackendMode {
        case .mock:
            return BluetoothBackendResolution(
                backend: .mock,
                status: .degraded,
                message: "Bluetooth uses the deterministic mock backend."
            )
        case .winrt:
            guard rendererMode == .win32 else {
                return BluetoothBackendResolution(
                    backend: .winrt,
                    status: .unavailable,
                    message: "The live WinRT Bluetooth backend is only supported with the Win32 renderer in block 5."
                )
            }
            guard WinRTBluetoothService.isSupported else {
                return BluetoothBackendResolution(
                    backend: .winrt,
                    status: .unavailable,
                    message: "The live WinRT Bluetooth backend is not supported by this host toolchain."
                )
            }

            let adapterState = WinRTBluetoothService.adapterStateValue()
            switch adapterState {
            case .poweredOn, .poweredOff, .unknown:
                return BluetoothBackendResolution(
                    backend: .winrt,
                    status: .available,
                    message: "Bluetooth uses the live WinRT backend."
                )
            case .unauthorized:
                return BluetoothBackendResolution(
                    backend: .winrt,
                    status: .unavailable,
                    message: "The live WinRT Bluetooth backend is unauthorized on this host."
                )
            case .unavailable:
                return BluetoothBackendResolution(
                    backend: .winrt,
                    status: .unavailable,
                    message: "The live WinRT Bluetooth backend could not access a usable BLE adapter."
                )
            }
        case .auto:
            guard rendererMode == .win32 else {
                return BluetoothBackendResolution(
                    backend: .mock,
                    status: .degraded,
                    message: "Text-mode Bluetooth uses the mock backend in block 5."
                )
            }
            guard WinRTBluetoothService.isSupported else {
                return BluetoothBackendResolution(
                    backend: .mock,
                    status: .degraded,
                    message: "Bluetooth fell back to the mock backend because the live WinRT backend is unavailable."
                )
            }

            let adapterState = WinRTBluetoothService.adapterStateValue()
            switch adapterState {
            case .poweredOn, .poweredOff, .unknown:
                return BluetoothBackendResolution(
                    backend: .winrt,
                    status: .available,
                    message: "Bluetooth uses the live WinRT backend."
                )
            case .unauthorized, .unavailable:
                return BluetoothBackendResolution(
                    backend: .mock,
                    status: .degraded,
                    message: "Bluetooth fell back to the mock backend because the live WinRT backend is unavailable on this host."
                )
            }
        }
    }

    private func resolveAppDataRoot(for appID: String) -> String {
        let baseRoot: String
        if let override = environment["EMULATOR_APP_DATA_ROOT"], !override.isEmpty {
            baseRoot = override
        } else {
            baseRoot = URL(fileURLWithPath: foundationRootPath)
                .appendingPathComponent(".emulator-cache")
                .appendingPathComponent("apps")
                .path
        }

        return URL(fileURLWithPath: baseRoot)
            .appendingPathComponent(sanitizePathComponent(appID))
            .path
    }

    private func sanitizePathComponent(_ value: String) -> String {
        let filtered = value.map { character -> Character in
            if character.isLetter || character.isNumber || character == "-" || character == "_" || character == "." {
                return character
            }
            return "-"
        }
        let sanitized = String(filtered)
        return sanitized.isEmpty ? "app" : sanitized
    }

    private func clipboardService() -> any EmulatorClipboardService {
        switch rendererMode {
        case .text:
            return NoopClipboardService()
        case .win32:
            #if os(Windows)
            return WindowsClipboardService()
            #else
            return NoopClipboardService()
            #endif
        }
    }
}

private struct BluetoothBackendResolution {
    let backend: EmulatorBluetoothBackendMode
    let status: EmulatorCapabilityAvailability
    let message: String
}

public final class SystemClockService: EmulatorClockService, @unchecked Sendable {
    public init() {}

    public var now: Date {
        Date()
    }

    public func monotonicTimeMilliseconds() -> UInt64 {
        UInt64(ProcessInfo.processInfo.systemUptime * 1000.0)
    }
}

public final class FileStorageService: EmulatorStorageService, @unchecked Sendable {
    public let rootPath: String
    private let fileManager: FileManager

    public init(rootPath: String, fileManager: FileManager = .default) {
        self.rootPath = rootPath
        self.fileManager = fileManager
    }

    public func readData(forKey key: String) throws -> Data? {
        let url = try url(forKey: key)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        return try Data(contentsOf: url)
    }

    public func writeData(_ data: Data, forKey key: String) throws {
        let url = try url(forKey: key)
        try fileManager.createDirectory(
            at: URL(fileURLWithPath: rootPath),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try data.write(to: url, options: .atomic)
    }

    public func readString(forKey key: String) throws -> String? {
        guard let data = try readData(forKey: key) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    public func writeString(_ value: String, forKey key: String) throws {
        try writeData(Data(value.utf8), forKey: key)
    }

    private func url(forKey key: String) throws -> URL {
        guard !key.isEmpty, !key.contains(".."), !key.contains(":"), !key.hasPrefix("/"), !key.hasPrefix("\\") else {
            throw EmulatorHostServiceError.invalidStorageKey(key)
        }

        return URL(fileURLWithPath: rootPath).appendingPathComponent(key)
    }
}

public final class SimpleNetworkService: EmulatorNetworkService, @unchecked Sendable {
    public init() {}

    public func fetch(url: URL) throws -> Data {
        do {
            return try Data(contentsOf: url)
        } catch {
            throw EmulatorHostServiceError.networkFailure(error.localizedDescription)
        }
    }
}

public final class StructuredLoggingService: EmulatorLoggingService, @unchecked Sendable {
    private let appID: String
    private let logFilePath: String?
    private let formatter = ISO8601DateFormatter()

    public init(appID: String, logFilePath: String?) {
        self.appID = appID
        self.logFilePath = logFilePath
    }

    public func log(_ level: EmulatorLogLevel, _ message: String) {
        let line = "[\(level.rawValue)][\(appID)][\(formatter.string(from: Date()))] \(message)"
        print(line)

        guard let logFilePath else {
            return
        }

        let data = Data((line + "\n").utf8)
        if FileManager.default.fileExists(atPath: logFilePath) {
            if let handle = FileHandle(forWritingAtPath: logFilePath) {
                do {
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                    try handle.close()
                } catch {
                    try? handle.close()
                }
            }
        } else {
            _ = FileManager.default.createFile(atPath: logFilePath, contents: data)
        }
    }
}

public final class NoopClipboardService: EmulatorClipboardService, @unchecked Sendable {
    public init() {}

    public func readText() throws -> String? {
        nil
    }

    public func writeText(_ text: String) throws {}
}

#if os(Windows)
public final class WindowsClipboardService: EmulatorClipboardService, @unchecked Sendable {
    public init() {}

    public func readText() throws -> String? {
        guard OpenClipboard(nil) else {
            throw EmulatorHostServiceError.clipboardFailure("Unable to open the Windows clipboard for reading.")
        }
        defer { CloseClipboard() }

        guard let handle = GetClipboardData(UINT(CF_UNICODETEXT)) else {
            return nil
        }

        guard let lockedPointer = GlobalLock(handle) else {
            throw EmulatorHostServiceError.clipboardFailure("Unable to lock clipboard memory for reading.")
        }
        defer { GlobalUnlock(handle) }

        let typedPointer = lockedPointer.assumingMemoryBound(to: UInt16.self)
        return String(decodingCString: typedPointer, as: UTF16.self)
    }

    public func writeText(_ text: String) throws {
        let utf16 = Array(text.utf16) + [0]
        let size = utf16.count * MemoryLayout<UInt16>.stride
        guard let memory = GlobalAlloc(UINT(GMEM_MOVEABLE), SIZE_T(size)) else {
            throw EmulatorHostServiceError.clipboardFailure("Unable to allocate clipboard memory.")
        }

        guard let lockedPointer = GlobalLock(memory) else {
            _ = GlobalFree(memory)
            throw EmulatorHostServiceError.clipboardFailure("Unable to lock clipboard memory for writing.")
        }

        lockedPointer.assumingMemoryBound(to: UInt16.self).update(from: utf16, count: utf16.count)
        GlobalUnlock(memory)

        guard OpenClipboard(nil) else {
            _ = GlobalFree(memory)
            throw EmulatorHostServiceError.clipboardFailure("Unable to open the Windows clipboard for writing.")
        }
        defer { CloseClipboard() }

        guard EmptyClipboard() else {
            _ = GlobalFree(memory)
            throw EmulatorHostServiceError.clipboardFailure("Unable to clear the Windows clipboard.")
        }

        guard SetClipboardData(UINT(CF_UNICODETEXT), memory) != nil else {
            _ = GlobalFree(memory)
            throw EmulatorHostServiceError.clipboardFailure("Unable to write text to the Windows clipboard.")
        }
    }
}
#endif
