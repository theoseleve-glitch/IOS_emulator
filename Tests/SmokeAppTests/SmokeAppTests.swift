import XCTest
@testable import SmokeApp
import EmulatorAppSDK

final class SmokeAppTests: XCTestCase {
    func testDemoStateNavigatesToSessionsAndBack() {
        let state = SmokeDemoState()

        XCTAssertEqual(state.currentRoute, .dashboard)
        XCTAssertTrue(state.handle(action: SmokeDemoAction.openSessions))
        XCTAssertEqual(state.currentRoute, .sessions)
        XCTAssertTrue(state.handle(action: SmokeDemoAction.back))
        XCTAssertEqual(state.currentRoute, .dashboard)
    }

    func testSelectingSessionPushesDetailAndTracksSelection() {
        let state = SmokeDemoState()

        XCTAssertTrue(state.handle(action: SmokeDemoAction.openSessions))
        XCTAssertTrue(state.handle(action: SmokeDemoAction.openSession("session-02")))

        XCTAssertEqual(state.currentRoute, .sessionDetail("session-02"))
        XCTAssertEqual(state.selectedSessionID, "session-02")
    }

    func testTelemetryAndConnectionActionsMutateState() {
        let state = SmokeDemoState()

        XCTAssertTrue(state.handle(action: SmokeDemoAction.increaseSpeed))
        XCTAssertEqual(state.speed, 140, accuracy: 0.1)
        XCTAssertTrue(state.handle(action: SmokeDemoAction.toggleConnection))
        XCTAssertFalse(state.isConnected)
        XCTAssertTrue(state.handle(action: SmokeDemoAction.toggleRecording))
        XCTAssertTrue(state.isRecording)
    }

    func testInputLabHandlesTextPointerAndGestures() {
        let state = SmokeDemoState()

        XCTAssertTrue(state.handle(action: SmokeDemoAction.openInputLab))
        XCTAssertEqual(state.currentRoute, .inputLab)

        XCTAssertTrue(state.handle(textInput: .insertText("GO"), for: "demo.input.field"))
        XCTAssertTrue(state.handle(textInput: .submit, for: "demo.input.field"))
        XCTAssertEqual(state.inputText, "GO")
        XCTAssertEqual(state.submitCount, 1)

        XCTAssertTrue(state.handle(pointer: EmulatorPointerEvent(phase: .move, location: UIPoint(x: 42, y: 18), modifiers: [], timestampMilliseconds: 10), on: "demo.gesture.surface"))
        XCTAssertEqual(state.lastPointerLabel, "move@42,18")

        XCTAssertTrue(state.handle(gesture: .dragChanged(start: UIPoint(x: 10, y: 10), current: UIPoint(x: 34, y: 46)), on: "demo.gesture.surface"))
        XCTAssertEqual(state.dragOffset.x, 24, accuracy: 0.1)
        XCTAssertEqual(state.dragOffset.y, 36, accuracy: 0.1)

        XCTAssertTrue(state.handle(gesture: .longPress(location: UIPoint(x: 18, y: 18)), on: "demo.gesture.surface"))
        XCTAssertEqual(state.longPressCount, 1)

        XCTAssertTrue(state.handle(gesture: .pinch(delta: 1.0, location: UIPoint(x: 18, y: 18)), on: "demo.gesture.surface"))
        XCTAssertGreaterThan(state.pinchValue, 1.0)

        XCTAssertTrue(state.handle(gesture: .rotate(deltaDegrees: 8, location: UIPoint(x: 18, y: 18)), on: "demo.gesture.surface"))
        XCTAssertEqual(state.rotationValue, 8, accuracy: 0.1)
    }
}
