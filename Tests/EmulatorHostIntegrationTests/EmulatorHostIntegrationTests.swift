import Foundation
import XCTest

private struct HostProcessResult {
    let exitCode: Int32
    let output: String
}

final class EmulatorHostIntegrationTests: XCTestCase {
    func testBluetoothCheckMockPasses() throws {
        #if os(Windows)
        let executable = try XCTUnwrap(resolveHostExecutable(), "Could not locate EmulatorHost.exe in the debug build output.")
        let result = try runHostProcess(
            executable: executable,
            arguments: ["bluetooth-check", "--backend", "mock"],
            environmentOverrides: [:],
            timeout: 60
        )

        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertTrue(result.output.contains("bluetooth success"), result.output)
        #else
        throw XCTSkip("Bluetooth integration runs only on Windows in this suite.")
        #endif
    }

    func testExternalAppValidatePasses() throws {
        #if os(Windows)
        let executable = try XCTUnwrap(resolveHostExecutable(), "Could not locate EmulatorHost.exe in the debug build output.")
        let result = try runHostProcess(
            executable: executable,
            arguments: ["app", "validate", "--package-path", "Examples/StarterTelemetryApp"],
            environmentOverrides: [:],
            timeout: 120
        )

        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertTrue(result.output.contains("app validate: PASS"), result.output)
        XCTAssertTrue(result.output.contains("capabilities:"), result.output)
        #else
        throw XCTSkip("External app integration runs only on Windows in this suite.")
        #endif
    }

    func testExternalAppTextRunRendersOutputAndPersistsLaunchCount() throws {
        #if os(Windows)
        let executable = try XCTUnwrap(resolveHostExecutable(), "Could not locate EmulatorHost.exe in the debug build output.")
        let storageRoot = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: storageRoot) }

        let firstResult = try runHostProcess(
            executable: executable,
            arguments: ["app", "run", "--package-path", "Examples/StarterTelemetryApp", "--renderer", "text"],
            environmentOverrides: ["EMULATOR_APP_DATA_ROOT": storageRoot],
            timeout: 120
        )
        let secondResult = try runHostProcess(
            executable: executable,
            arguments: ["app", "run", "--package-path", "Examples/StarterTelemetryApp", "--renderer", "text"],
            environmentOverrides: ["EMULATOR_APP_DATA_ROOT": storageRoot],
            timeout: 120
        )

        XCTAssertEqual(firstResult.exitCode, 0, firstResult.output)
        XCTAssertEqual(secondResult.exitCode, 0, secondResult.output)
        XCTAssertTrue(firstResult.output.contains("Starter Telemetry"), firstResult.output)
        XCTAssertTrue(firstResult.output.contains("[image: telemetry-banner]"), firstResult.output)
        XCTAssertTrue(firstResult.output.contains("Launch count: 1"), firstResult.output)
        XCTAssertTrue(secondResult.output.contains("Launch count: 2"), secondResult.output)
        #else
        throw XCTSkip("External app integration runs only on Windows in this suite.")
        #endif
    }

    func testExternalAppWin32RunAutoCloses() throws {
        #if os(Windows)
        let executable = try XCTUnwrap(resolveHostExecutable(), "Could not locate EmulatorHost.exe in the debug build output.")
        let result = try runHostProcess(
            executable: executable,
            arguments: ["app", "run", "--package-path", "Examples/StarterTelemetryApp", "--renderer", "win32", "--autoclose-ms", "1500"],
            environmentOverrides: [:],
            timeout: 120
        )

        XCTAssertEqual(result.exitCode, 0, result.output)
        #else
        throw XCTSkip("External app integration runs only on Windows in this suite.")
        #endif
    }

    func testBluetoothExternalAppValidatePassesWithMockBackend() throws {
        #if os(Windows)
        let executable = try XCTUnwrap(resolveHostExecutable(), "Could not locate EmulatorHost.exe in the debug build output.")
        let result = try runHostProcess(
            executable: executable,
            arguments: [
                "app",
                "validate",
                "--package-path", "Examples/BluetoothTelemetryApp",
                "--bluetooth-backend", "mock",
            ],
            environmentOverrides: [:],
            timeout: 120
        )

        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertTrue(result.output.contains("app validate: PASS"), result.output)
        #else
        throw XCTSkip("External app integration runs only on Windows in this suite.")
        #endif
    }

    func testBluetoothExternalAppTextRunRendersPacketState() throws {
        #if os(Windows)
        let executable = try XCTUnwrap(resolveHostExecutable(), "Could not locate EmulatorHost.exe in the debug build output.")
        let result = try runHostProcess(
            executable: executable,
            arguments: [
                "app",
                "run",
                "--package-path", "Examples/BluetoothTelemetryApp",
                "--renderer", "text",
                "--bluetooth-backend", "mock",
            ],
            environmentOverrides: [:],
            timeout: 120
        )

        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertTrue(result.output.contains("Bluetooth Telemetry"), result.output)
        XCTAssertTrue(result.output.contains("Packets"), result.output)
        XCTAssertTrue(result.output.contains("speed=128;lap=1"), result.output)
        #else
        throw XCTSkip("External app integration runs only on Windows in this suite.")
        #endif
    }

    func testBluetoothExternalAppWin32RunAutoClosesWithMockBackend() throws {
        #if os(Windows)
        let executable = try XCTUnwrap(resolveHostExecutable(), "Could not locate EmulatorHost.exe in the debug build output.")
        let result = try runHostProcess(
            executable: executable,
            arguments: [
                "app",
                "run",
                "--package-path", "Examples/BluetoothTelemetryApp",
                "--renderer", "win32",
                "--autoclose-ms", "2000",
                "--bluetooth-backend", "mock",
            ],
            environmentOverrides: [:],
            timeout: 120
        )

        XCTAssertEqual(result.exitCode, 0, result.output)
        #else
        throw XCTSkip("External app integration runs only on Windows in this suite.")
        #endif
    }

    func testUIDemoValidationPasses() throws {
        #if os(Windows)
        let swiftExecutable = try XCTUnwrap(resolveSwiftExecutable(), "Could not locate swift.exe on PATH for ui-demo validation.")
        let result = try runHostProcess(
            executable: swiftExecutable,
            arguments: ["run", "EmulatorHost", "ui-demo"],
            environmentOverrides: [
                "EMULATOR_UI_DEMO_VALIDATE": "1",
                "EMULATOR_UI_DEMO_AUTOCLOSE_MS": "1500",
            ],
            timeout: 90
        )

        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertTrue(result.output.contains("ui-demo validation: PASS"), result.output)
        #else
        throw XCTSkip("Native ui-demo validation runs only on Windows.")
        #endif
    }

    func testDeviceShowcaseValidatePasses() throws {
        #if os(Windows)
        let executable = try XCTUnwrap(resolveHostExecutable(), "Could not locate EmulatorHost.exe in the debug build output.")
        let result = try runHostProcess(
            executable: executable,
            arguments: ["app", "validate", "--package-path", "Examples/DeviceShowcaseApp"],
            environmentOverrides: [:],
            timeout: 120
        )

        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertTrue(result.output.contains("app validate: PASS"), result.output)
        #else
        throw XCTSkip("External app integration runs only on Windows in this suite.")
        #endif
    }

    func testDeviceShowcaseTextRunResolvesDeviceEnvironment() throws {
        #if os(Windows)
        let executable = try XCTUnwrap(resolveHostExecutable(), "Could not locate EmulatorHost.exe in the debug build output.")
        let result = try runHostProcess(
            executable: executable,
            arguments: [
                "app",
                "run",
                "--package-path", "Examples/DeviceShowcaseApp",
                "--renderer", "text",
                "--device-preset", "tablet",
                "--orientation", "landscape",
                "--rotate-after-ms", "1",
            ],
            environmentOverrides: [:],
            timeout: 120
        )

        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertTrue(result.output.contains("Device Showcase"), result.output)
        XCTAssertTrue(result.output.contains("Viewport"), result.output)
        #else
        throw XCTSkip("External app integration runs only on Windows in this suite.")
        #endif
    }

    func testDeviceShowcaseWin32RunSupportsLifecycleAndRotationSimulation() throws {
        #if os(Windows)
        let executable = try XCTUnwrap(resolveHostExecutable(), "Could not locate EmulatorHost.exe in the debug build output.")
        let result = try runHostProcess(
            executable: executable,
            arguments: [
                "app",
                "run",
                "--package-path", "Examples/DeviceShowcaseApp",
                "--renderer", "win32",
                "--autoclose-ms", "2000",
                "--background-after-ms", "500",
                "--resume-after-ms", "900",
                "--rotate-after-ms", "1200",
            ],
            environmentOverrides: [:],
            timeout: 120
        )

        XCTAssertEqual(result.exitCode, 0, result.output)
        #else
        throw XCTSkip("External app integration runs only on Windows in this suite.")
        #endif
    }

    func testInputPlaygroundValidatePasses() throws {
        #if os(Windows)
        let executable = try XCTUnwrap(resolveHostExecutable(), "Could not locate EmulatorHost.exe in the debug build output.")
        let result = try runHostProcess(
            executable: executable,
            arguments: ["app", "validate", "--package-path", "Examples/InputPlaygroundApp"],
            environmentOverrides: [:],
            timeout: 120
        )

        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertTrue(result.output.contains("app validate: PASS"), result.output)
        #else
        throw XCTSkip("External app integration runs only on Windows in this suite.")
        #endif
    }

    func testInputPlaygroundTextRunRendersInputAndGestureState() throws {
        #if os(Windows)
        let executable = try XCTUnwrap(resolveHostExecutable(), "Could not locate EmulatorHost.exe in the debug build output.")
        let result = try runHostProcess(
            executable: executable,
            arguments: [
                "app",
                "run",
                "--package-path", "Examples/InputPlaygroundApp",
                "--renderer", "text",
            ],
            environmentOverrides: [:],
            timeout: 120
        )

        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertTrue(result.output.contains("Input Playground"), result.output)
        XCTAssertTrue(result.output.contains("Gesture surface"), result.output)
        #else
        throw XCTSkip("External app integration runs only on Windows in this suite.")
        #endif
    }

    func testExternalAppInspectTextProducesSummary() throws {
        #if os(Windows)
        let executable = try XCTUnwrap(resolveHostExecutable(), "Could not locate EmulatorHost.exe in the debug build output.")
        let result = try runHostProcess(
            executable: executable,
            arguments: [
                "app",
                "inspect",
                "--package-path", "Examples/DeviceShowcaseApp",
                "--renderer", "text",
            ],
            environmentOverrides: [:],
            timeout: 120
        )

        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertTrue(result.output.contains("inspect: Device Showcase"), result.output)
        XCTAssertTrue(result.output.contains("counts: nodes="), result.output)
        #else
        throw XCTSkip("External app inspection runs only on Windows in this suite.")
        #endif
    }

    func testExternalAppInspectWin32JSONProducesStructuredOutput() throws {
        #if os(Windows)
        let executable = try XCTUnwrap(resolveHostExecutable(), "Could not locate EmulatorHost.exe in the debug build output.")
        let result = try runHostProcess(
            executable: executable,
            arguments: [
                "app",
                "inspect",
                "--package-path", "Examples/StarterTelemetryApp",
                "--renderer", "win32",
                "--format", "json",
            ],
            environmentOverrides: [:],
            timeout: 120
        )

        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertTrue(result.output.contains("\"appID\""), result.output)
        XCTAssertTrue(result.output.contains("\"viewTree\""), result.output)
        XCTAssertTrue(result.output.contains("\"interactions\""), result.output)
        #else
        throw XCTSkip("External app inspection runs only on Windows in this suite.")
        #endif
    }

    func testExternalAppTraceCapturesLifecycleAndRendererEvents() throws {
        #if os(Windows)
        let executable = try XCTUnwrap(resolveHostExecutable(), "Could not locate EmulatorHost.exe in the debug build output.")
        let result = try runHostProcess(
            executable: executable,
            arguments: [
                "app",
                "trace",
                "--package-path", "Examples/DeviceShowcaseApp",
                "--renderer", "win32",
                "--autoclose-ms", "1500",
                "--background-after-ms", "500",
                "--resume-after-ms", "900",
                "--rotate-after-ms", "1200",
            ],
            environmentOverrides: [:],
            timeout: 120
        )

        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertTrue(result.output.contains("lifecycle.didLaunch"), result.output)
        XCTAssertTrue(result.output.contains("renderer.frameGenerated"), result.output)
        XCTAssertTrue(result.output.contains("focus.changed"), result.output)
        XCTAssertTrue(result.output.contains("action.dispatched"), result.output)
        #else
        throw XCTSkip("External app trace runs only on Windows in this suite.")
        #endif
    }

    func testExternalAppCompatCheckReportsBluetoothRendererState() throws {
        #if os(Windows)
        let executable = try XCTUnwrap(resolveHostExecutable(), "Could not locate EmulatorHost.exe in the debug build output.")
        let result = try runHostProcess(
            executable: executable,
            arguments: [
                "app",
                "compat-check",
                "--package-path", "Examples/BluetoothTelemetryApp",
                "--bluetooth-backend", "mock",
            ],
            environmentOverrides: [:],
            timeout: 120
        )

        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertTrue(result.output.contains("compat-check: Bluetooth Telemetry"), result.output)
        XCTAssertTrue(result.output.contains("capability.degraded"), result.output)
        #else
        throw XCTSkip("External app compatibility checks run only on Windows in this suite.")
        #endif
    }

    private func resolveHostExecutable() -> String? {
        let buildRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build")
        guard FileManager.default.fileExists(atPath: buildRoot.path) else {
            return nil
        }

        let enumerator = FileManager.default.enumerator(atPath: buildRoot.path)
        while let entry = enumerator?.nextObject() as? String {
            let url = buildRoot.appendingPathComponent(entry)
            if url.lastPathComponent.caseInsensitiveCompare("EmulatorHost.exe") == .orderedSame {
                return url.path
            }
        }

        return nil
    }

    private func resolveSwiftExecutable() -> String? {
        let environment = ProcessInfo.processInfo.environment
        let pathKey = environment.keys.first(where: { $0.caseInsensitiveCompare("PATH") == .orderedSame }) ?? "PATH"
        let pathEntries = (environment[pathKey] ?? "")
            .split(separator: ";")
            .map(String.init)

        for entry in pathEntries where !entry.isEmpty {
            let candidate = URL(fileURLWithPath: entry).appendingPathComponent("swift.exe").path
            if FileManager.default.isExecutableFile(atPath: candidate) || FileManager.default.fileExists(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }

    private func runHostProcess(
        executable: String,
        arguments: [String],
        environmentOverrides: [String: String],
        timeout: TimeInterval
    ) throws -> HostProcessResult {
        let process = Process()
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("emulator-host-integration-\(UUID().uuidString).log")
        _ = FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let outputHandle = try FileHandle(forWritingTo: outputURL)

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = outputHandle
        process.standardError = outputHandle
        process.environment = ProcessInfo.processInfo.environment.merging(environmentOverrides) { _, override in
            override
        }

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
            XCTFail("Timed out waiting for EmulatorHost ui-demo validation run to complete.")
        }

        try outputHandle.close()
        let combinedData = try Data(contentsOf: outputURL)
        try? FileManager.default.removeItem(at: outputURL)

        return HostProcessResult(
            exitCode: process.terminationStatus,
            output: String(decoding: combinedData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func makeTemporaryDirectory() throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("emulator-host-integration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        return url.path
    }
}
