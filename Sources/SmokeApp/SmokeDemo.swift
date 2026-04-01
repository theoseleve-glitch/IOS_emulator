import EmulatorAppSDK
import Foundation
import RendererCore

public enum SmokeDemoRoute: Hashable, Sendable {
    case dashboard
    case sessions
    case controls
    case inputLab
    case sessionDetail(String)
}

public enum SmokeDemoAction {
    public static let back = "demo.nav.back"
    public static let openSessions = "demo.nav.sessions"
    public static let openControls = "demo.nav.controls"
    public static let openDashboard = "demo.nav.dashboard"
    public static let openInputLab = "demo.nav.inputLab"
    public static let increaseSpeed = "demo.telemetry.increase"
    public static let decreaseSpeed = "demo.telemetry.decrease"
    public static let toggleConnection = "demo.connection.toggle"
    public static let toggleRecording = "demo.recording.toggle"
    public static let submitInput = "demo.input.submit"

    public static func openSession(_ sessionID: String) -> UIActionID {
        "demo.session.open:\(sessionID)"
    }
}

public final class SmokeDemoState: EmulatorRenderEnvironmentAwareAppController, EmulatorInputAwareAppController, EmulatorLifecycleEventAwareAppController, EmulatorTextInputAwareAppController, EmulatorPointerAwareAppController, EmulatorGestureAwareAppController, @unchecked Sendable {
    public private(set) var navigation = NavigationPathState(root: SmokeDemoRoute.dashboard)
    public private(set) var selection = ListSelectionState<String>()
    public private(set) var speed = 128.0
    public private(set) var isConnected = true
    public private(set) var isRecording = false
    public private(set) var lifecycleLabel = "Foreground"
    public private(set) var lastEnvironment = SmokeDemoState.defaultEnvironment
    public private(set) var launchEventCount = 0
    public private(set) var foregroundEventCount = 0
    public private(set) var backgroundEventCount = 0
    public private(set) var rotationEventCount = 0
    public private(set) var inputText = ""
    public private(set) var inputCaretIndex = 0
    public private(set) var submitCount = 0
    public private(set) var lastPointerLabel = "idle"
    public private(set) var dragOffset = UIPoint(x: 0, y: 0)
    public private(set) var swipeLabel = "none"
    public private(set) var longPressCount = 0
    public private(set) var pinchValue = 1.0
    public private(set) var rotationValue = 0.0

    private let sessionSummaries: [SessionSummary] = [
        SessionSummary(id: "session-01", title: "Session 01", subtitle: "Paul Ricard | Dry | 12 laps", averageSpeed: 118),
        SessionSummary(id: "session-02", title: "Session 02", subtitle: "Monza | Mixed grip | 9 laps", averageSpeed: 133),
        SessionSummary(id: "session-03", title: "Session 03", subtitle: "Spa | Cool down | 5 laps", averageSpeed: 96),
    ]

    public init() {}

    public var currentRoute: SmokeDemoRoute {
        navigation.current
    }

    public var selectedSessionID: String? {
        selection.selectedID
    }

    @discardableResult
    public func handle(action: UIActionID) -> Bool {
        switch action {
        case SmokeDemoAction.back:
            _ = navigation.pop()
            return true
        case SmokeDemoAction.openSessions:
            navigation.push(.sessions)
            return true
        case SmokeDemoAction.openControls:
            navigation.push(.controls)
            return true
        case SmokeDemoAction.openDashboard:
            navigation.popToRoot()
            return true
        case SmokeDemoAction.openInputLab:
            navigation.push(.inputLab)
            return true
        case SmokeDemoAction.increaseSpeed:
            speed = min(220, speed + 12)
            return true
        case SmokeDemoAction.decreaseSpeed:
            speed = max(0, speed - 12)
            return true
        case SmokeDemoAction.toggleConnection:
            isConnected.toggle()
            return true
        case SmokeDemoAction.toggleRecording:
            isRecording.toggle()
            return true
        case SmokeDemoAction.submitInput:
            submitCount += 1
            lifecycleLabel = "Submitted note"
            return true
        default:
            guard action.hasPrefix("demo.session.open:") else {
                return false
            }

            let sessionID = String(action.dropFirst("demo.session.open:".count))
            selection.select(sessionID)
            navigation.push(.sessionDetail(sessionID))
            return true
        }
    }

    public func makeDocument() -> ScreenDocument {
        makeDocument(environment: lastEnvironment)
    }

    public func makeDocument(environment: EmulatorRenderEnvironment) -> ScreenDocument {
        lastEnvironment = environment
        return UI.screen(
            title: "lap_mobile smoke",
            rootLayoutMode: .safeArea,
            safeAreaInsets: environment.device.safeAreaInsets
        ) {
            UI.navigationStack(
                title: routeTitle(for: navigation.current),
                canGoBack: navigation.canGoBack,
                backAction: navigation.canGoBack ? SmokeDemoAction.back : nil
            ) {
                routeBody(for: navigation.current, environment: environment)
            }
        }
    }

    @discardableResult
    public func handle(input: EmulatorInputEvent) -> Bool {
        switch input {
        case .back:
            guard navigation.canGoBack else {
                return false
            }
            _ = navigation.pop()
            return true
        default:
            return false
        }
    }

    public func handle(lifecycleEvent: EmulatorLifecycleEvent) {
        switch lifecycleEvent {
        case .didLaunch:
            lifecycleLabel = "Launched"
            launchEventCount += 1
        case .didEnterForeground:
            lifecycleLabel = "Foreground"
            foregroundEventCount += 1
        case .didEnterBackground:
            lifecycleLabel = "Background"
            backgroundEventCount += 1
        case .willTerminate:
            lifecycleLabel = "Terminating"
        case .deviceEnvironmentChanged(let deviceEnvironment):
            lifecycleLabel = "Rotated to \(deviceEnvironment.orientation.rawValue)"
            rotationEventCount += 1
            lastEnvironment = EmulatorRenderEnvironment(
                device: deviceEnvironment,
                rendererMode: lastEnvironment.rendererMode,
                locale: lastEnvironment.locale
            )
        }
    }

    @discardableResult
    public func handle(textInput: EmulatorTextInputEvent, for fieldID: UITextFieldID) -> Bool {
        guard fieldID == "demo.input.field" else {
            return false
        }

        switch textInput {
        case .insertText(let value):
            let clamped = min(inputCaretIndex, inputText.count)
            let prefix = String(inputText.prefix(clamped))
            let suffix = String(inputText.dropFirst(clamped))
            inputText = prefix + value + suffix
            inputCaretIndex = clamped + value.count
        case .deleteBackward:
            guard inputCaretIndex > 0 else { return true }
            let removeIndex = inputText.index(inputText.startIndex, offsetBy: inputCaretIndex - 1)
            inputText.remove(at: removeIndex)
            inputCaretIndex -= 1
        case .deleteForward:
            guard inputCaretIndex < inputText.count else { return true }
            let removeIndex = inputText.index(inputText.startIndex, offsetBy: inputCaretIndex)
            inputText.remove(at: removeIndex)
        case .moveCaretLeft:
            inputCaretIndex = max(0, inputCaretIndex - 1)
        case .moveCaretRight:
            inputCaretIndex = min(inputText.count, inputCaretIndex + 1)
        case .moveCaretToStart:
            inputCaretIndex = 0
        case .moveCaretToEnd:
            inputCaretIndex = inputText.count
        case .submit:
            _ = handle(action: SmokeDemoAction.submitInput)
        }

        return true
    }

    @discardableResult
    public func handle(pointer: EmulatorPointerEvent, on surfaceID: UIGestureSurfaceID?) -> Bool {
        lastPointerLabel = "\(pointer.phase.rawValue)@\(Int(pointer.location.x)),\(Int(pointer.location.y))"
        return surfaceID != nil
    }

    @discardableResult
    public func handle(gesture: EmulatorGestureEvent, on surfaceID: UIGestureSurfaceID) -> Bool {
        guard surfaceID == "demo.gesture.surface" else {
            return false
        }

        switch gesture {
        case .dragBegan(let start, let current), .dragChanged(let start, let current):
            dragOffset = UIPoint(x: current.x - start.x, y: current.y - start.y)
        case .dragEnded(let start, let end):
            dragOffset = UIPoint(x: end.x - start.x, y: end.y - start.y)
        case .swipe(let direction, _, _):
            swipeLabel = direction.rawValue
        case .longPress:
            longPressCount += 1
        case .pinch(let delta, _):
            pinchValue = max(0.2, min(3.0, pinchValue + (delta * 0.2)))
        case .rotate(let deltaDegrees, _):
            rotationValue += deltaDegrees
        }

        return true
    }

    private func routeTitle(for route: SmokeDemoRoute) -> String {
        switch route {
        case .dashboard:
            return "Dashboard"
        case .sessions:
            return "Sessions"
        case .controls:
            return "Controls"
        case .inputLab:
            return "Input Lab"
        case .sessionDetail(let identifier):
            return sessionSummaries.first(where: { $0.id == identifier })?.title ?? "Session"
        }
    }

    private func routeBody(for route: SmokeDemoRoute, environment: EmulatorRenderEnvironment) -> RenderNode {
        switch route {
        case .dashboard:
            return dashboardBody(environment: environment)
        case .sessions:
            return sessionsBody(environment: environment)
        case .controls:
            return controlsBody(environment: environment)
        case .inputLab:
            return inputLabBody(environment: environment)
        case .sessionDetail(let identifier):
            return sessionDetailBody(identifier: identifier, environment: environment)
        }
    }

    private func dashboardBody(environment: EmulatorRenderEnvironment) -> RenderNode {
        let headerPanel: RenderNode
        switch environment.device.orientation {
        case .portrait:
            headerPanel = UI.vStack(spacing: 12) {
                statusPanel(environment: environment)
                UI.gauge(
                    label: "Speed",
                    value: speed,
                    range: 0...220,
                    unit: "km/h",
                    accentColor: isRecording ? .accentStrong : .accent
                )
            }
        case .landscape:
            headerPanel = UI.hStack(spacing: 12) {
                statusPanel(environment: environment)
                UI.frame(
                    fillsWidth: true,
                    alignment: .leading,
                    UI.gauge(
                        label: "Speed",
                        value: speed,
                        range: 0...220,
                        unit: "km/h",
                        accentColor: isRecording ? .accentStrong : .accent
                    )
                )
            }
        }

        return UI.padding(.uniform(20), UI.vStack(spacing: 18) {
            UI.text("SwiftUI-inspired Windows renderer", style: .headline)
            UI.text(connectionSummary, style: .caption)
            headerPanel
            UI.hStack(spacing: 12) {
                UI.frame(fillsWidth: true, alignment: .center, UI.button("Brake", action: SmokeDemoAction.decreaseSpeed, style: .secondary))
                UI.frame(fillsWidth: true, alignment: .center, UI.button("Boost", action: SmokeDemoAction.increaseSpeed))
            }
            UI.hStack(spacing: 12) {
                UI.text("Lap 01", style: .body)
                UI.spacer(minLength: 8)
                UI.text(isRecording ? "Mode: Recording" : "Mode: Preview", style: .caption)
            }
            UI.divider()
            UI.hStack(spacing: 12) {
                UI.frame(fillsWidth: true, alignment: .center, UI.button("Sessions", action: SmokeDemoAction.openSessions, style: .secondary))
                UI.frame(fillsWidth: true, alignment: .center, UI.button("Controls", action: SmokeDemoAction.openControls))
            }
            UI.frame(fillsWidth: true, alignment: .center, UI.button("Input Lab", action: SmokeDemoAction.openInputLab, style: .plain))
        })
    }

    private func sessionsBody(environment: EmulatorRenderEnvironment) -> RenderNode {
        UI.padding(.uniform(20), UI.vStack(spacing: 18) {
            statusBanner(environment: environment)
            UI.text("Recorded sessions", style: .headline)
            UI.text("Use keyboard focus or pointer hits to drill into a retained navigation view.", style: .caption)
            UI.list(
                items: sessionSummaries.map {
                    ListItemModel(
                        id: $0.id,
                        title: $0.title,
                        subtitle: $0.subtitle,
                        action: SmokeDemoAction.openSession($0.id)
                    )
                },
                selectedID: selectedSessionID
            )
            UI.hStack(spacing: 12) {
                UI.frame(fillsWidth: true, alignment: .center, UI.button("Back To Dashboard", action: SmokeDemoAction.openDashboard, style: .plain))
                UI.frame(fillsWidth: true, alignment: .center, UI.button("Input Lab", action: SmokeDemoAction.openInputLab, style: .secondary))
            }
        })
    }

    private func controlsBody(environment: EmulatorRenderEnvironment) -> RenderNode {
        UI.padding(.uniform(20), UI.vStack(spacing: 18) {
            statusBanner(environment: environment)
            UI.text("Interaction sandbox", style: .headline)
            UI.text("This screen exercises buttons, focus rings, redraws, and lifecycle-aware status text.", style: .caption)
            UI.hStack(spacing: 12) {
                UI.frame(
                    fillsWidth: true,
                    alignment: .center,
                    UI.button(
                        isConnected ? "Disconnect" : "Connect",
                        action: SmokeDemoAction.toggleConnection,
                        style: isConnected ? .secondary : .primary
                    )
                )
                UI.frame(
                    fillsWidth: true,
                    alignment: .center,
                    UI.button(
                        isRecording ? "Stop Session" : "Start Session",
                        action: SmokeDemoAction.toggleRecording,
                        style: .primary
                    )
                )
            }
            UI.gauge(
                label: "Stability",
                value: isConnected ? (isRecording ? 88 : 72) : 24,
                range: 0...100,
                unit: "%",
                accentColor: isConnected ? .success : .warning
            )
            UI.hStack(spacing: 10) {
                UI.text("Transport", style: .body)
                UI.spacer(minLength: 8)
                UI.text(isConnected ? "Linked" : "Offline", style: .caption)
            }
            UI.divider()
            UI.hStack(spacing: 12) {
                UI.frame(fillsWidth: true, alignment: .center, UI.button("Show Sessions", action: SmokeDemoAction.openSessions, style: .plain))
                UI.frame(fillsWidth: true, alignment: .center, UI.button("Input Lab", action: SmokeDemoAction.openInputLab, style: .secondary))
            }
        })
    }

    private func inputLabBody(environment: EmulatorRenderEnvironment) -> RenderNode {
        UI.padding(.uniform(20), UI.vStack(spacing: 18) {
            statusBanner(environment: environment)
            UI.text("Advanced input lab", style: .headline)
            UI.text("Type into the field, then drag, long-press, pinch, and rotate inside the gesture surface.", style: .caption)
            UI.textField(
                id: "demo.input.field",
                text: inputText,
                placeholder: "Type telemetry note",
                caretIndex: inputCaretIndex,
                submitAction: SmokeDemoAction.submitInput
            )
            UI.text("Submit count: \(submitCount)", style: .caption)
            UI.gestureSurface(
                id: "demo.gesture.surface",
                UI.frame(
                    fillsWidth: true,
                    alignment: .leading,
                    UI.padding(.uniform(16), UI.vStack(spacing: 10) {
                        UI.text("Gesture pad", style: .headline)
                        UI.text("Pointer: \(lastPointerLabel)", style: .caption)
                        UI.text("Drag offset: \(Int(dragOffset.x)), \(Int(dragOffset.y))", style: .caption)
                        UI.text("Swipe: \(swipeLabel)", style: .caption)
                        UI.text("Long press count: \(longPressCount)", style: .caption)
                        UI.text("Pinch: \(String(format: "%.2f", pinchValue))", style: .caption)
                        UI.text("Rotate: \(String(format: "%.1f", rotationValue))°", style: .caption)
                    })
                )
            )
            UI.hStack(spacing: 12) {
                UI.frame(fillsWidth: true, alignment: .center, UI.button("Controls", action: SmokeDemoAction.openControls, style: .secondary))
                UI.frame(fillsWidth: true, alignment: .center, UI.button("Dashboard", action: SmokeDemoAction.openDashboard, style: .plain))
            }
        })
    }

    private func sessionDetailBody(identifier: String, environment: EmulatorRenderEnvironment) -> RenderNode {
        let session = sessionSummaries.first(where: { $0.id == identifier }) ?? sessionSummaries[0]
        return UI.padding(.uniform(20), UI.vStack(spacing: 18) {
            statusBanner(environment: environment)
            UI.text(session.title, style: .title)
            UI.text(session.subtitle, style: .caption)
            UI.gauge(
                label: "Average speed",
                value: session.averageSpeed,
                range: 0...220,
                unit: "km/h",
                accentColor: .accentStrong
            )
            UI.text("Selection persists through the navigation stack so the sessions list still knows which row is active.", style: .body)
            UI.hStack(spacing: 12) {
                UI.frame(fillsWidth: true, alignment: .center, UI.button("Controls", action: SmokeDemoAction.openControls, style: .secondary))
                UI.frame(fillsWidth: true, alignment: .center, UI.button("Dashboard", action: SmokeDemoAction.openDashboard, style: .plain))
            }
        })
    }

    private var connectionSummary: String {
        let transport = isConnected ? "Connected" : "Searching"
        let mode = isRecording ? "Recording" : "Preview"
        return "Transport: \(transport) | Mode: \(mode)"
    }

    private func statusPanel(environment: EmulatorRenderEnvironment) -> RenderNode {
        UI.vStack(spacing: 8) {
            statusBanner(environment: environment)
            UI.text("Preset: \(environment.device.preset.rawValue)", style: .caption)
            UI.text("Orientation: \(environment.device.orientation.rawValue)", style: .caption)
        }
    }

    private func statusBanner(environment: EmulatorRenderEnvironment) -> RenderNode {
        UI.frame(
            fillsWidth: true,
            alignment: .leading,
            UI.padding(
                UIInsets(top: 10, leading: 12, bottom: 10, trailing: 12),
                UI.text(
                    "State: \(lifecycleLabel) | \(environment.rendererMode.rawValue) | \(environment.device.viewport.width)x\(environment.device.viewport.height)",
                    style: .caption
                )
            )
        )
    }

    private static let defaultEnvironment = EmulatorRenderEnvironment(
        device: EmulatorDeviceEnvironment(
            preset: .phoneTall,
            orientation: .portrait,
            viewport: .graphicalPhone,
            scale: 2.0,
            safeAreaInsets: .zero
        ),
        rendererMode: .win32,
        locale: "en"
    )
}

private struct SessionSummary {
    let id: String
    let title: String
    let subtitle: String
    let averageSpeed: Double
}
