import EmulatorAppSDK
import EmulatorDiagnostics
import Foundation
import RendererCore
import XCTest

final class EmulatorDiagnosticsTests: XCTestCase {
    func testInspectionSnapshotCapturesInteractionsAndWarnings() throws {
        let document = ScreenDocument(
            title: "Diagnostics",
            root: .vStack(
                StackNode(
                    children: [
                        .button(ButtonNode(title: "Open", action: "action.open")),
                        .image(
                            ImageNode(
                                asset: RasterImageAsset(
                                    name: "missing-banner",
                                    filePath: #"C:\definitely-missing.png"#
                                ),
                                width: 120,
                                height: 48
                            )
                        ),
                    ],
                    spacing: 8
                )
            )
        )
        let manifest = EmulatorAppManifest(appID: "test.app", displayName: "Test App")
        let environment = manifest.resolvedRenderEnvironment(rendererMode: .text)
        let output = RenderPipeline.makeDisplayList(for: document, in: environment.device.viewport, focusedAction: "action.open")

        let snapshot = EmulatorInspectionBuilder.makeSnapshot(
            manifest: manifest,
            environment: environment,
            document: document,
            output: output,
            focusedAction: "action.open"
        )

        XCTAssertEqual(snapshot.focusedAction, "action.open")
        XCTAssertEqual(snapshot.actionCount, 1)
        XCTAssertTrue(snapshot.interactions.contains(where: { $0.action == "action.open" && $0.isFocused }))
        XCTAssertTrue(snapshot.warnings.contains(where: { $0.contains("image asset missing") }))
    }

    func testTraceRecorderIncludesBufferedDiagnostics() {
        let counter = TimestampCounter()
        let recorder = EmulatorTraceRecorder(timeProvider: {
            counter.next()
        })
        let diagnostics = BufferedDiagnosticsService()

        recorder.record(category: "runner", name: "start")
        diagnostics.mark("app.ready", metadata: ["state": "warm"])
        diagnostics.recordWarning("layout clipped", metadata: ["view": "hero"])
        recorder.recordAppDiagnostics(diagnostics.snapshot())

        let events = recorder.snapshot()

        XCTAssertEqual(events.first?.category, "runner")
        XCTAssertTrue(events.contains(where: { $0.category == "mark" && $0.name == "app.ready" }))
        XCTAssertTrue(events.contains(where: { $0.category == "warning" && $0.name == "layout clipped" }))
    }

    func testCompatibilityAnalyzerFlagsDegradedCapabilityAndLocaleFallback() throws {
        let packageRoot = try makeTemporaryPackageRoot()
        defer { try? FileManager.default.removeItem(atPath: packageRoot) }

        let stringsRoot = URL(fileURLWithPath: packageRoot).appendingPathComponent("Strings")
        try FileManager.default.createDirectory(at: stringsRoot, withIntermediateDirectories: true)
        try #"{"hello":"Hello"}"#.write(
            to: stringsRoot.appendingPathComponent("en.json"),
            atomically: true,
            encoding: .utf8
        )

        let manifest = EmulatorAppManifest(
            appID: "compat.app",
            displayName: "Compat App",
            supportedRenderers: [.text],
            requiredCapabilities: [.clipboard],
            preferredLocales: ["fr"]
        )

        let report = EmulatorCompatibilityAnalyzer.makeReport(
            inputs: [
                EmulatorRendererCompatibilityInput(
                    rendererMode: .text,
                    manifest: manifest,
                    packageRootPath: packageRoot,
                    capabilityStatuses: [
                        EmulatorCapabilityStatus(
                            capability: .clipboard,
                            availability: .degraded,
                            message: "Clipboard is stubbed in text renderer mode."
                        )
                    ],
                    inspectionSnapshot: nil,
                    output: nil
                )
            ]
        )

        XCTAssertFalse(report.hasErrors)
        XCTAssertTrue(report.issues.contains(where: { $0.code == "capability.degraded" }))
        XCTAssertTrue(report.issues.contains(where: { $0.code == "locale.fallback" }))
    }

    private func makeTemporaryPackageRoot() throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("emulator-diagnostics-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.path
    }
}

private final class TimestampCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64 = 100

    func next() -> UInt64 {
        lock.lock()
        defer {
            value += 10
            lock.unlock()
        }
        return value
    }
}
