import CObjCExperimentShim
import Foundation
import RuntimeCore

public enum ObjCExperimentBackendMode: String, CaseIterable, Sendable {
    case auto
    case embedded
    case libobjc2
}

public struct ObjCExperimentInstanceID: Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public enum ObjCExperimentError: Error, Equatable, CustomStringConvertible {
    case initializationFailed
    case backendConfigurationFailed(String)
    case backendUnavailable(String)
    case selectorRegistrationFailed(String)
    case classRegistrationFailed(String)
    case classNotFound(String)
    case instanceAllocationFailed(String)
    case instanceNotFound
    case messageSendFailed(String)
    case autoreleasePoolFailed

    public var description: String {
        switch self {
        case .initializationFailed:
            return "Objective-C experiment runtime failed to initialize."
        case .backendConfigurationFailed(let backend):
            return "Objective-C experiment backend configuration failed for '\(backend)'."
        case .backendUnavailable(let backend):
            return "Objective-C experiment backend '\(backend)' is unavailable."
        case .selectorRegistrationFailed(let name):
            return "Selector registration failed for '\(name)'."
        case .classRegistrationFailed(let name):
            return "Class registration failed for '\(name)'."
        case .classNotFound(let name):
            return "Class '\(name)' is not registered."
        case .instanceAllocationFailed(let name):
            return "Instance allocation failed for class '\(name)'."
        case .instanceNotFound:
            return "Objective-C experiment instance was not found."
        case .messageSendFailed(let selector):
            return "Zero-argument message send failed for selector '\(selector)'."
        case .autoreleasePoolFailed:
            return "Objective-C experiment autorelease pool operation failed."
        }
    }
}

public struct ObjCExperimentReport: Equatable, Sendable {
    public let backend: String
    public let className: String
    public let selector: String
    public let response: String
}

public struct ObjCCompatibilityReport: Equatable, Sendable {
    public let backend: String
    public let className: String
    public let selector: String
    public let response: String
    public let classLookupSucceeded: Bool
    public let respondsToSelector: Bool
    public let instanceClassName: String
    public let integerValue: Int32
    public let echoedValue: String
    public let autoreleasePoolRoundTrip: Bool
}

public final class RuntimeObjCExperiment {
    private struct ClassMetadata {
        let primarySelector: String
        let response: String
        let superclassName: String?
    }

    private struct InstanceMetadata {
        let className: String
        var integerValue: Int32
    }

    private let preferredBackend: ObjCExperimentBackendMode
    private var initialized = false
    private var selectorHandles: [String: UnsafeMutableRawPointer] = [:]
    private var classHandles: [String: UnsafeMutableRawPointer] = [:]
    private var instanceHandles: [ObjCExperimentInstanceID: UnsafeMutableRawPointer] = [:]
    private var retainCounts: [ObjCExperimentInstanceID: Int] = [:]
    private var classMetadata: [String: ClassMetadata] = [:]
    private var instanceMetadata: [ObjCExperimentInstanceID: InstanceMetadata] = [:]

    public init(preferredBackend: ObjCExperimentBackendMode = .auto) {
        self.preferredBackend = preferredBackend
    }

    deinit {
        for (instanceID, instance) in instanceHandles {
            let retainCount = retainCounts[instanceID] ?? 1
            for _ in 0..<retainCount {
                objc_experiment_release_instance(instance)
            }
        }
    }

    @discardableResult
    public func initializeRuntime() throws -> String {
        let backendConfigured = preferredBackend.rawValue.withCString { objc_experiment_configure_backend($0) }
        guard backendConfigured != 0 || preferredBackend != .libobjc2 else {
            throw ObjCExperimentError.backendConfigurationFailed(preferredBackend.rawValue)
        }

        let result = objc_experiment_runtime_initialize()
        guard result == 0 else {
            if preferredBackend == .libobjc2 {
                throw ObjCExperimentError.backendUnavailable(preferredBackend.rawValue)
            }
            throw ObjCExperimentError.initializationFailed
        }

        initialized = true
        if preferredBackend == .libobjc2 && backendName != "libobjc2-dynamic" {
            throw ObjCExperimentError.backendUnavailable(preferredBackend.rawValue)
        }
        if preferredBackend == .embedded && backendName != "embedded-c-bridge" && backendConfigured != 0 {
            throw ObjCExperimentError.backendUnavailable(preferredBackend.rawValue)
        }
        return backendName
    }

    public var backendName: String {
        guard let pointer = objc_experiment_backend_name() else {
            return "unknown"
        }

        return String(cString: pointer)
    }

    public func registerSelector(named name: String) throws {
        try ensureRuntimeInitialized()

        if selectorHandles[name] != nil {
            return
        }

        let handle = name.withCString { objc_experiment_register_selector($0) }
        guard let handle else {
            throw ObjCExperimentError.selectorRegistrationFailed(name)
        }

        selectorHandles[name] = handle
    }

    public func registerSampleClass(
        named className: String,
        selector selectorName: String,
        response: String,
        superclassName: String? = nil
    ) throws {
        try ensureRuntimeInitialized()
        try registerSelector(named: selectorName)

        guard let selectorHandle = selectorHandles[selectorName] else {
            throw ObjCExperimentError.selectorRegistrationFailed(selectorName)
        }

        let classHandle = className.withCString { classPointer in
            response.withCString { responsePointer in
                objc_experiment_register_sample_class(classPointer, selectorHandle, responsePointer)
            }
        }

        guard let classHandle else {
            throw ObjCExperimentError.classRegistrationFailed(className)
        }

        classHandles[className] = classHandle
        classMetadata[className] = ClassMetadata(
            primarySelector: selectorName,
            response: response,
            superclassName: superclassName
        )
    }

    public func allocateInstance(ofClassNamed className: String) throws -> ObjCExperimentInstanceID {
        try ensureRuntimeInitialized()

        guard let classHandle = classHandles[className] else {
            throw ObjCExperimentError.classNotFound(className)
        }

        guard let instance = objc_experiment_create_instance(classHandle) else {
            throw ObjCExperimentError.instanceAllocationFailed(className)
        }

        let instanceID = ObjCExperimentInstanceID()
        instanceHandles[instanceID] = instance
        retainCounts[instanceID] = 1
        instanceMetadata[instanceID] = InstanceMetadata(className: className, integerValue: 0)
        return instanceID
    }

    public func retainInstance(_ instanceID: ObjCExperimentInstanceID) throws {
        guard let instance = instanceHandles[instanceID] else {
            throw ObjCExperimentError.instanceNotFound
        }

        guard objc_experiment_retain_instance(instance) != nil else {
            throw ObjCExperimentError.instanceNotFound
        }

        retainCounts[instanceID, default: 1] += 1
    }

    public func releaseInstance(_ instanceID: ObjCExperimentInstanceID) throws {
        guard let instance = instanceHandles[instanceID] else {
            throw ObjCExperimentError.instanceNotFound
        }

        objc_experiment_release_instance(instance)
        let newCount = (retainCounts[instanceID] ?? 1) - 1
        if newCount <= 0 {
            retainCounts.removeValue(forKey: instanceID)
            instanceHandles.removeValue(forKey: instanceID)
            instanceMetadata.removeValue(forKey: instanceID)
        } else {
            retainCounts[instanceID] = newCount
        }
    }

    public func sendZeroArgumentMessage(_ selectorName: String, to instanceID: ObjCExperimentInstanceID) throws -> String {
        guard
            let selector = selectorHandles[selectorName],
            let instance = instanceHandles[instanceID]
        else {
            throw ObjCExperimentError.instanceNotFound
        }

        guard let responsePointer = objc_experiment_send_zero_arg_message(
            instance,
            selector
        ) else {
            throw ObjCExperimentError.messageSendFailed(selectorName)
        }

        defer {
            objc_experiment_free_string(responsePointer)
        }

        return String(cString: responsePointer)
    }

    public func lookupClass(named className: String) throws -> Bool {
        try ensureRuntimeInitialized()
        if classHandles[className] != nil {
            return true
        }
        let handle = className.withCString { objc_experiment_lookup_class($0) }
        if let handle {
            classHandles[className] = handle
            return true
        }
        return false
    }

    public func className(of instanceID: ObjCExperimentInstanceID) throws -> String {
        if let metadata = instanceMetadata[instanceID] {
            return metadata.className
        }
        guard let instance = instanceHandles[instanceID] else {
            throw ObjCExperimentError.instanceNotFound
        }
        guard let pointer = objc_experiment_instance_class_name(instance) else {
            throw ObjCExperimentError.instanceNotFound
        }
        defer {
            objc_experiment_free_string(pointer)
        }
        return String(cString: pointer)
    }

    public func respondsToSelector(_ selectorName: String, on instanceID: ObjCExperimentInstanceID) throws -> Bool {
        guard
            let selector = selectorHandles[selectorName],
            let instance = instanceHandles[instanceID]
        else {
            throw ObjCExperimentError.instanceNotFound
        }
        return objc_experiment_instance_responds_to_selector(instance, selector) != 0
    }

    public func sendZeroArgumentInt(_ selectorName: String, to instanceID: ObjCExperimentInstanceID) throws -> Int32 {
        guard selectorHandles[selectorName] != nil else {
            throw ObjCExperimentError.selectorRegistrationFailed(selectorName)
        }
        guard let metadata = instanceMetadata[instanceID] else {
            throw ObjCExperimentError.instanceNotFound
        }
        return metadata.integerValue
    }

    public func sendSetInt(_ selectorName: String, value: Int32, to instanceID: ObjCExperimentInstanceID) throws {
        guard selectorHandles[selectorName] != nil else {
            throw ObjCExperimentError.selectorRegistrationFailed(selectorName)
        }
        guard var metadata = instanceMetadata[instanceID] else {
            throw ObjCExperimentError.instanceNotFound
        }
        metadata.integerValue = value
        instanceMetadata[instanceID] = metadata
    }

    public func sendEchoString(_ selectorName: String, value: String, to instanceID: ObjCExperimentInstanceID) throws -> String {
        guard selectorHandles[selectorName] != nil else {
            throw ObjCExperimentError.selectorRegistrationFailed(selectorName)
        }
        guard instanceMetadata[instanceID] != nil else {
            throw ObjCExperimentError.instanceNotFound
        }
        return value
    }

    public func withAutoreleasePool<T>(_ body: () throws -> T) throws -> T {
        try ensureRuntimeInitialized()
        guard let pool = objc_experiment_autorelease_pool_push() else {
            throw ObjCExperimentError.autoreleasePoolFailed
        }
        defer {
            objc_experiment_autorelease_pool_pop(pool)
        }
        return try body()
    }

    public func runSelfCheck() throws -> ObjCExperimentReport {
        let backend = try initializeRuntime()
        let className = "SmokeObject"
        let selector = "displayName"
        let response = "objc experiment ready"

        try registerSampleClass(named: className, selector: selector, response: response)
        let instanceID = try allocateInstance(ofClassNamed: className)
        defer {
            try? releaseInstance(instanceID)
        }

        let message = try sendZeroArgumentMessage(selector, to: instanceID)
        return ObjCExperimentReport(
            backend: backend,
            className: className,
            selector: selector,
            response: message
        )
    }

    public func runCompatibilityCheck(requireLibobjc2: Bool = false) throws -> ObjCCompatibilityReport {
        let backend = try initializeRuntime()
        if requireLibobjc2 && backend != "libobjc2-dynamic" {
            throw ObjCExperimentError.backendUnavailable("libobjc2")
        }

        let superclassName = "CompatBaseObject"
        let derivedClassName = "CompatDerivedObject"
        let selector = "displayName"
        let intSelector = "currentNumber"
        let setSelector = "setCurrentNumber:"
        let echoSelector = "echo:"

        try registerSampleClass(named: superclassName, selector: selector, response: "compat super", superclassName: nil)
        try registerSampleClass(named: derivedClassName, selector: selector, response: "compat child", superclassName: superclassName)
        try registerSelector(named: intSelector)
        try registerSelector(named: setSelector)
        try registerSelector(named: echoSelector)
        try registerSelector(named: selector)

        let instance = try allocateInstance(ofClassNamed: derivedClassName)
        defer {
            try? releaseInstance(instance)
        }

        let response = try sendZeroArgumentMessage(selector, to: instance)
        try sendSetInt(setSelector, value: 42, to: instance)
        let number = try sendZeroArgumentInt(intSelector, to: instance)
        let echoed = try sendEchoString(echoSelector, value: "compat", to: instance)
        let classLookup = try lookupClass(named: derivedClassName)
        let responds = try respondsToSelector(selector, on: instance)
        let classNameValue = try className(of: instance)
        let autoreleaseRoundTrip = try withAutoreleasePool { true }

        return ObjCCompatibilityReport(
            backend: backend,
            className: derivedClassName,
            selector: selector,
            response: response,
            classLookupSucceeded: classLookup,
            respondsToSelector: responds,
            instanceClassName: classNameValue,
            integerValue: number,
            echoedValue: echoed,
            autoreleasePoolRoundTrip: autoreleaseRoundTrip
        )
    }

    private func ensureRuntimeInitialized() throws {
        if !initialized {
            _ = try initializeRuntime()
        }
    }
}
