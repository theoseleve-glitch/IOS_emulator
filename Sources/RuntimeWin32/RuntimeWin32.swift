import Dispatch
import Foundation
import RuntimeCore

public struct Win32FileSystemService: FileSystemService {
    private let fileManager = FileManager.default

    public init() {}

    public func fileExists(at path: String) -> Bool {
        fileManager.fileExists(atPath: path)
    }

    public func createDirectoryIfNeeded(at path: String) throws {
        guard !fileManager.fileExists(atPath: path) else {
            return
        }

        try fileManager.createDirectory(
            atPath: path,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }
}

public struct Win32ProcessService: ProcessService {
    public let environment: [String: String]
    public let processIdentifier: Int32

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
        self.processIdentifier = Int32(ProcessInfo.processInfo.processIdentifier)
    }
}

public struct Win32ClockService: ClockService {
    public init() {}

    public func now() -> Date {
        Date()
    }
}

public struct Win32TaskScheduler: TaskSchedulingService {
    public init() {}

    public func schedule(_ operation: @escaping @Sendable () -> Void) {
        DispatchQueue.global(qos: .userInitiated).async(execute: operation)
    }
}

public struct Win32MemoryAllocator: MemoryAllocator {
    public init() {}

    public func allocate(byteCount: Int, alignment: Int) throws -> UnsafeMutableRawPointer {
        UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: alignment)
    }

    public func deallocate(_ pointer: UnsafeMutableRawPointer?, byteCount: Int, alignment: Int) {
        pointer?.deallocate()
    }
}

public final class Win32Mutex: MutexHandle, @unchecked Sendable {
    private let primitiveLock = NSLock()

    public init() {}

    public func lock() {
        primitiveLock.lock()
    }

    public func unlock() {
        primitiveLock.unlock()
    }
}

public struct Win32ThreadRuntime: ThreadRuntime {
    public init() {}

    public func spawn(named: String?, operation: @escaping @Sendable () -> Void) {
        DispatchQueue.global(qos: .userInitiated).async(execute: operation)
    }

    public func makeMutex() -> any MutexHandle {
        Win32Mutex()
    }
}

public final class Win32DynamicLibraryHandle: DynamicLibraryHandle, @unchecked Sendable {
    public let path: String

    public init(path: String) {
        self.path = path
    }

    public func resolve(symbol: String) -> UnsafeMutableRawPointer? {
        nil
    }
}

public struct Win32DynamicLibraryLoader: DynamicLibraryLoader {
    private let fileManager = FileManager.default

    public init() {}

    public func openLibrary(at path: String) throws -> any DynamicLibraryHandle {
        guard fileManager.fileExists(atPath: path) else {
            throw DynamicLibraryLoaderError.libraryNotFound(path)
        }

        return Win32DynamicLibraryHandle(path: path)
    }

    public func defaultSearchPaths() -> [String] {
        let process = ProcessInfo.processInfo
        return [
            FileManager.default.currentDirectoryPath,
            process.environment["SystemRoot"].map { "\($0)\\System32" },
            process.environment["ProgramFiles"],
        ].compactMap { $0 }
    }
}

public final class Win32EmulatorRuntime: EmulatorRuntime {
    public private(set) var state: RuntimeState = .idle

    private let registry: AppModuleRegistry
    private let output: @Sendable (String) -> Void
    private var activeModule: (any AppModule)?
    private var context: RuntimeContext?

    public init(
        registry: AppModuleRegistry,
        output: @escaping @Sendable (String) -> Void = { print($0) }
    ) {
        self.registry = registry
        self.output = output
    }

    public func boot(configuration: BootConfiguration) throws {
        guard state == .idle else {
            throw RuntimeError.invalidState(expected: .idle, actual: state, action: "boot")
        }

        let descriptor: AppModuleDescriptor
        do {
            descriptor = try registry.descriptor(for: configuration.appModule)
        } catch let error as AppModuleRegistryError {
            switch error {
            case .moduleNotFound(let identifier):
                throw RuntimeError.appModuleNotFound(identifier)
            case .duplicateIdentifier:
                throw error
            }
        }

        let logger = RuntimeLogger(minimumLevel: configuration.logLevel, sink: output)
        let runtimeContext = RuntimeContext(
            fileSystem: Win32FileSystemService(),
            process: Win32ProcessService(),
            clock: Win32ClockService(),
            taskScheduler: Win32TaskScheduler(),
            memoryAllocator: Win32MemoryAllocator(),
            threadRuntime: Win32ThreadRuntime(),
            dynamicLibraryLoader: Win32DynamicLibraryLoader(),
            logger: logger,
            workingDirectory: configuration.workingDirectory
        )

        activeModule = descriptor.makeModule()
        context = runtimeContext
        state = .booted
        runtimeContext.log(.info, "boot complete: \(descriptor.identifier)")
    }

    public func run() throws {
        guard state == .booted else {
            throw RuntimeError.invalidState(expected: .booted, actual: state, action: "run")
        }

        guard let activeModule, let context else {
            throw RuntimeError.invalidState(expected: .booted, actual: state, action: "run")
        }

        try activeModule.start(context: context)
        state = .running
    }

    public func shutdown() throws {
        guard state == .booted || state == .running else {
            throw RuntimeError.invalidState(expected: .booted, actual: state, action: "shutdown")
        }

        guard let context else {
            throw RuntimeError.invalidState(expected: .booted, actual: state, action: "shutdown")
        }

        if state == .running, let activeModule {
            try activeModule.stop(context: context)
        }

        context.log(.info, "shutdown complete")
        activeModule = nil
        self.context = nil
        state = .shutdown
    }
}
