import Foundation

public enum LogLevel: Int, CaseIterable, Comparable, Sendable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3

    public var label: String {
        switch self {
        case .debug:
            return "DEBUG"
        case .info:
            return "INFO"
        case .warning:
            return "WARNING"
        case .error:
            return "ERROR"
        }
    }

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct BootConfiguration: Equatable, Sendable {
    public let appModule: String
    public let workingDirectory: String
    public let logLevel: LogLevel

    public init(
        appModule: String,
        workingDirectory: String = FileManager.default.currentDirectoryPath,
        logLevel: LogLevel = .info
    ) {
        self.appModule = appModule
        self.workingDirectory = workingDirectory
        self.logLevel = logLevel
    }
}

public struct AppModuleDescriptor: Sendable {
    public let identifier: String
    public let displayName: String
    public let makeModule: @Sendable () -> any AppModule

    public init(
        identifier: String,
        displayName: String,
        makeModule: @escaping @Sendable () -> any AppModule
    ) {
        self.identifier = identifier
        self.displayName = displayName
        self.makeModule = makeModule
    }
}

public enum AppModuleRegistryError: Error, Equatable, CustomStringConvertible {
    case duplicateIdentifier(String)
    case moduleNotFound(String)

    public var description: String {
        switch self {
        case .duplicateIdentifier(let identifier):
            return "Duplicate app module identifier '\(identifier)'."
        case .moduleNotFound(let identifier):
            return "App module '\(identifier)' is not registered in the registry."
        }
    }
}

public struct AppModuleRegistry: Sendable {
    public let registeredModules: [AppModuleDescriptor]
    private let modulesByIdentifier: [String: AppModuleDescriptor]

    public init(descriptors: [AppModuleDescriptor]) throws {
        var seenIdentifiers = Set<String>()
        var modulesByIdentifier: [String: AppModuleDescriptor] = [:]

        for descriptor in descriptors {
            if seenIdentifiers.contains(descriptor.identifier) {
                throw AppModuleRegistryError.duplicateIdentifier(descriptor.identifier)
            }

            seenIdentifiers.insert(descriptor.identifier)
            modulesByIdentifier[descriptor.identifier] = descriptor
        }

        self.registeredModules = descriptors
        self.modulesByIdentifier = modulesByIdentifier
    }

    public func descriptor(for identifier: String) throws -> AppModuleDescriptor {
        guard let descriptor = modulesByIdentifier[identifier] else {
            throw AppModuleRegistryError.moduleNotFound(identifier)
        }

        return descriptor
    }
}

public protocol FileSystemService: Sendable {
    func fileExists(at path: String) -> Bool
    func createDirectoryIfNeeded(at path: String) throws
}

public protocol ProcessService: Sendable {
    var environment: [String: String] { get }
    var processIdentifier: Int32 { get }
}

public protocol ClockService: Sendable {
    func now() -> Date
}

public protocol TaskSchedulingService: Sendable {
    func schedule(_ operation: @escaping @Sendable () -> Void)
}

public enum MemoryAllocatorError: Error, Equatable {
    case allocationFailed(byteCount: Int, alignment: Int)
}

public protocol MemoryAllocator: Sendable {
    func allocate(byteCount: Int, alignment: Int) throws -> UnsafeMutableRawPointer
    func deallocate(_ pointer: UnsafeMutableRawPointer?, byteCount: Int, alignment: Int)
}

public protocol MutexHandle: AnyObject, Sendable {
    func lock()
    func unlock()
}

public extension MutexHandle {
    func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}

public protocol ThreadRuntime: Sendable {
    func spawn(named: String?, operation: @escaping @Sendable () -> Void)
    func makeMutex() -> any MutexHandle
}

public enum DynamicLibraryLoaderError: Error, Equatable {
    case libraryNotFound(String)
}

public protocol DynamicLibraryHandle: AnyObject, Sendable {
    var path: String { get }
    func resolve(symbol: String) -> UnsafeMutableRawPointer?
}

public protocol DynamicLibraryLoader: Sendable {
    func openLibrary(at path: String) throws -> any DynamicLibraryHandle
    func defaultSearchPaths() -> [String]
}

public struct RuntimeLogger: Sendable {
    public let minimumLevel: LogLevel
    private let sink: @Sendable (String) -> Void

    public init(minimumLevel: LogLevel, sink: @escaping @Sendable (String) -> Void) {
        self.minimumLevel = minimumLevel
        self.sink = sink
    }

    public func log(_ level: LogLevel, _ message: String) {
        guard level >= minimumLevel else {
            return
        }

        sink("[\(level.label)] \(message)")
    }
}

public struct RuntimeContext: Sendable {
    public let fileSystem: any FileSystemService
    public let process: any ProcessService
    public let clock: any ClockService
    public let taskScheduler: any TaskSchedulingService
    public let memoryAllocator: any MemoryAllocator
    public let threadRuntime: any ThreadRuntime
    public let dynamicLibraryLoader: any DynamicLibraryLoader
    public let logger: RuntimeLogger
    public let workingDirectory: String

    public init(
        fileSystem: any FileSystemService,
        process: any ProcessService,
        clock: any ClockService,
        taskScheduler: any TaskSchedulingService,
        memoryAllocator: any MemoryAllocator,
        threadRuntime: any ThreadRuntime,
        dynamicLibraryLoader: any DynamicLibraryLoader,
        logger: RuntimeLogger,
        workingDirectory: String
    ) {
        self.fileSystem = fileSystem
        self.process = process
        self.clock = clock
        self.taskScheduler = taskScheduler
        self.memoryAllocator = memoryAllocator
        self.threadRuntime = threadRuntime
        self.dynamicLibraryLoader = dynamicLibraryLoader
        self.logger = logger
        self.workingDirectory = workingDirectory
    }

    public func log(_ level: LogLevel, _ message: String) {
        logger.log(level, message)
    }
}

public protocol AppModule: AnyObject {
    var identifier: String { get }
    func start(context: RuntimeContext) throws
    func stop(context: RuntimeContext) throws
}

public enum RuntimeState: String, Sendable {
    case idle
    case booted
    case running
    case shutdown
}

public enum RuntimeError: Error, Equatable, CustomStringConvertible {
    case appModuleNotFound(String)
    case invalidState(expected: RuntimeState, actual: RuntimeState, action: String)

    public var description: String {
        switch self {
        case .appModuleNotFound(let module):
            return "App module '\(module)' is not registered."
        case .invalidState(let expected, let actual, let action):
            return "Cannot \(action) from state '\(actual.rawValue)'. Expected '\(expected.rawValue)'."
        }
    }
}

public protocol EmulatorRuntime: AnyObject {
    var state: RuntimeState { get }
    func boot(configuration: BootConfiguration) throws
    func run() throws
    func shutdown() throws
}
