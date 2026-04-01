import EmulatorAppSDK
import EmulatorDiagnostics
import Foundation
import RendererText

public enum ExternalRunnerSupportError: Error, CustomStringConvertible {
    case usage(String)
    case unsupportedRenderer(String)
    case invalidAutoClose(String)
    case invalidBluetoothBackend(String)
    case invalidDevicePreset(String)
    case invalidOrientation(String)
    case invalidSimulationDelay(String)
    case invalidFormat(String)
    case compatibilityFailed(String)

    public var description: String {
        switch self {
        case .usage(let value), .compatibilityFailed(let value):
            return value
        case .unsupportedRenderer(let value):
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
            return "Invalid diagnostics format: \(value)"
        }
    }
}

public enum ExternalRunnerSupport {
    public static func run<Registration: EmulatorAppRegistration>(
        registration: Registration.Type,
        executableName: String,
        appPackageRootPath: String,
        arguments: [String] = Array(CommandLine.arguments.dropFirst())
    ) throws {
        guard let command = arguments.first else {
            throw ExternalRunnerSupportError.usage(usage(executableName: executableName))
        }

        switch command {
        case "validate":
            try validate(
                registration: registration,
                arguments: Array(arguments.dropFirst())
            )
        case "run":
            try runApp(
                registration: registration,
                arguments: Array(arguments.dropFirst())
            )
        case "inspect":
            try inspect(
                registration: registration,
                appPackageRootPath: appPackageRootPath,
                arguments: Array(arguments.dropFirst())
            )
        case "trace":
            try trace(
                registration: registration,
                arguments: Array(arguments.dropFirst())
            )
        case "compat-check":
            try compatCheck(
                registration: registration,
                appPackageRootPath: appPackageRootPath,
                arguments: Array(arguments.dropFirst())
            )
        default:
            throw ExternalRunnerSupportError.usage(usage(executableName: executableName))
        }
    }

    private static func usage(executableName: String) -> String {
        "Usage: \(executableName) <validate|run|inspect|trace|compat-check> [--renderer <text|win32>] [--format <text|json>] [--autoclose-ms <n>] [--bluetooth-backend <auto|mock|winrt>] [--device-preset <phoneCompact|phoneTall|tablet>] [--orientation <portrait|landscape>] [--background-after-ms <n>] [--resume-after-ms <n>] [--rotate-after-ms <n>]"
    }

    private static func validate<Registration: EmulatorAppRegistration>(
        registration: Registration.Type,
        arguments: [String]
    ) throws {
        let manifest = registration.manifest
        let options = try parseValidateOptions(arguments, usage: usage(executableName: String(describing: Registration.self)))
        let launchRenderer = try selectLaunchRenderer(
            for: manifest,
            bluetoothBackend: options.bluetoothBackend
        )
        let rendererSummaries = capabilitySummary(
            for: manifest,
            bluetoothBackend: options.bluetoothBackend
        )
        let services = try makeRegistry(
            for: launchRenderer,
            bluetoothBackend: options.bluetoothBackend
        ).makeServices(for: manifest)
        let controller = EmulatorAppRegistrationResolver.makeController(for: registration, services: services)
        try EmulatorLifecycleControllerRunner.startIfNeeded(controller)
        defer {
            emitLifecycle(.willTerminate, to: controller)
            EmulatorLifecycleControllerRunner.stopIfNeeded(controller)
        }

        let environmentState = makeEnvironmentState(
            manifest: manifest,
            renderer: launchRenderer,
            devicePreset: nil,
            orientation: nil
        )
        _ = makeRenderSession(controller: controller, environmentState: environmentState)
        print("capabilities: \(rendererSummaries)")
        print("app validate: PASS \(manifest.displayName) [\(manifest.appID)] using \(launchRenderer.rawValue)")
    }

    private static func runApp<Registration: EmulatorAppRegistration>(
        registration: Registration.Type,
        arguments: [String]
    ) throws {
        let manifest = registration.manifest
        let options = try parseRunOptions(arguments, defaultRenderer: manifest.defaultRenderer)
        guard manifest.supportedRenderers.contains(options.renderer) else {
            throw ExternalRunnerSupportError.unsupportedRenderer(options.renderer.rawValue)
        }

        let invalidationService = BufferedUIInvalidationService()
        let services = try makeRegistry(
            for: options.renderer,
            bluetoothBackend: options.bluetoothBackend
        ).makeServices(
            for: manifest,
            invalidationService: invalidationService
        )
        let controller = EmulatorAppRegistrationResolver.makeController(for: registration, services: services)
        let controllerBox = ControllerBox(controller)

        try EmulatorLifecycleControllerRunner.startIfNeeded(controllerBox.controller)
        defer {
            emitLifecycle(.willTerminate, to: controllerBox.controller)
            EmulatorLifecycleControllerRunner.stopIfNeeded(controllerBox.controller)
        }

        let environmentState = makeEnvironmentState(
            manifest: manifest,
            renderer: options.renderer,
            devicePreset: options.devicePreset,
            orientation: options.orientation
        )
        emitLifecycle(.didLaunch, to: controllerBox.controller)
        emitLifecycle(.didEnterForeground, to: controllerBox.controller)

        switch options.renderer {
        case .text:
            applySynchronousSimulation(
                controller: controllerBox.controller,
                environmentState: environmentState,
                options: options
            )
            let session = makeRenderSession(
                controller: controllerBox.controller,
                environmentState: environmentState
            )
            print(TerminalRenderer().render(session.document, in: session.environment.device.viewport))
        case .win32:
            try runWin32App(
                manifest: manifest,
                controllerBox: controllerBox,
                environmentState: environmentState,
                invalidationService: invalidationService,
                options: options
            )
        }
    }

    private static func inspect<Registration: EmulatorAppRegistration>(
        registration: Registration.Type,
        appPackageRootPath: String,
        arguments: [String]
    ) throws {
        let manifest = registration.manifest
        let options = try parseInspectOptions(arguments, defaultRenderer: manifest.defaultRenderer)
        guard manifest.supportedRenderers.contains(options.renderer) else {
            throw ExternalRunnerSupportError.unsupportedRenderer(options.renderer.rawValue)
        }

        let registry = makeRegistry(for: options.renderer, bluetoothBackend: options.bluetoothBackend)
        let services = try registry.makeServices(for: manifest)
        let controller = EmulatorAppRegistrationResolver.makeController(for: registration, services: services)
        try EmulatorLifecycleControllerRunner.startIfNeeded(controller)
        defer {
            emitLifecycle(.willTerminate, to: controller)
            EmulatorLifecycleControllerRunner.stopIfNeeded(controller)
        }

        let environmentState = makeEnvironmentState(
            manifest: manifest,
            renderer: options.renderer,
            devicePreset: options.devicePreset,
            orientation: options.orientation
        )
        emitLifecycle(.didLaunch, to: controller)
        emitLifecycle(.didEnterForeground, to: controller)
        let session = makeRenderSession(controller: controller, environmentState: environmentState)
        let snapshot = EmulatorInspectionBuilder.makeSnapshot(
            manifest: manifest,
            environment: session.environment,
            document: session.document,
            output: session.output
        )
        _ = appPackageRootPath
        print(try EmulatorDiagnosticsFormatter.formatInspection(snapshot, format: options.format))
    }

    private static func trace<Registration: EmulatorAppRegistration>(
        registration: Registration.Type,
        arguments: [String]
    ) throws {
        let manifest = registration.manifest
        let options = try parseTraceOptions(arguments, defaultRenderer: manifest.defaultRenderer)
        guard manifest.supportedRenderers.contains(options.renderer) else {
            throw ExternalRunnerSupportError.unsupportedRenderer(options.renderer.rawValue)
        }

        let recorder = EmulatorTraceRecorder()
        let diagnosticsService = BufferedDiagnosticsService()
        let invalidationService = BufferedUIInvalidationService()
        invalidationService.setObserver {
            recorder.record(category: "ui", name: "redraw-request")
        }

        let services = try makeRegistry(
            for: options.renderer,
            bluetoothBackend: options.bluetoothBackend
        ).makeServices(
            for: manifest,
            invalidationService: invalidationService,
            diagnosticsService: diagnosticsService
        )
        let controller = EmulatorAppRegistrationResolver.makeController(for: registration, services: services)
        let controllerBox = ControllerBox(controller)

        recorder.record(
            category: "runner",
            name: "start",
            metadata: [
                "renderer": options.renderer.rawValue,
                "bluetoothBackend": options.bluetoothBackend.rawValue,
            ]
        )
        try EmulatorLifecycleControllerRunner.startIfNeeded(controllerBox.controller)
        defer {
            emitLifecycle(.willTerminate, to: controllerBox.controller, recorder: recorder)
            EmulatorLifecycleControllerRunner.stopIfNeeded(controllerBox.controller)
            recorder.record(category: "runner", name: "stop")
        }

        let environmentState = makeEnvironmentState(
            manifest: manifest,
            renderer: options.renderer,
            devicePreset: options.devicePreset,
            orientation: options.orientation
        )
        emitLifecycle(.didLaunch, to: controllerBox.controller, recorder: recorder)
        emitLifecycle(.didEnterForeground, to: controllerBox.controller, recorder: recorder)

        switch options.renderer {
        case .text:
            applySynchronousSimulation(
                controller: controllerBox.controller,
                environmentState: environmentState,
                options: RunOptions(
                    renderer: options.renderer,
                    autoCloseMilliseconds: options.autoCloseMilliseconds,
                    bluetoothBackend: options.bluetoothBackend,
                    devicePreset: options.devicePreset,
                    orientation: options.orientation,
                    backgroundAfterMilliseconds: options.backgroundAfterMilliseconds,
                    resumeAfterMilliseconds: options.resumeAfterMilliseconds,
                    rotateAfterMilliseconds: options.rotateAfterMilliseconds
                ),
                recorder: recorder
            )
            let session = makeRenderSession(
                controller: controllerBox.controller,
                environmentState: environmentState
            )
            recorder.record(
                category: "renderer",
                name: "frameGenerated",
                metadata: [
                    "renderer": "text",
                    "viewport": "\(session.environment.device.viewport.width)x\(session.environment.device.viewport.height)",
                    "commands": "\(session.output.commands.count)",
                    "interactions": "\(session.output.interactions.count)",
                ]
            )
        case .win32:
            try traceWin32App(
                manifest: manifest,
                controllerBox: controllerBox,
                environmentState: environmentState,
                invalidationService: invalidationService,
                options: options,
                recorder: recorder
            )
        }

        recorder.recordAppDiagnostics(diagnosticsService.snapshot())
        print(try EmulatorDiagnosticsFormatter.formatTrace(recorder.snapshot(), format: options.format))
    }

    private static func compatCheck<Registration: EmulatorAppRegistration>(
        registration: Registration.Type,
        appPackageRootPath: String,
        arguments: [String]
    ) throws {
        let manifest = registration.manifest
        let options = try parseCompatCheckOptions(arguments)
        let renderers = options.renderer.map { [$0] }
            ?? manifest.supportedRenderers.sorted(by: { $0.rawValue < $1.rawValue })
        let inputs = try renderers.map {
            try compatibilityInput(
                renderer: $0,
                manifest: manifest,
                registration: registration,
                bluetoothBackend: options.bluetoothBackend,
                appPackageRootPath: appPackageRootPath
            )
        }
        let report = EmulatorCompatibilityAnalyzer.makeReport(inputs: inputs)
        let formatted = try EmulatorDiagnosticsFormatter.formatCompatibility(report, format: options.format)
        if report.hasErrors {
            throw ExternalRunnerSupportError.compatibilityFailed(formatted)
        }
        print(formatted)
    }
}

struct ExternalRunnerRenderedSession {
    let environment: EmulatorRenderEnvironment
    let document: ScreenDocument
    let output: RenderPipelineOutput
}

final class ControllerBox: @unchecked Sendable {
    let controller: any EmulatorAppController

    init(_ controller: any EmulatorAppController) {
        self.controller = controller
    }
}

extension ExternalRunnerSupport {
    static func makeRegistry(
        for renderer: EmulatorRendererMode,
        bluetoothBackend: EmulatorBluetoothBackendMode
    ) -> EmulatorHostServiceRegistry {
        EmulatorHostServiceRegistry(
            rendererMode: renderer,
            foundationRootPath: FileManager.default.currentDirectoryPath,
            environment: ProcessInfo.processInfo.environment,
            bluetoothBackendMode: bluetoothBackend
        )
    }

    static func selectLaunchRenderer(
        for manifest: EmulatorAppManifest,
        bluetoothBackend: EmulatorBluetoothBackendMode
    ) throws -> EmulatorRendererMode {
        let defaultRegistry = makeRegistry(for: manifest.defaultRenderer, bluetoothBackend: bluetoothBackend)
        if defaultRegistry.validationReport(for: manifest).launchable {
            return manifest.defaultRenderer
        }

        for renderer in manifest.supportedRenderers.sorted(by: { $0.rawValue < $1.rawValue }) {
            let candidateRegistry = makeRegistry(for: renderer, bluetoothBackend: bluetoothBackend)
            if candidateRegistry.validationReport(for: manifest).launchable {
                return renderer
            }
        }

        throw EmulatorHostServiceRegistryError.unavailableRequiredCapabilities(
            renderer: manifest.defaultRenderer,
            statuses: defaultRegistry.validationReport(for: manifest).unavailableCapabilities
        )
    }

    static func capabilitySummary(
        for manifest: EmulatorAppManifest,
        bluetoothBackend: EmulatorBluetoothBackendMode
    ) -> String {
        manifest.supportedRenderers
            .sorted { $0.rawValue < $1.rawValue }
            .map { renderer -> String in
                let report = makeRegistry(for: renderer, bluetoothBackend: bluetoothBackend)
                    .validationReport(for: manifest)
                if report.statuses.isEmpty {
                    return "\(renderer.rawValue): none"
                }

                let summary = report.statuses
                    .map { "\($0.capability.rawValue)=\($0.availability.rawValue)" }
                    .joined(separator: ", ")
                return "\(renderer.rawValue): \(summary)"
            }
            .joined(separator: " | ")
    }

    static func makeEnvironmentState(
        manifest: EmulatorAppManifest,
        renderer: EmulatorRendererMode,
        devicePreset: EmulatorDevicePreset?,
        orientation: EmulatorDeviceOrientation?
    ) -> EmulatorRenderEnvironmentState {
        EmulatorRenderEnvironmentState(
            manifest: manifest,
            rendererMode: renderer,
            devicePresetOverride: devicePreset,
            orientationOverride: orientation
        )
    }

    static func makeRenderSession(
        controller: any EmulatorAppController,
        environmentState: EmulatorRenderEnvironmentState,
        viewport: DeviceViewport? = nil,
        focusedAction: UIActionID? = nil
    ) -> ExternalRunnerRenderedSession {
        let environment = environmentState.snapshot(viewport: viewport)
        let document = EmulatorAppControllerBridge.makeDocument(
            from: controller,
            environment: environment
        )
        let output = RenderPipeline.makeDisplayList(
            for: document,
            in: environment.device.viewport,
            focusedAction: focusedAction
        )
        return ExternalRunnerRenderedSession(
            environment: environment,
            document: document,
            output: output
        )
    }

    static func emitLifecycle(
        _ event: EmulatorLifecycleEvent,
        to controller: any EmulatorAppController,
        recorder: EmulatorTraceRecorder? = nil
    ) {
        recorder?.record(
            category: "lifecycle",
            name: lifecycleEventName(event),
            metadata: lifecycleMetadata(event)
        )
        EmulatorLifecycleControllerRunner.emitIfNeeded(event, on: controller)
    }

    static func lifecycleEventName(_ event: EmulatorLifecycleEvent) -> String {
        switch event {
        case .didLaunch:
            return "didLaunch"
        case .didEnterForeground:
            return "didEnterForeground"
        case .didEnterBackground:
            return "didEnterBackground"
        case .willTerminate:
            return "willTerminate"
        case .deviceEnvironmentChanged:
            return "deviceEnvironmentChanged"
        }
    }

    static func lifecycleMetadata(_ event: EmulatorLifecycleEvent) -> [String: String] {
        switch event {
        case .deviceEnvironmentChanged(let environment):
            return [
                "preset": environment.preset.rawValue,
                "orientation": environment.orientation.rawValue,
                "viewport": "\(environment.viewport.width)x\(environment.viewport.height)",
            ]
        default:
            return [:]
        }
    }

    static func applySynchronousSimulation(
        controller: any EmulatorAppController,
        environmentState: EmulatorRenderEnvironmentState,
        options: RunOptions,
        recorder: EmulatorTraceRecorder? = nil
    ) {
        if options.backgroundAfterMilliseconds != nil {
            emitLifecycle(.didEnterBackground, to: controller, recorder: recorder)
        }
        if options.resumeAfterMilliseconds != nil {
            emitLifecycle(.didEnterForeground, to: controller, recorder: recorder)
        }
        if options.rotateAfterMilliseconds != nil {
            let updated = environmentState.rotate()
            emitLifecycle(.deviceEnvironmentChanged(updated.device), to: controller, recorder: recorder)
        }
    }

    static func scheduleSimulation(
        controllerBox: ControllerBox,
        environmentState: EmulatorRenderEnvironmentState,
        invalidationService: BufferedUIInvalidationService,
        options: RunOptions,
        recorder: EmulatorTraceRecorder? = nil
    ) {
        if let backgroundAfter = options.backgroundAfterMilliseconds {
            DispatchQueue.global(qos: .userInitiated).asyncAfter(
                deadline: .now() + .milliseconds(Int(backgroundAfter))
            ) {
                emitLifecycle(.didEnterBackground, to: controllerBox.controller, recorder: recorder)
                invalidationService.requestRedraw()
            }
        }

        if let resumeAfter = options.resumeAfterMilliseconds {
            DispatchQueue.global(qos: .userInitiated).asyncAfter(
                deadline: .now() + .milliseconds(Int(resumeAfter))
            ) {
                emitLifecycle(.didEnterForeground, to: controllerBox.controller, recorder: recorder)
                invalidationService.requestRedraw()
            }
        }

        if let rotateAfter = options.rotateAfterMilliseconds {
            DispatchQueue.global(qos: .userInitiated).asyncAfter(
                deadline: .now() + .milliseconds(Int(rotateAfter))
            ) {
                let updated = environmentState.rotate()
                emitLifecycle(.deviceEnvironmentChanged(updated.device), to: controllerBox.controller, recorder: recorder)
                invalidationService.requestRedraw()
            }
        }
    }

    static func compatibilityInput<Registration: EmulatorAppRegistration>(
        renderer: EmulatorRendererMode,
        manifest: EmulatorAppManifest,
        registration: Registration.Type,
        bluetoothBackend: EmulatorBluetoothBackendMode,
        appPackageRootPath: String
    ) throws -> EmulatorRendererCompatibilityInput {
        let registry = makeRegistry(for: renderer, bluetoothBackend: bluetoothBackend)
        let validation = registry.validationReport(for: manifest)

        guard manifest.supportedRenderers.contains(renderer) else {
            return EmulatorRendererCompatibilityInput(
                rendererMode: renderer,
                manifest: manifest,
                packageRootPath: appPackageRootPath,
                capabilityStatuses: validation.statuses,
                inspectionSnapshot: nil,
                output: nil
            )
        }

        guard validation.launchable else {
            return EmulatorRendererCompatibilityInput(
                rendererMode: renderer,
                manifest: manifest,
                packageRootPath: appPackageRootPath,
                capabilityStatuses: validation.statuses,
                inspectionSnapshot: nil,
                output: nil
            )
        }

        let services = try registry.makeServices(for: manifest)
        let controller = EmulatorAppRegistrationResolver.makeController(for: registration, services: services)
        try EmulatorLifecycleControllerRunner.startIfNeeded(controller)
        defer {
            emitLifecycle(.willTerminate, to: controller)
            EmulatorLifecycleControllerRunner.stopIfNeeded(controller)
        }

        let environmentState = makeEnvironmentState(
            manifest: manifest,
            renderer: renderer,
            devicePreset: nil,
            orientation: nil
        )
        emitLifecycle(.didLaunch, to: controller)
        emitLifecycle(.didEnterForeground, to: controller)
        let session = makeRenderSession(controller: controller, environmentState: environmentState)
        let snapshot = EmulatorInspectionBuilder.makeSnapshot(
            manifest: manifest,
            environment: session.environment,
            document: session.document,
            output: session.output
        )
        return EmulatorRendererCompatibilityInput(
            rendererMode: renderer,
            manifest: manifest,
            packageRootPath: appPackageRootPath,
            capabilityStatuses: validation.statuses,
            inspectionSnapshot: snapshot,
            output: session.output
        )
    }
}

struct ValidateOptions {
    let bluetoothBackend: EmulatorBluetoothBackendMode
}

struct ParsedRendererCommandOptions {
    let renderer: EmulatorRendererMode
    let autoCloseMilliseconds: Int32?
    let bluetoothBackend: EmulatorBluetoothBackendMode
    let devicePreset: EmulatorDevicePreset?
    let orientation: EmulatorDeviceOrientation?
    let backgroundAfterMilliseconds: Int32?
    let resumeAfterMilliseconds: Int32?
    let rotateAfterMilliseconds: Int32?
    let format: EmulatorDiagnosticsFormat?
}

struct RunOptions {
    let renderer: EmulatorRendererMode
    let autoCloseMilliseconds: Int32?
    let bluetoothBackend: EmulatorBluetoothBackendMode
    let devicePreset: EmulatorDevicePreset?
    let orientation: EmulatorDeviceOrientation?
    let backgroundAfterMilliseconds: Int32?
    let resumeAfterMilliseconds: Int32?
    let rotateAfterMilliseconds: Int32?
}

struct InspectOptions {
    let renderer: EmulatorRendererMode
    let bluetoothBackend: EmulatorBluetoothBackendMode
    let devicePreset: EmulatorDevicePreset?
    let orientation: EmulatorDeviceOrientation?
    let format: EmulatorDiagnosticsFormat
}

struct TraceOptions {
    let renderer: EmulatorRendererMode
    let autoCloseMilliseconds: Int32?
    let bluetoothBackend: EmulatorBluetoothBackendMode
    let devicePreset: EmulatorDevicePreset?
    let orientation: EmulatorDeviceOrientation?
    let backgroundAfterMilliseconds: Int32?
    let resumeAfterMilliseconds: Int32?
    let rotateAfterMilliseconds: Int32?
    let format: EmulatorDiagnosticsFormat
}

struct CompatCheckOptions {
    let renderer: EmulatorRendererMode?
    let bluetoothBackend: EmulatorBluetoothBackendMode
    let format: EmulatorDiagnosticsFormat
}

extension ExternalRunnerSupport {
    static func parseValidateOptions(_ arguments: [String], usage: String) throws -> ValidateOptions {
        var bluetoothBackend: EmulatorBluetoothBackendMode = .auto
        var index = 0

        while index < arguments.count {
            switch arguments[index] {
            case "--bluetooth-backend":
                guard index + 1 < arguments.count else {
                    throw ExternalRunnerSupportError.usage(usage)
                }
                guard let parsed = EmulatorBluetoothBackendMode(rawValue: arguments[index + 1]) else {
                    throw ExternalRunnerSupportError.invalidBluetoothBackend(arguments[index + 1])
                }
                bluetoothBackend = parsed
                index += 2
            default:
                throw ExternalRunnerSupportError.usage(usage)
            }
        }

        return ValidateOptions(bluetoothBackend: bluetoothBackend)
    }

    static func parseRunOptions(
        _ arguments: [String],
        defaultRenderer: EmulatorRendererMode
    ) throws -> RunOptions {
        let parsed = try parseRendererCommandOptions(
            arguments,
            defaultRenderer: defaultRenderer,
            includeFormat: false
        )
        return RunOptions(
            renderer: parsed.renderer,
            autoCloseMilliseconds: parsed.autoCloseMilliseconds,
            bluetoothBackend: parsed.bluetoothBackend,
            devicePreset: parsed.devicePreset,
            orientation: parsed.orientation,
            backgroundAfterMilliseconds: parsed.backgroundAfterMilliseconds,
            resumeAfterMilliseconds: parsed.resumeAfterMilliseconds,
            rotateAfterMilliseconds: parsed.rotateAfterMilliseconds
        )
    }

    static func parseInspectOptions(
        _ arguments: [String],
        defaultRenderer: EmulatorRendererMode
    ) throws -> InspectOptions {
        let parsed = try parseRendererCommandOptions(
            arguments,
            defaultRenderer: defaultRenderer,
            includeFormat: true
        )
        return InspectOptions(
            renderer: parsed.renderer,
            bluetoothBackend: parsed.bluetoothBackend,
            devicePreset: parsed.devicePreset,
            orientation: parsed.orientation,
            format: parsed.format ?? .text
        )
    }

    static func parseTraceOptions(
        _ arguments: [String],
        defaultRenderer: EmulatorRendererMode
    ) throws -> TraceOptions {
        let parsed = try parseRendererCommandOptions(
            arguments,
            defaultRenderer: defaultRenderer,
            includeFormat: true
        )
        return TraceOptions(
            renderer: parsed.renderer,
            autoCloseMilliseconds: parsed.autoCloseMilliseconds,
            bluetoothBackend: parsed.bluetoothBackend,
            devicePreset: parsed.devicePreset,
            orientation: parsed.orientation,
            backgroundAfterMilliseconds: parsed.backgroundAfterMilliseconds,
            resumeAfterMilliseconds: parsed.resumeAfterMilliseconds,
            rotateAfterMilliseconds: parsed.rotateAfterMilliseconds,
            format: parsed.format ?? .text
        )
    }

    static func parseCompatCheckOptions(_ arguments: [String]) throws -> CompatCheckOptions {
        var renderer: EmulatorRendererMode?
        var bluetoothBackend: EmulatorBluetoothBackendMode = .auto
        var format: EmulatorDiagnosticsFormat = .text
        var index = 0

        while index < arguments.count {
            switch arguments[index] {
            case "--renderer":
                guard index + 1 < arguments.count else {
                    throw ExternalRunnerSupportError.usage(usage(executableName: "runner"))
                }
                guard let parsed = EmulatorRendererMode(rawValue: arguments[index + 1]) else {
                    throw ExternalRunnerSupportError.unsupportedRenderer(arguments[index + 1])
                }
                renderer = parsed
                index += 2
            case "--bluetooth-backend":
                guard index + 1 < arguments.count else {
                    throw ExternalRunnerSupportError.usage(usage(executableName: "runner"))
                }
                guard let parsed = EmulatorBluetoothBackendMode(rawValue: arguments[index + 1]) else {
                    throw ExternalRunnerSupportError.invalidBluetoothBackend(arguments[index + 1])
                }
                bluetoothBackend = parsed
                index += 2
            case "--format":
                guard index + 1 < arguments.count else {
                    throw ExternalRunnerSupportError.usage(usage(executableName: "runner"))
                }
                guard let parsed = EmulatorDiagnosticsFormat(rawValue: arguments[index + 1]) else {
                    throw ExternalRunnerSupportError.invalidFormat(arguments[index + 1])
                }
                format = parsed
                index += 2
            default:
                throw ExternalRunnerSupportError.usage(usage(executableName: "runner"))
            }
        }

        return CompatCheckOptions(renderer: renderer, bluetoothBackend: bluetoothBackend, format: format)
    }

    static func parseRendererCommandOptions(
        _ arguments: [String],
        defaultRenderer: EmulatorRendererMode,
        includeFormat: Bool
    ) throws -> ParsedRendererCommandOptions {
        var renderer = defaultRenderer
        var autoCloseMilliseconds: Int32?
        var bluetoothBackend: EmulatorBluetoothBackendMode = .auto
        var devicePreset: EmulatorDevicePreset?
        var orientation: EmulatorDeviceOrientation?
        var backgroundAfterMilliseconds: Int32?
        var resumeAfterMilliseconds: Int32?
        var rotateAfterMilliseconds: Int32?
        var format: EmulatorDiagnosticsFormat?
        var index = 0

        while index < arguments.count {
            switch arguments[index] {
            case "--renderer":
                guard index + 1 < arguments.count else {
                    throw ExternalRunnerSupportError.usage(usage(executableName: "runner"))
                }
                guard let parsed = EmulatorRendererMode(rawValue: arguments[index + 1]) else {
                    throw ExternalRunnerSupportError.unsupportedRenderer(arguments[index + 1])
                }
                renderer = parsed
                index += 2
            case "--autoclose-ms":
                guard index + 1 < arguments.count else {
                    throw ExternalRunnerSupportError.usage(usage(executableName: "runner"))
                }
                guard let parsed = Int32(arguments[index + 1]) else {
                    throw ExternalRunnerSupportError.invalidAutoClose(arguments[index + 1])
                }
                autoCloseMilliseconds = parsed
                index += 2
            case "--bluetooth-backend":
                guard index + 1 < arguments.count else {
                    throw ExternalRunnerSupportError.usage(usage(executableName: "runner"))
                }
                guard let parsed = EmulatorBluetoothBackendMode(rawValue: arguments[index + 1]) else {
                    throw ExternalRunnerSupportError.invalidBluetoothBackend(arguments[index + 1])
                }
                bluetoothBackend = parsed
                index += 2
            case "--device-preset":
                guard index + 1 < arguments.count else {
                    throw ExternalRunnerSupportError.usage(usage(executableName: "runner"))
                }
                guard let parsed = EmulatorDevicePreset(rawValue: arguments[index + 1]) else {
                    throw ExternalRunnerSupportError.invalidDevicePreset(arguments[index + 1])
                }
                devicePreset = parsed
                index += 2
            case "--orientation":
                guard index + 1 < arguments.count else {
                    throw ExternalRunnerSupportError.usage(usage(executableName: "runner"))
                }
                guard let parsed = EmulatorDeviceOrientation(rawValue: arguments[index + 1]) else {
                    throw ExternalRunnerSupportError.invalidOrientation(arguments[index + 1])
                }
                orientation = parsed
                index += 2
            case "--background-after-ms":
                guard index + 1 < arguments.count else {
                    throw ExternalRunnerSupportError.usage(usage(executableName: "runner"))
                }
                guard let parsed = Int32(arguments[index + 1]) else {
                    throw ExternalRunnerSupportError.invalidSimulationDelay(arguments[index + 1])
                }
                backgroundAfterMilliseconds = parsed
                index += 2
            case "--resume-after-ms":
                guard index + 1 < arguments.count else {
                    throw ExternalRunnerSupportError.usage(usage(executableName: "runner"))
                }
                guard let parsed = Int32(arguments[index + 1]) else {
                    throw ExternalRunnerSupportError.invalidSimulationDelay(arguments[index + 1])
                }
                resumeAfterMilliseconds = parsed
                index += 2
            case "--rotate-after-ms":
                guard index + 1 < arguments.count else {
                    throw ExternalRunnerSupportError.usage(usage(executableName: "runner"))
                }
                guard let parsed = Int32(arguments[index + 1]) else {
                    throw ExternalRunnerSupportError.invalidSimulationDelay(arguments[index + 1])
                }
                rotateAfterMilliseconds = parsed
                index += 2
            case "--format":
                guard includeFormat else {
                    throw ExternalRunnerSupportError.usage(usage(executableName: "runner"))
                }
                guard index + 1 < arguments.count else {
                    throw ExternalRunnerSupportError.usage(usage(executableName: "runner"))
                }
                guard let parsed = EmulatorDiagnosticsFormat(rawValue: arguments[index + 1]) else {
                    throw ExternalRunnerSupportError.invalidFormat(arguments[index + 1])
                }
                format = parsed
                index += 2
            default:
                throw ExternalRunnerSupportError.usage(usage(executableName: "runner"))
            }
        }

        return ParsedRendererCommandOptions(
            renderer: renderer,
            autoCloseMilliseconds: autoCloseMilliseconds,
            bluetoothBackend: bluetoothBackend,
            devicePreset: devicePreset,
            orientation: orientation,
            backgroundAfterMilliseconds: backgroundAfterMilliseconds,
            resumeAfterMilliseconds: resumeAfterMilliseconds,
            rotateAfterMilliseconds: rotateAfterMilliseconds,
            format: format
        )
    }
}
