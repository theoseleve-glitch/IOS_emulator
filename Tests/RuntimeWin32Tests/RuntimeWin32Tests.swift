import Foundation
import XCTest
@testable import RuntimeCore
@testable import RuntimeWin32

private final class Win32RecordingModule: AppModule, @unchecked Sendable {
    let identifier = "win32-recording"
    private(set) var events: [String] = []

    func start(context: RuntimeContext) throws {
        events.append("start")
        let mutex = context.threadRuntime.makeMutex()
        let scratchPath = context.workingDirectory + "\\objc-runtime.dll"
        let pointer = try context.memoryAllocator.allocate(byteCount: 16, alignment: 8)
        pointer.storeBytes(of: UInt64(0xABCD), as: UInt64.self)
        context.memoryAllocator.deallocate(pointer, byteCount: 16, alignment: 8)

        mutex.withLock {
            events.append("mutex")
        }

        XCTAssertEqual(context.dynamicLibraryLoader.defaultSearchPaths().isEmpty, false)
        XCTAssertThrowsError(try context.dynamicLibraryLoader.openLibrary(at: scratchPath))
        context.log(.info, "win32 app start")
    }

    func stop(context: RuntimeContext) throws {
        events.append("stop")
    }
}

final class RuntimeWin32Tests: XCTestCase {
    func testWin32ProcessServicePublishesEnvironmentAndPid() {
        let process = Win32ProcessService(environment: ["FOO": "BAR"])

        XCTAssertEqual(process.environment["FOO"], "BAR")
        XCTAssertGreaterThan(process.processIdentifier, 0)
    }

    func testWin32ClockServiceReturnsANonFutureDate() {
        let clock = Win32ClockService()

        XCTAssertLessThanOrEqual(clock.now().timeIntervalSinceNow, 0.1)
    }

    func testWin32RuntimeBootRunAndShutdown() throws {
        let module = Win32RecordingModule()
        let registry = try AppModuleRegistry(descriptors: [
            AppModuleDescriptor(
                identifier: module.identifier,
                displayName: "Win32 Recording",
                makeModule: { module }
            )
        ])
        let runtime = Win32EmulatorRuntime(registry: registry, output: { _ in })
        let workingDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .path

        try runtime.boot(configuration: BootConfiguration(
            appModule: module.identifier,
            workingDirectory: workingDirectory,
            logLevel: .debug
        ))
        try runtime.run()
        try runtime.shutdown()

        XCTAssertEqual(runtime.state, .shutdown)
        XCTAssertEqual(module.events, ["start", "mutex", "stop"])
    }
}
