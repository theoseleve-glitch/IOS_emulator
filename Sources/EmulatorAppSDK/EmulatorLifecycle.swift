import Foundation

public protocol EmulatorLifecycleAwareAppController: EmulatorAppController {
    func start() throws
    func stop()
}

public enum EmulatorLifecycleControllerRunner {
    public static func startIfNeeded(_ controller: any EmulatorAppController) throws {
        if let lifecycleAware = controller as? any EmulatorLifecycleAwareAppController {
            try lifecycleAware.start()
        }
    }

    public static func stopIfNeeded(_ controller: any EmulatorAppController) {
        if let lifecycleAware = controller as? any EmulatorLifecycleAwareAppController {
            lifecycleAware.stop()
        }
    }

    public static func emitIfNeeded(
        _ event: EmulatorLifecycleEvent,
        on controller: any EmulatorAppController
    ) {
        EmulatorAppControllerBridge.handleLifecycleEvent(event, on: controller)
    }
}
