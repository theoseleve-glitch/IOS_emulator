import EmulatorAppSDK
import EmulatorDiagnostics
import Foundation

#if os(Windows)
import RendererWin32

extension ExternalRunnerSupport {
    static func runWin32App(
        manifest: EmulatorAppManifest,
        controllerBox: ControllerBox,
        environmentState: EmulatorRenderEnvironmentState,
        invalidationService: BufferedUIInvalidationService,
        options: RunOptions
    ) throws {
        let initialEnvironment = environmentState.snapshot()
        let presenter = Win32ScreenPresenter(
            documentProvider: { viewport in
                let environment = environmentState.snapshot(viewport: viewport)
                return EmulatorAppControllerBridge.makeDocument(
                    from: controllerBox.controller,
                    environment: environment
                )
            },
            actionHandler: { action in
                _ = controllerBox.controller.handle(action: action)
            },
            inputHandler: { input in
                EmulatorAppControllerBridge.handleInput(input, on: controllerBox.controller)
            },
            textInputHandler: { fieldID, event in
                EmulatorAppControllerBridge.handleTextInput(event, fieldID: fieldID, on: controllerBox.controller)
            },
            pointerHandler: { pointer, surfaceID in
                EmulatorAppControllerBridge.handlePointer(pointer, surfaceID: surfaceID, on: controllerBox.controller)
            },
            gestureHandler: { gesture, surfaceID in
                EmulatorAppControllerBridge.handleGesture(gesture, surfaceID: surfaceID, on: controllerBox.controller)
            }
        )
        _ = try presenter.run(
            options: Win32WindowOptions(
                title: manifest.displayName,
                width: Int32(initialEnvironment.device.viewport.width),
                height: Int32(initialEnvironment.device.viewport.height),
                autoCloseMilliseconds: options.autoCloseMilliseconds ?? 0
            ),
            onWindowReady: { handle in
                invalidationService.bind {
                    handle.requestRedraw()
                }
                scheduleSimulation(
                    controllerBox: controllerBox,
                    environmentState: environmentState,
                    invalidationService: invalidationService,
                    options: options
                )
            }
        )
    }

    static func traceWin32App(
        manifest: EmulatorAppManifest,
        controllerBox: ControllerBox,
        environmentState: EmulatorRenderEnvironmentState,
        invalidationService: BufferedUIInvalidationService,
        options: TraceOptions,
        recorder: EmulatorTraceRecorder
    ) throws {
        let initialEnvironment = environmentState.snapshot()
        let presenter = Win32ScreenPresenter(
            documentProvider: { viewport in
                let environment = environmentState.snapshot(viewport: viewport)
                return EmulatorAppControllerBridge.makeDocument(
                    from: controllerBox.controller,
                    environment: environment
                )
            },
            actionHandler: { action in
                _ = controllerBox.controller.handle(action: action)
            },
            inputHandler: { input in
                EmulatorAppControllerBridge.handleInput(input, on: controllerBox.controller)
            },
            textInputHandler: { fieldID, event in
                EmulatorAppControllerBridge.handleTextInput(event, fieldID: fieldID, on: controllerBox.controller)
            },
            pointerHandler: { pointer, surfaceID in
                EmulatorAppControllerBridge.handlePointer(pointer, surfaceID: surfaceID, on: controllerBox.controller)
            },
            gestureHandler: { gesture, surfaceID in
                EmulatorAppControllerBridge.handleGesture(gesture, surfaceID: surfaceID, on: controllerBox.controller)
            },
            eventHandler: { event in
                recordPresentationEvent(event, recorder: recorder)
            }
        )
        let report = try presenter.run(
            options: Win32WindowOptions(
                title: manifest.displayName,
                width: Int32(initialEnvironment.device.viewport.width),
                height: Int32(initialEnvironment.device.viewport.height),
                autoCloseMilliseconds: options.autoCloseMilliseconds ?? 1500
            ),
            onWindowReady: { handle in
                invalidationService.bind {
                    handle.requestRedraw()
                }
                scheduleTraceInputs(handle: handle, recorder: recorder)
                scheduleSimulation(
                    controllerBox: controllerBox,
                    environmentState: environmentState,
                    invalidationService: invalidationService,
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
            }
        )
        recorder.record(
            category: "renderer",
            name: "runCompleted",
            metadata: [
                "frameCount": "\(report.frameCount)",
                "focusChangeCount": "\(report.focusChangeCount)",
                "keyActivationCount": "\(report.keyActivationCount)",
                "scriptedActionRequested": report.scriptedActionRequested ? "true" : "false",
                "scriptedActionDispatched": report.scriptedActionDispatched ? "true" : "false",
            ]
        )
    }

    static func recordPresentationEvent(
        _ event: Win32PresentationEvent,
        recorder: EmulatorTraceRecorder
    ) {
        switch event {
        case .windowReady:
            recorder.record(category: "window", name: "ready")
        case .frameGenerated(let viewport, let commandCount, let interactionCount):
            recorder.record(
                category: "renderer",
                name: "frameGenerated",
                metadata: [
                    "renderer": "win32",
                    "viewport": "\(viewport.width)x\(viewport.height)",
                    "commands": "\(commandCount)",
                    "interactions": "\(interactionCount)",
                ]
            )
        case .inputReceived(let input):
            recorder.record(category: "input", name: input.rawValue)
        case .textInputReceived(let fieldID, let event):
            recorder.record(
                category: "text",
                name: "input",
                metadata: [
                    "fieldID": fieldID,
                    "event": describeTextInput(event),
                ]
            )
        case .pointerReceived(let surfaceID, let target, let event):
            recorder.record(
                category: "pointer",
                name: event.phase.rawValue,
                metadata: [
                    "surfaceID": surfaceID ?? "none",
                    "target": describeFocusTarget(target),
                    "x": "\(event.location.x)",
                    "y": "\(event.location.y)",
                ]
            )
        case .gestureDispatched(let surfaceID, let event):
            recorder.record(
                category: "gesture",
                name: describeGesture(event),
                metadata: ["surfaceID": surfaceID]
            )
        case .focusChanged(let target):
            recorder.record(category: "focus", name: "changed", metadata: ["target": describeFocusTarget(target)])
        case .actionDispatched(let action, let source):
            recorder.record(category: "action", name: "dispatched", metadata: ["action": action, "source": source])
        }
    }

    static func scheduleTraceInputs(
        handle: Win32RedrawHandle,
        recorder: EmulatorTraceRecorder
    ) {
        let schedule: [(milliseconds: Int32, key: Win32VirtualKey, shift: Bool)] = [
            (220, .tab, false),
            (440, .enter, false),
            (760, .escape, false),
        ]

        for item in schedule {
            DispatchQueue.global(qos: .userInitiated).asyncAfter(
                deadline: .now() + .milliseconds(Int(item.milliseconds))
            ) {
                recorder.record(
                    category: "input",
                    name: "scheduledKey",
                    metadata: [
                        "key": "\(item.key.rawValue)",
                        "shift": item.shift ? "true" : "false",
                    ]
                )
                handle.sendKey(item.key, shiftDown: item.shift)
            }
        }
    }

    static func describeFocusTarget(_ target: FocusableTarget?) -> String {
        guard let target else {
            return "none"
        }
        switch target {
        case .action(let action):
            return "action:\(action)"
        case .textField(let fieldID):
            return "textField:\(fieldID)"
        case .gestureSurface(let surfaceID):
            return "gestureSurface:\(surfaceID)"
        }
    }

    static func describeTextInput(_ event: EmulatorTextInputEvent) -> String {
        switch event {
        case .insertText(let value):
            return "insert:\(value)"
        case .deleteBackward:
            return "deleteBackward"
        case .deleteForward:
            return "deleteForward"
        case .moveCaretLeft:
            return "moveCaretLeft"
        case .moveCaretRight:
            return "moveCaretRight"
        case .moveCaretToStart:
            return "moveCaretToStart"
        case .moveCaretToEnd:
            return "moveCaretToEnd"
        case .submit:
            return "submit"
        }
    }

    static func describeGesture(_ event: EmulatorGestureEvent) -> String {
        switch event {
        case .dragBegan:
            return "dragBegan"
        case .dragChanged:
            return "dragChanged"
        case .dragEnded:
            return "dragEnded"
        case .swipe(let direction, _, _):
            return "swipe:\(direction.rawValue)"
        case .longPress:
            return "longPress"
        case .pinch:
            return "pinch"
        case .rotate:
            return "rotate"
        }
    }
}
#else
extension ExternalRunnerSupport {
    static func runWin32App(
        manifest: EmulatorAppManifest,
        controllerBox: ControllerBox,
        environmentState: EmulatorRenderEnvironmentState,
        invalidationService: BufferedUIInvalidationService,
        options: RunOptions
    ) throws {
        _ = manifest
        _ = controllerBox
        _ = environmentState
        _ = invalidationService
        _ = options
        throw ExternalRunnerSupportError.unsupportedRenderer(EmulatorRendererMode.win32.rawValue)
    }

    static func traceWin32App(
        manifest: EmulatorAppManifest,
        controllerBox: ControllerBox,
        environmentState: EmulatorRenderEnvironmentState,
        invalidationService: BufferedUIInvalidationService,
        options: TraceOptions,
        recorder: EmulatorTraceRecorder
    ) throws {
        _ = manifest
        _ = controllerBox
        _ = environmentState
        _ = invalidationService
        _ = options
        _ = recorder
        throw ExternalRunnerSupportError.unsupportedRenderer(EmulatorRendererMode.win32.rawValue)
    }
}
#endif
