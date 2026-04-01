import Foundation

public protocol EmulatorUIInvalidationService: Sendable {
    func requestRedraw()
}

public final class NoopUIInvalidationService: EmulatorUIInvalidationService, @unchecked Sendable {
    public init() {}
    public func requestRedraw() {}
}

public final class BufferedUIInvalidationService: EmulatorUIInvalidationService, @unchecked Sendable {
    private let lock = NSLock()
    private var callback: (() -> Void)?
    private var observer: (@Sendable () -> Void)?
    private var hasPendingRequest = false

    public init() {}

    public func bind(callback: @escaping () -> Void) {
        let shouldFlush: Bool
        lock.lock()
        self.callback = callback
        shouldFlush = hasPendingRequest
        hasPendingRequest = false
        lock.unlock()

        if shouldFlush {
            callback()
        }
    }

    public func setObserver(_ observer: (@Sendable () -> Void)?) {
        lock.lock()
        self.observer = observer
        lock.unlock()
    }

    public func requestRedraw() {
        let currentCallback: (() -> Void)?
        let currentObserver: (@Sendable () -> Void)?
        lock.lock()
        currentCallback = callback
        currentObserver = observer
        if currentCallback == nil {
            hasPendingRequest = true
        }
        lock.unlock()

        currentObserver?()
        currentCallback?()
    }
}
