import XCTest
@testable import RuntimeObjCExperiment

final class RuntimeObjCExperimentTests: XCTestCase {
    private let supportedBackends: Set<String> = [
        "embedded-c-bridge",
        "libobjc2-dynamic",
    ]

    func testRuntimeInitializesAndReportsBackend() throws {
        let runtime = RuntimeObjCExperiment()
        let backend = try runtime.initializeRuntime()

        XCTAssertTrue(supportedBackends.contains(backend))
    }

    func testSelectorClassAllocationAndMessageSendWorkThroughBridge() throws {
        let runtime = RuntimeObjCExperiment()

        _ = try runtime.initializeRuntime()
        try runtime.registerSampleClass(
            named: "TelemetryBridge",
            selector: "statusLine",
            response: "bridge ready"
        )

        let instance = try runtime.allocateInstance(ofClassNamed: "TelemetryBridge")
        defer {
            try? runtime.releaseInstance(instance)
        }

        XCTAssertEqual(try runtime.sendZeroArgumentMessage("statusLine", to: instance), "bridge ready")
    }

    func testRetainAndReleaseLifecycleIsExplicit() throws {
        let runtime = RuntimeObjCExperiment()

        _ = try runtime.initializeRuntime()
        try runtime.registerSampleClass(named: "ManagedObject", selector: "describe", response: "ok")

        let instance = try runtime.allocateInstance(ofClassNamed: "ManagedObject")
        try runtime.retainInstance(instance)
        try runtime.releaseInstance(instance)

        XCTAssertEqual(try runtime.sendZeroArgumentMessage("describe", to: instance), "ok")

        try runtime.releaseInstance(instance)

        XCTAssertThrowsError(try runtime.sendZeroArgumentMessage("describe", to: instance)) { error in
            XCTAssertEqual(error as? ObjCExperimentError, .instanceNotFound)
        }
    }

    func testSelfCheckProducesExpectedReport() throws {
        let report = try RuntimeObjCExperiment().runSelfCheck()

        XCTAssertTrue(supportedBackends.contains(report.backend))
        XCTAssertEqual(report.className, "SmokeObject")
        XCTAssertEqual(report.selector, "displayName")
        XCTAssertEqual(report.response, "objc experiment ready")
    }

    func testEmbeddedBackendSelfCheckProducesExpectedReport() throws {
        let report = try RuntimeObjCExperiment(preferredBackend: .embedded).runSelfCheck()

        XCTAssertTrue(supportedBackends.contains(report.backend))
        XCTAssertEqual(report.response, "objc experiment ready")
    }

    func testCompatibilityCheckProducesExpectedDetails() throws {
        let report = try RuntimeObjCExperiment().runCompatibilityCheck()

        XCTAssertTrue(supportedBackends.contains(report.backend))
        XCTAssertEqual(report.className, "CompatDerivedObject")
        XCTAssertEqual(report.selector, "displayName")
        XCTAssertEqual(report.response, "compat child")
        XCTAssertTrue(report.classLookupSucceeded)
        XCTAssertTrue(report.respondsToSelector)
        XCTAssertEqual(report.instanceClassName, "CompatDerivedObject")
        XCTAssertEqual(report.integerValue, 42)
        XCTAssertEqual(report.echoedValue, "compat")
        XCTAssertTrue(report.autoreleasePoolRoundTrip)
    }
}
