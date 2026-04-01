import Foundation

public enum EmulatorTextInputEvent: Equatable, Sendable {
    case insertText(String)
    case deleteBackward
    case deleteForward
    case moveCaretLeft
    case moveCaretRight
    case moveCaretToStart
    case moveCaretToEnd
    case submit
}

public enum EmulatorPointerPhase: String, Codable, Equatable, Sendable {
    case down
    case move
    case up
    case cancel
}

public enum EmulatorInputModifier: String, CaseIterable, Codable, Hashable, Sendable {
    case shift
    case control
    case alt
}

public struct EmulatorPointerEvent: Equatable, Sendable {
    public let phase: EmulatorPointerPhase
    public let location: UIPoint
    public let modifiers: Set<EmulatorInputModifier>
    public let timestampMilliseconds: UInt64

    public init(
        phase: EmulatorPointerPhase,
        location: UIPoint,
        modifiers: Set<EmulatorInputModifier> = [],
        timestampMilliseconds: UInt64
    ) {
        self.phase = phase
        self.location = location
        self.modifiers = modifiers
        self.timestampMilliseconds = timestampMilliseconds
    }
}

public enum EmulatorSwipeDirection: String, Codable, Equatable, Sendable {
    case up
    case down
    case left
    case right
}

public enum EmulatorGestureEvent: Equatable, Sendable {
    case dragBegan(start: UIPoint, current: UIPoint)
    case dragChanged(start: UIPoint, current: UIPoint)
    case dragEnded(start: UIPoint, end: UIPoint)
    case swipe(direction: EmulatorSwipeDirection, start: UIPoint, end: UIPoint)
    case longPress(location: UIPoint)
    case pinch(delta: Double, location: UIPoint)
    case rotate(deltaDegrees: Double, location: UIPoint)
}

public protocol EmulatorTextInputAwareAppController: EmulatorAppController {
    @discardableResult
    func handle(textInput: EmulatorTextInputEvent, for fieldID: UITextFieldID) -> Bool
}

public protocol EmulatorPointerAwareAppController: EmulatorAppController {
    @discardableResult
    func handle(pointer: EmulatorPointerEvent, on surfaceID: UIGestureSurfaceID?) -> Bool
}

public protocol EmulatorGestureAwareAppController: EmulatorAppController {
    @discardableResult
    func handle(gesture: EmulatorGestureEvent, on surfaceID: UIGestureSurfaceID) -> Bool
}
