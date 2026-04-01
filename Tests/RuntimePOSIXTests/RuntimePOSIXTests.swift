import Foundation
import XCTest
@testable import RuntimeCore
@testable import RuntimePOSIX

private final class LogCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    func append(_ entry: String) {
        lock.lock()
        storage.append(entry)
        lock.unlock()
    }

    var entries: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

private final class RecordingAppModule: AppModule, @unchecked Sendable {
    let identifier = "recording-app"
    private(set) var events: [String] = []

    func start(context: RuntimeContext) throws {
        events.append("start")
        context.log(.info, "recording app start")
    }

    func stop(context: RuntimeContext) throws {
        events.append("stop")
        context.log(.info, "recording app stop")
    }
}

final class RuntimePOSIXTests: XCTestCase {
    func testRuntimeBootRunAndShutdownFollowExpectedLifecycle() throws {
        let module = RecordingAppModule()
        let logs = LogCollector()
        let registry = try AppModuleRegistry(descriptors: [
            AppModuleDescriptor(
                identifier: module.identifier,
                displayName: "Recording App",
                makeModule: { module }
            )
        ])
        let runtime = POSIXEmulatorRuntime(registry: registry, output: { logs.append($0) })
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
        XCTAssertEqual(module.events, ["start", "stop"])
        XCTAssertTrue(logs.entries.contains(where: { $0.contains("boot complete") }))
        XCTAssertTrue(logs.entries.contains(where: { $0.contains("shutdown complete") }))
    }

    func testBootFailsWhenModuleIsMissing() {
        let runtime = POSIXEmulatorRuntime(registry: try! AppModuleRegistry(descriptors: []))

        XCTAssertThrowsError(try runtime.boot(configuration: BootConfiguration(appModule: "missing"))) { error in
            XCTAssertEqual(error as? RuntimeError, RuntimeError.appModuleNotFound("missing"))
        }
    }
}
