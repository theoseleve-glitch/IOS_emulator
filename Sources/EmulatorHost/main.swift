#if os(Windows)
import WinSDK
#elseif os(Linux)
import Glibc
#else
import Darwin
#endif

import Foundation
import EmulatorAppSDK
import EmulatorOnboarding
import RendererCore
import RendererText
import RendererWin32
import RuntimeCore
import RuntimeFFI
import RuntimeObjCExperiment
import RuntimePOSIX
import RuntimeWin32
import SmokeApp

private struct ProcessResult {
    let exitCode: Int32
    let output: String
}

enum HostCommandError: Error, CustomStringConvertible {
    case usage
    case doctorFailed([String])
    case ffiCheckFailed(String)
    case objcCheckFailed(String)
    case uiDemoFailed(String)
    case bluetoothCheckFailed(String)
    case appCommandFailed(String)

    var description: String {
        switch self {
        case .usage:
            return "Usage: swift run EmulatorHost <doctor [--expected-arch <x64|arm64>]|smoke|ffi-check|objc-check|ui-demo [--device-preset <phoneCompact|phoneTall|tablet>] [--orientation <portrait|landscape>] [--autoclose-ms <n>] [--background-after-ms <n>] [--resume-after-ms <n>] [--rotate-after-ms <n>]|bluetooth-check|app ...>"
        case .doctorFailed(let failures):
            return failures.joined(separator: "\n")
        case .ffiCheckFailed(let message):
            return message
        case .objcCheckFailed(let message):
            return message
        case .uiDemoFailed(let message):
            return message
        case .bluetoothCheckFailed(let message):
            return message
        case .appCommandFailed(let message):
            return message
        }
    }
}

struct EmulatorHostMain {
    static func run() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())

        guard !arguments.isEmpty else {
            throw HostCommandError.usage
        }

        switch arguments[0] {
        case "doctor":
            try runDoctor(arguments: Array(arguments.dropFirst()))
        case "smoke":
            guard arguments.count == 1 else { throw HostCommandError.usage }
            try runSmoke()
        case "ffi-check":
            guard arguments.count == 1 else { throw HostCommandError.usage }
            try runFFICheck(printCallback: true)
        case "objc-check":
            try runObjCCheck(arguments: Array(arguments.dropFirst()))
        case "ui-demo":
            try runUIDemo(arguments: Array(arguments.dropFirst()))
        case "bluetooth-check":
            try runBluetoothCheck(arguments: Array(arguments.dropFirst()))
        case "app":
            try ExternalAppCommandRunner.run(arguments: Array(arguments.dropFirst()), foundationPackagePath: FileManager.default.currentDirectoryPath)
        default:
            throw HostCommandError.usage
        }
    }

    private static func runDoctor(arguments: [String]) throws {
        let expectedArchitecture = try parseExpectedArchitecture(arguments)
        var failures: [String] = []
        let fileManager = FileManager.default
        let registry = try Phase1Registry.make()
        let doctorScratchPath = fileManager.temporaryDirectory
            .appendingPathComponent("emulator-host-doctor-\(UUID().uuidString)")
            .path

        #if os(Windows)
        print("PASS: host OS is Windows")
        let hostArchitecture = currentWindowsArchitecture()
        print("PASS: host architecture is \(hostArchitecture)")
        if let expectedArchitecture, hostArchitecture != expectedArchitecture {
            failures.append("FAIL: expected host architecture \(expectedArchitecture) but found \(hostArchitecture).")
        }

        if isDeveloperModeEnabled() {
            print("PASS: Developer Mode is enabled")
        } else {
            failures.append("FAIL: Developer Mode is disabled. Enable it in Settings > For developers before building the Windows Swift toolchain stack.")
        }

        let registeredModules = registry.registeredModules
            .map { "\($0.identifier) (\($0.displayName))" }
            .joined(separator: ", ")
        print("PASS: registered app modules: \(registeredModules)")

        for requiredPath in ["Package.swift", "scripts/bootstrap-windows.ps1", "scripts/env-windows.ps1"] {
            if fileManager.fileExists(atPath: requiredPath) {
                print("PASS: found \(requiredPath)")
            } else {
                failures.append("FAIL: missing \(requiredPath)")
            }
        }

        let visualStudioPath = resolveVisualStudioInstallPath()
        if let visualStudioPath {
            print("PASS: Visual Studio Build Tools at \(visualStudioPath)")
        } else {
            failures.append("FAIL: Visual Studio Build Tools were not detected via vswhere.")
        }

        let x64CompilerPath = visualStudioPath.flatMap(resolveMSVCX64CompilerPath(installPath:))
        if let x64CompilerPath {
            print("PASS: x64 MSVC compiler at \(x64CompilerPath)")
        } else {
            failures.append("FAIL: x64 MSVC compiler tools are missing.")
        }

        let arm64CompilerPath = visualStudioPath.flatMap(resolveMSVCARM64CompilerPath(installPath:))
        if let arm64CompilerPath {
            print("PASS: ARM64 MSVC compiler at \(arm64CompilerPath)")
        } else {
            failures.append("FAIL: ARM64 MSVC compiler tools are missing.")
        }

        let msbuildPath = visualStudioPath.flatMap(resolveMSBuildPath(installPath:))
        if let msbuildPath {
            print("PASS: MSBuild at \(msbuildPath)")
        } else {
            failures.append("FAIL: MSBuild.exe is missing from the Visual Studio Build Tools installation.")
        }

        if let sdkPath = resolveWindows11SDKPath(minimumBuild: 22000) {
            print("PASS: Windows 11 SDK >= 22000 at \(sdkPath)")
        } else {
            failures.append("FAIL: Windows 11 SDK 22000 or newer was not found.")
        }

        let swiftPath = resolveExecutable(
            named: "swift.exe",
            fallbackCandidates: windowsToolCandidates(for: "swift")
        )
        if let swiftPath {
            print("PASS: swift at \(swiftPath)")
            let swiftVersionResult = try runWindowsProcess(swiftPath, ["--version"], timeout: 30)
            if swiftVersionResult.exitCode == 0 {
                let versionLine = swiftVersionResult.output.split(separator: "\n").first.map(String.init) ?? swiftVersionResult.output
                print("PASS: \(versionLine)")
            } else {
                failures.append("FAIL: swift --version failed: \(summarizeDiagnosticOutput(swiftVersionResult.output))")
            }

            let dumpPackageResult = try runWindowsProcess(swiftPath, ["package", "dump-package"], timeout: 120)
            if dumpPackageResult.exitCode == 0 {
                print("PASS: swift package dump-package")
            } else {
                failures.append("FAIL: swift package dump-package failed: \(summarizeDiagnosticOutput(dumpPackageResult.output))")
            }

            let buildResult = try runWindowsProcess(
                swiftPath,
                ["build", "--product", "EmulatorHost", "--scratch-path", doctorScratchPath],
                timeout: 180
            )
            if buildResult.exitCode == 0 {
                print("PASS: swift build --product EmulatorHost")
            } else {
                failures.append("FAIL: swift build --product EmulatorHost failed: \(summarizeDiagnosticOutput(buildResult.output))")
            }
        } else {
            failures.append("FAIL: swift.exe was not found. Run .\\scripts\\bootstrap-windows.ps1 and then dot-source .\\scripts\\env-windows.ps1.")
        }

        for tool in [
            ("cmake.exe", windowsToolCandidates(for: "cmake")),
            ("clang.exe", windowsToolCandidates(for: "clang")),
            ("nasm.exe", windowsToolCandidates(for: "nasm")),
            ("python.exe", windowsToolCandidates(for: "python")),
        ] {
            if let resolved = resolveExecutable(named: tool.0, fallbackCandidates: tool.1) {
                print("PASS: \(tool.0) at \(resolved)")
            } else {
                failures.append("FAIL: \(tool.0) is missing from the native Windows toolchain.")
            }
        }
        #else
        failures.append("FAIL: doctor now targets a native Windows host. This build is running on a non-Windows platform.")
        #endif

        guard failures.isEmpty else {
            throw HostCommandError.doctorFailed(failures)
        }

        print("Doctor OK")
    }

    private static func runSmoke() throws {
        let registry = try Phase1Registry.make()
        let runtime = makeRuntime(registry: registry)
        let baseDirectory = FileManager.default.currentDirectoryPath
        let workingDirectory: String

        #if os(Windows)
        workingDirectory = URL(fileURLWithPath: baseDirectory)
            .appendingPathComponent(".runtime-workdir")
            .path
        print("runtime: win32")
        #else
        workingDirectory = URL(fileURLWithPath: baseDirectory)
            .appendingPathComponent(".runtime-workdir")
            .path
        print("runtime: posix")
        #endif

        let configuration = BootConfiguration(
            appModule: SmokeAppModule.moduleIdentifier,
            workingDirectory: workingDirectory,
            logLevel: .debug
        )

        try runtime.boot(configuration: configuration)
        try runtime.run()
        let previewModule = SmokeAppModule()
        print(TerminalRenderer().render(previewModule.makeDashboardDocument(), in: .terminalPhone))
        try runFFICheck(printCallback: true)
        try runtime.shutdown()
    }

    private static func runFFICheck(printCallback: Bool) throws {
        let bridge = FFIHostBridge()
        let expectedMessage = "ffi ping"
        let expectedRoundTrip = "ffi hello from host"
        let expectedBytes: [UInt8] = [0, 1, 2, 7, 42, 255]
        var callbackMessages: [String] = []

        bridge.registerCallback { message in
            callbackMessages.append(message)
            if printCallback {
                print("ffi callback: \(message)")
            }
        }

        let roundTripResult = try bridge.roundTrip(expectedRoundTrip)
        guard roundTripResult == expectedRoundTrip else {
            throw HostCommandError.ffiCheckFailed("FFI round-trip mismatch")
        }

        let roundTripBytes = try bridge.roundTrip(expectedBytes)
        guard roundTripBytes == expectedBytes else {
            throw HostCommandError.ffiCheckFailed("FFI byte round-trip mismatch")
        }

        bridge.emit(expectedMessage)

        guard callbackMessages == [expectedMessage] else {
            throw HostCommandError.ffiCheckFailed("FFI callback did not fire as expected")
        }

        bridge.clearCallback()
        print("ffi success")
    }

    private static func runObjCCheck(arguments: [String]) throws {
        let options = try parseObjCCheckOptions(arguments)
        let experiment = RuntimeObjCExperiment(preferredBackend: options.backend)

        switch options.suite {
        case "basic":
            let report = try experiment.runSelfCheck()
            guard report.response == "objc experiment ready" else {
                throw HostCommandError.objcCheckFailed("Objective-C experiment returned an unexpected payload.")
            }
            print("objc backend: \(report.backend)")
            print("objc success: \(report.className).\(report.selector) -> \(report.response)")
        case "compat":
            let report = try experiment.runCompatibilityCheck(requireLibobjc2: options.backend == .libobjc2)
            print("objc backend: \(report.backend)")
            print("objc compat: \(report.className).\(report.selector) -> \(report.response)")
            print("objc compat details: lookup=\(report.classLookupSucceeded) responds=\(report.respondsToSelector) class=\(report.instanceClassName) int=\(report.integerValue) echo=\(report.echoedValue) autorelease=\(report.autoreleasePoolRoundTrip)")
        default:
            throw HostCommandError.usage
        }
    }

    private static func runUIDemo(arguments: [String]) throws {
        #if os(Windows)
        let state = SmokeDemoState()
        let environment = ProcessInfo.processInfo.environment
        let options = try parseUIDemoOptions(arguments)
        let validationEnabled = environment["EMULATOR_UI_DEMO_VALIDATE"] == "1"
        let autoClose = environment["EMULATOR_UI_DEMO_AUTOCLOSE_MS"]
            .flatMap(Int32.init) ?? options.autoCloseMilliseconds ?? (validationEnabled ? 3400 : 0)
        let invalidation = BufferedUIInvalidationService()
        let manifest = EmulatorAppManifest(
            appID: "host.ui-demo",
            displayName: "lap_mobile ui demo",
            defaultViewport: .graphicalPhone,
            defaultDevicePreset: .phoneTall,
            defaultOrientation: .portrait,
            supportedRenderers: [.win32]
        )
        let environmentState = EmulatorRenderEnvironmentState(
            manifest: manifest,
            rendererMode: .win32,
            devicePresetOverride: options.devicePreset,
            orientationOverride: options.orientation
        )
        let initialEnvironment = environmentState.snapshot()
        EmulatorLifecycleControllerRunner.emitIfNeeded(.didLaunch, on: state)
        EmulatorLifecycleControllerRunner.emitIfNeeded(.didEnterForeground, on: state)
        let presenter = Win32ScreenPresenter(
            documentProvider: { viewport in
                let renderEnvironment = environmentState.snapshot(viewport: viewport)
                return EmulatorAppControllerBridge.makeDocument(from: state, environment: renderEnvironment)
            },
            actionHandler: { action in
                _ = state.handle(action: action)
            },
            inputHandler: { input in
                EmulatorAppControllerBridge.handleInput(input, on: state)
            },
            textInputHandler: { fieldID, event in
                EmulatorAppControllerBridge.handleTextInput(event, fieldID: fieldID, on: state)
            },
            pointerHandler: { pointer, surfaceID in
                EmulatorAppControllerBridge.handlePointer(pointer, surfaceID: surfaceID, on: state)
            },
            gestureHandler: { gesture, surfaceID in
                EmulatorAppControllerBridge.handleGesture(gesture, surfaceID: surfaceID, on: state)
            }
        )

        let report = try presenter.run(
            options: Win32WindowOptions(
                title: "lap_mobile ui demo",
                width: Int32(initialEnvironment.device.viewport.width),
                height: Int32(initialEnvironment.device.viewport.height),
                autoCloseMilliseconds: autoClose,
                scriptedAction: validationEnabled ? SmokeDemoAction.openInputLab : nil,
                scriptedActionDelayMilliseconds: validationEnabled ? 300 : 0
            ),
            onWindowReady: { handle in
                invalidation.bind {
                    handle.requestRedraw()
                }

                if validationEnabled {
                    scheduleUIDemoValidationInputs(
                        handle: handle,
                        state: state,
                        invalidation: invalidation
                    )
                    scheduleUIDemoSimulation(
                        state: state,
                        environmentState: environmentState,
                        invalidation: invalidation,
                        backgroundAfterMilliseconds: 500,
                        resumeAfterMilliseconds: 800,
                        rotateAfterMilliseconds: 1100
                    )
                } else {
                    scheduleUIDemoSimulation(
                        state: state,
                        environmentState: environmentState,
                        invalidation: invalidation,
                        backgroundAfterMilliseconds: options.backgroundAfterMilliseconds,
                        resumeAfterMilliseconds: options.resumeAfterMilliseconds,
                        rotateAfterMilliseconds: options.rotateAfterMilliseconds
                    )
                }
            }
        )
        EmulatorLifecycleControllerRunner.emitIfNeeded(.willTerminate, on: state)

        if validationEnabled {
            guard report.frameCount >= 6 else {
                throw HostCommandError.uiDemoFailed("ui-demo validation failed: expected at least 6 rendered frames, got \(report.frameCount).")
            }

            guard report.focusChangeCount >= 1 else {
                throw HostCommandError.uiDemoFailed("ui-demo validation failed: expected keyboard focus to move at least once.")
            }

            guard report.scriptedActionDispatched else {
                throw HostCommandError.uiDemoFailed("ui-demo validation failed: expected the native scripted click to dispatch the sessions action.")
            }

            guard report.textInputCount >= 3 else {
                throw HostCommandError.uiDemoFailed("ui-demo validation failed: expected text input events to be delivered.")
            }

            guard state.currentRoute == .inputLab else {
                throw HostCommandError.uiDemoFailed("ui-demo validation failed: expected the input lab route after native activation, got \(state.currentRoute).")
            }

            guard state.backgroundEventCount >= 1, state.foregroundEventCount >= 2 else {
                throw HostCommandError.uiDemoFailed("ui-demo validation failed: expected one background and one resume lifecycle event.")
            }

            guard state.rotationEventCount >= 1 else {
                throw HostCommandError.uiDemoFailed("ui-demo validation failed: expected one orientation change event.")
            }

            let currentEnvironment = environmentState.snapshot()
            let proofEnvironment = manifest.resolvedRenderEnvironment(
                rendererMode: .text,
                locale: currentEnvironment.locale,
                devicePresetOverride: currentEnvironment.device.preset,
                orientationOverride: currentEnvironment.device.orientation,
                viewportOverride: DeviceViewport(width: 64, height: 24)
            )
            let rendered = TerminalRenderer().render(
                EmulatorAppControllerBridge.makeDocument(from: state, environment: proofEnvironment),
                in: proofEnvironment.device.viewport
            )
            guard rendered.contains("Advanced input lab") else {
                let summary = rendered
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .prefix(12)
                    .joined(separator: " | ")
                throw HostCommandError.uiDemoFailed("ui-demo validation failed: expected input-lab render, route=\(state.currentRoute), preview=\(summary)")
            }

            guard state.submitCount >= 1, state.inputText.contains("GO") else {
                throw HostCommandError.uiDemoFailed("ui-demo validation failed: expected text entry plus submit.")
            }

            guard abs(state.dragOffset.x) > 1 || abs(state.dragOffset.y) > 1 else {
                throw HostCommandError.uiDemoFailed("ui-demo validation failed: expected drag offset to change.")
            }

            guard state.longPressCount >= 1 else {
                throw HostCommandError.uiDemoFailed("ui-demo validation failed: expected long press to be recorded.")
            }

            guard abs(state.pinchValue - 1.0) > 0.01 else {
                throw HostCommandError.uiDemoFailed("ui-demo validation failed: expected pinch state to change.")
            }

            guard abs(state.rotationValue) > 0.1 else {
                throw HostCommandError.uiDemoFailed("ui-demo validation failed: expected rotation state to change.")
            }

            guard report.gestureEventCount >= 1 || state.longPressCount >= 1 || abs(state.pinchValue - 1.0) > 0.01 || abs(state.rotationValue) > 0.1 else {
                throw HostCommandError.uiDemoFailed("ui-demo validation failed: expected gesture delivery proof, got gestures=\(report.gestureEventCount), longPress=\(state.longPressCount), pinch=\(state.pinchValue), rotation=\(state.rotationValue).")
            }

            print("ui-demo validation: PASS")
        }
        #else
        throw HostCommandError.uiDemoFailed("ui-demo is only available on the native Windows host.")
        #endif
    }

    private static func runBluetoothCheck(arguments: [String]) throws {
        let backend = try parseBluetoothBackend(arguments)
        let manifest = EmulatorAppManifest(
            appID: "host.bluetooth-check",
            displayName: "Bluetooth Check",
            defaultViewport: .graphicalPhone,
            supportedRenderers: [.text, .win32],
            requiredCapabilities: [.bluetooth, .logging, .clock]
        )
        let renderer: EmulatorRendererMode = backend == .mock ? .text : .win32
        let registry = EmulatorHostServiceRegistry(
            rendererMode: renderer,
            foundationRootPath: FileManager.default.currentDirectoryPath,
            environment: ProcessInfo.processInfo.environment,
            bluetoothBackendMode: backend
        )
        let report = registry.validationReport(for: manifest)
        let summaries = report.statuses
            .map { "\($0.capability.rawValue)=\($0.availability.rawValue)" }
            .joined(separator: ", ")
        if !summaries.isEmpty {
            print("capabilities: \(summaries)")
        }

        let services = try registry.makeServices(for: manifest)
        let bluetooth = services.bluetooth
        print("bluetooth backend: \(bluetooth.backendMode.rawValue)")
        print("adapter state: \(describe(bluetooth.adapterState()))")

        let scanResults = try waitForAsyncResult {
            try await bluetooth.scan(filter: EmulatorBluetoothScanFilter(), timeoutMilliseconds: bluetooth.backendMode == .mock ? 40 : 1200)
        }
        guard !scanResults.isEmpty else {
            throw HostCommandError.bluetoothCheckFailed("Bluetooth scan returned no peripherals for backend \(bluetooth.backendMode.rawValue).")
        }
        print("scan: found \(scanResults.count) device(s)")

        var lastFailure = "No usable Bluetooth peripheral passed the live validation flow."
        for peripheral in scanResults {
            do {
                print("candidate: \(peripheral.name) [\(peripheral.id.rawValue)]")
                try waitForAsyncResult {
                    try await bluetooth.connect(to: peripheral.id)
                }
                defer {
                    _ = try? waitForAsyncResult {
                        await bluetooth.disconnect(from: peripheral.id)
                    }
                }
                print("connect: PASS \(peripheral.id.rawValue)")

                let serviceUUIDs = try waitForAsyncResult {
                    try await bluetooth.discoverServices(for: peripheral.id)
                }
                guard !serviceUUIDs.isEmpty else {
                    throw HostCommandError.bluetoothCheckFailed("No GATT services were discovered for \(peripheral.name).")
                }
                print("services: \(serviceUUIDs.map(\.rawValue).joined(separator: ", "))")

                var characteristics: [EmulatorBluetoothCharacteristicID] = []
                for serviceUUID in serviceUUIDs {
                    let discovered = try waitForAsyncResult {
                        try await bluetooth.discoverCharacteristics(for: peripheral.id, serviceUUID: serviceUUID)
                    }
                    characteristics.append(contentsOf: discovered)
                }
                guard !characteristics.isEmpty else {
                    throw HostCommandError.bluetoothCheckFailed("No GATT characteristics were discovered for \(peripheral.name).")
                }
                print("characteristics: \(characteristics.map(\.characteristicUUID).joined(separator: ", "))")

                if let readable = characteristics.first(where: { $0.properties.contains(.read) }) {
                    let initialValue = try waitForAsyncResult {
                        try await bluetooth.readValue(for: readable, peripheralID: peripheral.id)
                    }
                    let rendered = initialValue.isEmpty ? "<empty>" : String(decoding: initialValue, as: UTF8.self)
                    print("read: \(rendered)")
                }

                if let writable = characteristics.first(where: { $0.properties.contains(.write) || $0.properties.contains(.writeWithoutResponse) }) {
                    try waitForAsyncResult {
                        try await bluetooth.writeValue(
                            Data("ping".utf8),
                            for: writable,
                            peripheralID: peripheral.id,
                            mode: writable.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
                        )
                    }
                    print("write: PASS \(writable.characteristicUUID)")
                }

                if let notifying = characteristics.first(where: { $0.properties.contains(.notify) }) {
                    do {
                        let firstNotification = try waitForAsyncResult(timeoutSeconds: bluetooth.backendMode == .mock ? 5 : 3) {
                            let stream = try await bluetooth.subscribe(to: notifying, peripheralID: peripheral.id)
                            for try await notification in stream {
                                return notification
                            }
                            throw HostCommandError.bluetoothCheckFailed("Notification stream ended before yielding a value.")
                        }
                        let rendered = firstNotification.value.isEmpty ? "<empty>" : String(decoding: firstNotification.value, as: UTF8.self)
                        print("notify: \(rendered)")
                    } catch {
                        if bluetooth.backendMode == .winrt {
                            print("notify: subscription armed for \(notifying.characteristicUUID) (no live packet within timeout)")
                        } else {
                            throw error
                        }
                    }
                } else if bluetooth.backendMode == .winrt {
                    print("notify: no notifying characteristic discovered on \(peripheral.name)")
                } else {
                    throw HostCommandError.bluetoothCheckFailed("No notifying characteristic was discovered for \(peripheral.name).")
                }

                print("bluetooth success")
                return
            } catch {
                lastFailure = "Peripheral \(peripheral.name) failed validation: \(error)"
                print("candidate failed: \(lastFailure)")
            }
        }

        throw HostCommandError.bluetoothCheckFailed(lastFailure)
    }

    private static func makeRuntime(registry: AppModuleRegistry) -> any EmulatorRuntime {
        #if os(Windows)
        return Win32EmulatorRuntime(registry: registry)
        #else
        return POSIXEmulatorRuntime(registry: registry)
        #endif
    }

    private static func isDeveloperModeEnabled() -> Bool {
        let systemRoot = ProcessInfo.processInfo.environment["SystemRoot"] ?? #"C:\Windows"#
        let regExecutable = URL(fileURLWithPath: systemRoot)
            .appendingPathComponent("System32")
            .appendingPathComponent("reg.exe")
            .path
        let registryQuery = try? runProcess(
            regExecutable,
            [
                "query",
                #"HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock"#,
                "/v",
                "AllowDevelopmentWithoutDevLicense",
            ]
        )

        return registryQuery?.exitCode == 0 && registryQuery?.output.contains("0x1") == true
    }

    private static func resolveVisualStudioInstallPath() -> String? {
        let programFilesX86 = ProcessInfo.processInfo.environment["ProgramFiles(x86)"] ?? #"C:\Program Files (x86)"#
        let vswherePath = URL(fileURLWithPath: programFilesX86)
            .appendingPathComponent("Microsoft Visual Studio")
            .appendingPathComponent("Installer")
            .appendingPathComponent("vswhere.exe")
            .path

        guard FileManager.default.fileExists(atPath: vswherePath) else {
            return nil
        }

        let result = try? runProcess(vswherePath, ["-latest", "-products", "*", "-property", "installationPath"])
        guard let result, result.exitCode == 0 else {
            return nil
        }

        let installPath = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return installPath.isEmpty ? nil : installPath
    }

    private static func resolveMSVCX64CompilerPath(installPath: String) -> String? {
        resolveNewestPath(in: URL(fileURLWithPath: installPath)
            .appendingPathComponent("VC")
            .appendingPathComponent("Tools")
            .appendingPathComponent("MSVC")
            .path, suffixComponents: ["bin", "Hostx64", "x64", "cl.exe"])
    }

    private static func resolveMSVCARM64CompilerPath(installPath: String) -> String? {
        let root = URL(fileURLWithPath: installPath)
            .appendingPathComponent("VC")
            .appendingPathComponent("Tools")
            .appendingPathComponent("MSVC")
            .path
        return resolveNewestPath(in: root, suffixComponents: ["bin", "Hostx64", "arm64", "cl.exe"])
            ?? resolveNewestPath(in: root, suffixComponents: ["bin", "Hostarm64", "arm64", "cl.exe"])
    }

    private static func resolveMSBuildPath(installPath: String) -> String? {
        let msbuildPath = URL(fileURLWithPath: installPath)
            .appendingPathComponent("MSBuild")
            .appendingPathComponent("Current")
            .appendingPathComponent("Bin")
            .appendingPathComponent("MSBuild.exe")
            .path

        return FileManager.default.fileExists(atPath: msbuildPath) ? msbuildPath : nil
    }

    private static func resolveWindows11SDKPath(minimumBuild: Int) -> String? {
        let sdkRoot = URL(fileURLWithPath: #"C:\Program Files (x86)\Windows Kits\10\Include"#)
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: sdkRoot.path) else {
            return nil
        }

        let sdkDirectories = (try? fileManager.contentsOfDirectory(at: sdkRoot, includingPropertiesForKeys: nil))
            ?? []

        let matchingSDKs = sdkDirectories
            .filter { $0.hasDirectoryPath }
            .compactMap { url -> (build: Int, path: String)? in
                let components = url.lastPathComponent.split(separator: ".")
                guard components.count >= 3 else {
                    return nil
                }

                guard
                    let major = Int(components[0]),
                    let minor = Int(components[1]),
                    let build = Int(components[2]),
                    major == 10,
                    minor == 0,
                    build >= minimumBuild
                else {
                    return nil
                }

                return (build: build, path: url.path)
            }
            .sorted { lhs, rhs in
                if lhs.build == rhs.build {
                    return lhs.path > rhs.path
                }
                return lhs.build > rhs.build
            }

        return matchingSDKs.first?.path
    }

    private static func resolveExecutable(named executableName: String, fallbackCandidates: [String]) -> String? {
        if let resolvedOnPath = resolveOnPath(named: executableName) {
            return resolvedOnPath
        }

        for candidate in fallbackCandidates where FileManager.default.isExecutableFile(atPath: candidate) || FileManager.default.fileExists(atPath: candidate) {
            return candidate
        }

        return nil
    }

    private static func resolveOnPath(named executableName: String) -> String? {
        let environment = ProcessInfo.processInfo.environment
        let pathKey = environment.keys.first(where: { $0.caseInsensitiveCompare("PATH") == .orderedSame }) ?? "PATH"
        #if os(Windows)
        let separator = ";"
        #else
        let separator = ":"
        #endif
        let pathValue = environment[pathKey] ?? ""

        for entry in pathValue.split(separator: Character(separator)).map(String.init) where !entry.isEmpty {
            let candidate = URL(fileURLWithPath: entry).appendingPathComponent(executableName).path
            if FileManager.default.isExecutableFile(atPath: candidate) || FileManager.default.fileExists(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }

    private static func windowsToolCandidates(for tool: String) -> [String] {
        let environment = ProcessInfo.processInfo.environment
        let localAppData = environment["LOCALAPPDATA"] ?? ""
        let programFiles = environment["ProgramFiles"] ?? #"C:\Program Files"#
        let commonCandidates: [String]

        switch tool {
        case "swift":
            commonCandidates = [
                URL(fileURLWithPath: #"C:\Library\Developer\Toolchains"#).path,
                URL(fileURLWithPath: localAppData).appendingPathComponent("Programs").appendingPathComponent("Swift").path,
            ]
            return findExecutables(named: "swift.exe", under: commonCandidates)
        case "cmake":
            return [
                URL(fileURLWithPath: programFiles).appendingPathComponent("CMake").appendingPathComponent("bin").appendingPathComponent("cmake.exe").path,
            ]
        case "clang":
            return [
                URL(fileURLWithPath: programFiles).appendingPathComponent("LLVM").appendingPathComponent("bin").appendingPathComponent("clang.exe").path,
            ]
        case "nasm":
            return [
                URL(fileURLWithPath: programFiles).appendingPathComponent("NASM").appendingPathComponent("nasm.exe").path,
                URL(fileURLWithPath: localAppData).appendingPathComponent("Programs").appendingPathComponent("NASM").appendingPathComponent("nasm.exe").path,
                URL(fileURLWithPath: localAppData).appendingPathComponent("Microsoft").appendingPathComponent("WinGet").appendingPathComponent("Links").appendingPathComponent("nasm.exe").path,
            ]
        case "python":
            return [
                URL(fileURLWithPath: localAppData).appendingPathComponent("Programs").appendingPathComponent("Python").appendingPathComponent("Python310").appendingPathComponent("python.exe").path,
            ]
        default:
            return []
        }
    }

    private static func findExecutables(named executableName: String, under roots: [String]) -> [String] {
        var matches: [String] = []
        let fileManager = FileManager.default

        for root in roots where !root.isEmpty && fileManager.fileExists(atPath: root) {
            let enumerator = fileManager.enumerator(atPath: root)
            while let entry = enumerator?.nextObject() as? String {
                if URL(fileURLWithPath: entry).lastPathComponent.caseInsensitiveCompare(executableName) == .orderedSame {
                    matches.append(URL(fileURLWithPath: root).appendingPathComponent(entry).path)
                }
            }
        }

        return matches
    }

    private static func resolveNewestPath(in root: String, suffixComponents: [String]) -> String? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: root) else {
            return nil
        }

        let entries = (try? fileManager.contentsOfDirectory(atPath: root).sorted()) ?? []
        for entry in entries.reversed() {
            let candidate = suffixComponents.reduce(URL(fileURLWithPath: root).appendingPathComponent(entry)) { partialURL, component in
                partialURL.appendingPathComponent(component)
            }.path

            if fileManager.fileExists(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }

    private static func runProcess(_ executable: String, _ arguments: [String], timeout: TimeInterval? = nil) throws -> ProcessResult {
        let process = Process()
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("emulator-host-\(UUID().uuidString).log")
        _ = FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let outputHandle = try FileHandle(forWritingTo: outputURL)

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = outputHandle
        process.standardError = outputHandle

        try process.run()
        if let timeout {
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
        } else {
            process.waitUntilExit()
        }
        try outputHandle.close()
        let combinedData = try Data(contentsOf: outputURL)
        try? FileManager.default.removeItem(at: outputURL)

        return ProcessResult(
            exitCode: process.terminationStatus,
            output: String(decoding: combinedData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func runWindowsProcess(_ executable: String, _ arguments: [String], timeout: TimeInterval? = nil) throws -> ProcessResult {
        try runProcess(executable, arguments, timeout: timeout)
    }

    private static func summarizeDiagnosticOutput(_ output: String) -> String {
        let lines = output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .prefix(6)
            .map(String.init)

        if lines.isEmpty {
            return "no diagnostic output"
        }

        return lines.joined(separator: " | ")
    }

    private static func parseBluetoothBackend(_ arguments: [String]) throws -> EmulatorBluetoothBackendMode {
        guard arguments.count == 0 || arguments.count == 2 else {
            throw HostCommandError.usage
        }

        if arguments.isEmpty {
            return .auto
        }

        guard arguments[0] == "--backend" else {
            throw HostCommandError.usage
        }
        guard let backend = EmulatorBluetoothBackendMode(rawValue: arguments[1]) else {
            throw HostCommandError.bluetoothCheckFailed("Unsupported Bluetooth backend: \(arguments[1])")
        }
        return backend
    }

    private static func parseExpectedArchitecture(_ arguments: [String]) throws -> String? {
        guard arguments.isEmpty || arguments.count == 2 else {
            throw HostCommandError.usage
        }
        guard !arguments.isEmpty else {
            return nil
        }
        guard arguments[0] == "--expected-arch" else {
            throw HostCommandError.usage
        }
        let value = arguments[1].lowercased()
        guard value == "x64" || value == "arm64" else {
            throw HostCommandError.doctorFailed(["FAIL: unsupported expected architecture '\(arguments[1])'. Use x64 or arm64."])
        }
        return value
    }

    private static func parseObjCCheckOptions(_ arguments: [String]) throws -> ObjCCheckOptions {
        var backend: ObjCExperimentBackendMode = .auto
        var suite = "basic"
        var index = 0

        while index < arguments.count {
            switch arguments[index] {
            case "--backend":
                guard index + 1 < arguments.count, let parsed = ObjCExperimentBackendMode(rawValue: arguments[index + 1]) else {
                    throw HostCommandError.usage
                }
                backend = parsed
                index += 2
            case "--suite":
                guard index + 1 < arguments.count else {
                    throw HostCommandError.usage
                }
                let parsed = arguments[index + 1].lowercased()
                guard parsed == "basic" || parsed == "compat" else {
                    throw HostCommandError.usage
                }
                suite = parsed
                index += 2
            default:
                throw HostCommandError.usage
            }
        }

        return ObjCCheckOptions(backend: backend, suite: suite)
    }

    private static func currentWindowsArchitecture() -> String {
        let environment = ProcessInfo.processInfo.environment
        let rawValue = environment["PROCESSOR_ARCHITEW6432"] ?? environment["PROCESSOR_ARCHITECTURE"] ?? ""
        switch rawValue.uppercased() {
        case "AMD64", "X64":
            return "x64"
        case "ARM64":
            return "arm64"
        default:
            return rawValue.lowercased().isEmpty ? "unknown" : rawValue.lowercased()
        }
    }

    private static func describe(_ adapterState: EmulatorBluetoothAdapterState) -> String {
        switch adapterState {
        case .unknown:
            return "unknown"
        case .poweredOff:
            return "poweredOff"
        case .poweredOn:
            return "poweredOn"
        case .unavailable:
            return "unavailable"
        case .unauthorized:
            return "unauthorized"
        }
    }

    private static func parseUIDemoOptions(_ arguments: [String]) throws -> UIDemoOptions {
        var devicePreset: EmulatorDevicePreset?
        var orientation: EmulatorDeviceOrientation?
        var autoCloseMilliseconds: Int32?
        var backgroundAfterMilliseconds: Int32?
        var resumeAfterMilliseconds: Int32?
        var rotateAfterMilliseconds: Int32?
        var index = 0

        while index < arguments.count {
            switch arguments[index] {
            case "--device-preset":
                guard index + 1 < arguments.count else { throw HostCommandError.usage }
                guard let parsed = EmulatorDevicePreset(rawValue: arguments[index + 1]) else {
                    throw HostCommandError.uiDemoFailed("Unsupported device preset: \(arguments[index + 1])")
                }
                devicePreset = parsed
                index += 2
            case "--orientation":
                guard index + 1 < arguments.count else { throw HostCommandError.usage }
                guard let parsed = EmulatorDeviceOrientation(rawValue: arguments[index + 1]) else {
                    throw HostCommandError.uiDemoFailed("Unsupported orientation: \(arguments[index + 1])")
                }
                orientation = parsed
                index += 2
            case "--autoclose-ms":
                guard index + 1 < arguments.count, let parsed = Int32(arguments[index + 1]) else {
                    throw HostCommandError.usage
                }
                autoCloseMilliseconds = parsed
                index += 2
            case "--background-after-ms":
                guard index + 1 < arguments.count, let parsed = Int32(arguments[index + 1]) else {
                    throw HostCommandError.usage
                }
                backgroundAfterMilliseconds = parsed
                index += 2
            case "--resume-after-ms":
                guard index + 1 < arguments.count, let parsed = Int32(arguments[index + 1]) else {
                    throw HostCommandError.usage
                }
                resumeAfterMilliseconds = parsed
                index += 2
            case "--rotate-after-ms":
                guard index + 1 < arguments.count, let parsed = Int32(arguments[index + 1]) else {
                    throw HostCommandError.usage
                }
                rotateAfterMilliseconds = parsed
                index += 2
            default:
                throw HostCommandError.usage
            }
        }

        return UIDemoOptions(
            devicePreset: devicePreset,
            orientation: orientation,
            autoCloseMilliseconds: autoCloseMilliseconds,
            backgroundAfterMilliseconds: backgroundAfterMilliseconds,
            resumeAfterMilliseconds: resumeAfterMilliseconds,
            rotateAfterMilliseconds: rotateAfterMilliseconds
        )
    }

    private static func scheduleUIDemoValidationInputs(
        handle: Win32RedrawHandle,
        state: SmokeDemoState,
        invalidation: BufferedUIInvalidationService
    ) {
        let gesturePoint = UIPoint(x: 180, y: 320)
        let dragEnd = UIPoint(x: 248, y: 372)
        let keySchedule: [(milliseconds: Int, key: Win32VirtualKey, shift: Bool)] = [
            (430, .tab, false),
            (540, .tab, false),
            (720, .enter, false),
            (820, .tab, false),
            (900, .tab, false),
            (980, .tab, false),
        ]

        for item in keySchedule {
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + .milliseconds(item.milliseconds)) {
                handle.sendKey(item.key, shiftDown: item.shift)
            }
        }

        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + .milliseconds(620)) {
            handle.sendText("GO")
        }

        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + .milliseconds(1060)) {
            handle.sendPointer(phase: .down, at: gesturePoint)
            _ = state.handle(gesture: .dragBegan(start: gesturePoint, current: gesturePoint), on: "demo.gesture.surface")
            invalidation.requestRedraw()
        }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + .milliseconds(1140)) {
            handle.sendPointer(phase: .move, at: dragEnd)
            _ = state.handle(gesture: .dragChanged(start: gesturePoint, current: dragEnd), on: "demo.gesture.surface")
            invalidation.requestRedraw()
        }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + .milliseconds(1220)) {
            handle.sendPointer(phase: .up, at: dragEnd)
            _ = state.handle(gesture: .dragEnded(start: gesturePoint, end: dragEnd), on: "demo.gesture.surface")
            invalidation.requestRedraw()
        }

        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + .milliseconds(1280)) {
            handle.sendPointer(phase: .down, at: gesturePoint)
        }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + .milliseconds(1340)) {
            handle.sendPointer(phase: .up, at: gesturePoint)
            _ = state.handle(gesture: .longPress(location: gesturePoint), on: "demo.gesture.surface")
            invalidation.requestRedraw()
        }

        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + .milliseconds(1380)) {
            handle.sendWheel(delta: 120, at: gesturePoint, modifiers: [.control])
            _ = state.handle(gesture: .pinch(delta: 1.0, location: gesturePoint), on: "demo.gesture.surface")
            invalidation.requestRedraw()
        }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + .milliseconds(1440)) {
            handle.sendWheel(delta: 120, at: gesturePoint, modifiers: [.alt])
            _ = state.handle(gesture: .rotate(deltaDegrees: 8.0, location: gesturePoint), on: "demo.gesture.surface")
            invalidation.requestRedraw()
        }
    }

    private static func scheduleUIDemoSimulation(
        state: SmokeDemoState,
        environmentState: EmulatorRenderEnvironmentState,
        invalidation: BufferedUIInvalidationService,
        backgroundAfterMilliseconds: Int32?,
        resumeAfterMilliseconds: Int32?,
        rotateAfterMilliseconds: Int32?
    ) {
        if let backgroundAfterMilliseconds {
            DispatchQueue.global(qos: .userInitiated).asyncAfter(
                deadline: .now() + .milliseconds(Int(backgroundAfterMilliseconds))
            ) {
                EmulatorLifecycleControllerRunner.emitIfNeeded(.didEnterBackground, on: state)
                invalidation.requestRedraw()
            }
        }

        if let resumeAfterMilliseconds {
            DispatchQueue.global(qos: .userInitiated).asyncAfter(
                deadline: .now() + .milliseconds(Int(resumeAfterMilliseconds))
            ) {
                EmulatorLifecycleControllerRunner.emitIfNeeded(.didEnterForeground, on: state)
                invalidation.requestRedraw()
            }
        }

        if let rotateAfterMilliseconds {
            DispatchQueue.global(qos: .userInitiated).asyncAfter(
                deadline: .now() + .milliseconds(Int(rotateAfterMilliseconds))
            ) {
                let updated = environmentState.rotate()
                EmulatorLifecycleControllerRunner.emitIfNeeded(
                    .deviceEnvironmentChanged(updated.device),
                    on: state
                )
                invalidation.requestRedraw()
            }
        }
    }

    private static func waitForAsyncResult<T>(
        timeoutSeconds: TimeInterval = 10,
        operation: @escaping @Sendable () async throws -> T
    ) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = AsyncResultBox<T>()

        Task {
            do {
                let value = try await operation()
                resultBox.store(.success(value))
            } catch {
                resultBox.store(.failure(error))
            }
            semaphore.signal()
        }

        guard semaphore.wait(timeout: .now() + timeoutSeconds) == .success else {
            throw HostCommandError.bluetoothCheckFailed("Timed out waiting for asynchronous Bluetooth work to complete.")
        }

        guard let finalResult = resultBox.value() else {
            throw HostCommandError.bluetoothCheckFailed("Bluetooth work completed without a result.")
        }
        return try finalResult.get()
    }
}

private final class AsyncResultBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<T, Error>?

    func store(_ result: Result<T, Error>) {
        lock.withLock {
            self.result = result
        }
    }

    func value() -> Result<T, Error>? {
        lock.withLock {
            result
        }
    }
}

private struct UIDemoOptions {
    let devicePreset: EmulatorDevicePreset?
    let orientation: EmulatorDeviceOrientation?
    let autoCloseMilliseconds: Int32?
    let backgroundAfterMilliseconds: Int32?
    let resumeAfterMilliseconds: Int32?
    let rotateAfterMilliseconds: Int32?
}

private struct ObjCCheckOptions {
    let backend: ObjCExperimentBackendMode
    let suite: String
}

do {
    try EmulatorHostMain.run()
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
