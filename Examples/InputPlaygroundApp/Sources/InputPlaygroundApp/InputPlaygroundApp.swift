import EmulatorAppSDK
import Foundation

public enum InputPlaygroundRegistration: EmulatorAppRegistration {
    public static let manifest = EmulatorAppManifest(
        appID: "example.input-playground",
        displayName: "Input Playground",
        defaultViewport: .graphicalPhone,
        defaultDevicePreset: .phoneTall,
        defaultOrientation: .portrait,
        supportedRenderers: [.text, .win32]
    )

    public static func makeController() -> any EmulatorAppController {
        InputPlaygroundController()
    }
}

public final class InputPlaygroundController: EmulatorRenderEnvironmentAwareAppController, EmulatorTextInputAwareAppController, EmulatorPointerAwareAppController, EmulatorGestureAwareAppController, EmulatorInputAwareAppController, @unchecked Sendable {
    private var note = ""
    private var caretIndex = 0
    private var submitCount = 0
    private var lastPointer = "idle"
    private var dragOffset = UIPoint(x: 0, y: 0)
    private var swipeLabel = "none"
    private var longPressCount = 0
    private var pinchValue = 1.0
    private var rotationValue = 0.0

    public init() {}

    public func makeDocument() -> ScreenDocument {
        makeDocument(environment: InputPlaygroundRegistration.manifest.resolvedRenderEnvironment(rendererMode: .text))
    }

    public func makeDocument(environment: EmulatorRenderEnvironment) -> ScreenDocument {
        UI.screen(
            title: "Input Playground",
            backgroundColor: .canvas,
            rootLayoutMode: .safeArea,
            safeAreaInsets: environment.device.safeAreaInsets
        ) {
            UI.padding(.uniform(20), UI.vStack(spacing: 18) {
                UI.text("Input Playground", style: .headline)
                UI.text("Single-line text and synthetic gestures for the simplified emulator host.", style: .caption)
                UI.textField(
                    id: "playground.note",
                    text: note,
                    placeholder: "Type a short note",
                    caretIndex: caretIndex,
                    submitAction: "playground.submit"
                )
                UI.text("Submit count: \(submitCount)", style: .caption)
                UI.gestureSurface(
                    id: "playground.surface",
                    UI.frame(
                        fillsWidth: true,
                        alignment: .leading,
                        UI.padding(.uniform(16), UI.vStack(spacing: 10) {
                            UI.text("Gesture surface", style: .headline)
                            UI.text("Pointer: \(lastPointer)", style: .caption)
                            UI.text("Drag: \(Int(dragOffset.x)), \(Int(dragOffset.y))", style: .caption)
                            UI.text("Swipe: \(swipeLabel)", style: .caption)
                            UI.text("Long press: \(longPressCount)", style: .caption)
                            UI.text("Pinch: \(String(format: "%.2f", pinchValue))", style: .caption)
                            UI.text("Rotate: \(String(format: "%.1f", rotationValue))°", style: .caption)
                        })
                    )
                )
            })
        }
    }

    @discardableResult
    public func handle(action: UIActionID) -> Bool {
        guard action == "playground.submit" else {
            return false
        }
        submitCount += 1
        return true
    }

    @discardableResult
    public func handle(textInput: EmulatorTextInputEvent, for fieldID: UITextFieldID) -> Bool {
        guard fieldID == "playground.note" else {
            return false
        }

        switch textInput {
        case .insertText(let value):
            let clamped = min(caretIndex, note.count)
            let prefix = String(note.prefix(clamped))
            let suffix = String(note.dropFirst(clamped))
            note = prefix + value + suffix
            caretIndex = clamped + value.count
        case .deleteBackward:
            guard caretIndex > 0 else { return true }
            let index = note.index(note.startIndex, offsetBy: caretIndex - 1)
            note.remove(at: index)
            caretIndex -= 1
        case .deleteForward:
            guard caretIndex < note.count else { return true }
            let index = note.index(note.startIndex, offsetBy: caretIndex)
            note.remove(at: index)
        case .moveCaretLeft:
            caretIndex = max(0, caretIndex - 1)
        case .moveCaretRight:
            caretIndex = min(note.count, caretIndex + 1)
        case .moveCaretToStart:
            caretIndex = 0
        case .moveCaretToEnd:
            caretIndex = note.count
        case .submit:
            _ = handle(action: "playground.submit")
        }

        return true
    }

    @discardableResult
    public func handle(pointer: EmulatorPointerEvent, on surfaceID: UIGestureSurfaceID?) -> Bool {
        lastPointer = "\(pointer.phase.rawValue)@\(Int(pointer.location.x)),\(Int(pointer.location.y))"
        return surfaceID != nil
    }

    @discardableResult
    public func handle(gesture: EmulatorGestureEvent, on surfaceID: UIGestureSurfaceID) -> Bool {
        guard surfaceID == "playground.surface" else {
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

    @discardableResult
    public func handle(input: EmulatorInputEvent) -> Bool {
        input == .back
    }
}
