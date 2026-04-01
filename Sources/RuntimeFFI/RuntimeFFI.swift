import CRuntimeShim
import Foundation

public enum FFIHostBridgeError: Error, Equatable {
    case roundTripFailed
}

fileprivate final class CallbackBox {
    let handler: (String) -> Void

    init(_ handler: @escaping (String) -> Void) {
        self.handler = handler
    }
}

public final class FFIHostBridge {
    private var callbackBox: Unmanaged<CallbackBox>?

    public init() {}

    deinit {
        clearCallback()
    }

    public func registerCallback(_ handler: @escaping (String) -> Void) {
        clearCallback()

        let retainedBox = Unmanaged.passRetained(CallbackBox(handler))
        callbackBox = retainedBox
        runtime_shim_register_callback(runtimeFFITrampoline, retainedBox.toOpaque())
    }

    public func clearCallback() {
        runtime_shim_clear_callback()
        callbackBox?.release()
        callbackBox = nil
    }

    public func emit(_ message: String) {
        message.withCString { pointer in
            runtime_shim_emit(pointer)
        }
    }

    public func roundTrip(_ message: String) throws -> String {
        let duplicatedPointer = message.withCString { pointer in
            runtime_shim_roundtrip_string(pointer)
        }

        guard let duplicatedPointer else {
            throw FFIHostBridgeError.roundTripFailed
        }

        defer {
            runtime_shim_free_string(duplicatedPointer)
        }

        return String(cString: duplicatedPointer)
    }

    public func roundTrip(_ bytes: [UInt8]) throws -> [UInt8] {
        guard !bytes.isEmpty else {
            return []
        }

        var outputLength = 0
        let duplicatedPointer = bytes.withUnsafeBufferPointer { buffer in
            runtime_shim_roundtrip_bytes(buffer.baseAddress, buffer.count, &outputLength)
        }

        guard let duplicatedPointer else {
            throw FFIHostBridgeError.roundTripFailed
        }

        defer {
            runtime_shim_free_bytes(duplicatedPointer)
        }

        return Array(UnsafeBufferPointer(start: duplicatedPointer, count: outputLength))
    }
}

private let runtimeFFITrampoline: @convention(c) (UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Void = { message, context in
    guard
        let message,
        let context
    else {
        return
    }

    let callbackBox = Unmanaged<CallbackBox>.fromOpaque(context).takeUnretainedValue()
    callbackBox.handler(String(cString: message))
}
