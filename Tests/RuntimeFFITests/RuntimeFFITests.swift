import XCTest
@testable import RuntimeFFI

final class RuntimeFFITests: XCTestCase {
    func testRoundTripReturnsTheOriginalString() throws {
        let bridge = FFIHostBridge()

        XCTAssertEqual(try bridge.roundTrip("ffi hello"), "ffi hello")
    }

    func testRoundTripReturnsTheOriginalBytes() throws {
        let bridge = FFIHostBridge()
        let payload: [UInt8] = [0, 3, 9, 27, 81, 255]

        XCTAssertEqual(try bridge.roundTrip(payload), payload)
    }

    func testCallbackRegistrationReceivesEmittedMessage() {
        let bridge = FFIHostBridge()
        var messages: [String] = []

        bridge.registerCallback { message in
            messages.append(message)
        }
        bridge.emit("ffi ping")
        bridge.clearCallback()

        XCTAssertEqual(messages, ["ffi ping"])
    }

    func testCallbackRemainsSafeAfterMixedStringAndByteOperations() throws {
        let bridge = FFIHostBridge()
        var messages: [String] = []

        bridge.registerCallback { message in
            messages.append(message)
        }

        XCTAssertEqual(try bridge.roundTrip("ffi hello"), "ffi hello")
        XCTAssertEqual(try bridge.roundTrip([1, 2, 3, 4]), [1, 2, 3, 4])
        bridge.emit("ffi ping")
        bridge.clearCallback()
        XCTAssertEqual(try bridge.roundTrip([5, 6]), [5, 6])

        XCTAssertEqual(messages, ["ffi ping"])
    }
}
