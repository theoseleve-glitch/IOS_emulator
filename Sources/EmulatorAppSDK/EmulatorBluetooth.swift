import CBluetoothWinRTShim
import Foundation

public enum EmulatorBluetoothBackendMode: String, CaseIterable, Codable, Equatable, Sendable {
    case auto
    case mock
    case winrt
}

public enum EmulatorBluetoothAdapterState: Int32, Codable, Equatable, Sendable {
    case unknown = 0
    case poweredOff = 1
    case poweredOn = 2
    case unavailable = 3
    case unauthorized = 4
}

public struct EmulatorBluetoothScanFilter: Equatable, Sendable {
    public let namePrefix: String?
    public let serviceUUIDs: [EmulatorBluetoothServiceUUID]

    public init(namePrefix: String? = nil, serviceUUIDs: [EmulatorBluetoothServiceUUID] = []) {
        self.namePrefix = namePrefix
        self.serviceUUIDs = serviceUUIDs
    }
}

public struct EmulatorBluetoothPeripheralID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct EmulatorBluetoothServiceUUID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue.uppercased()
    }
}

public struct EmulatorBluetoothCharacteristicProperties: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let read = EmulatorBluetoothCharacteristicProperties(rawValue: 1 << 0)
    public static let write = EmulatorBluetoothCharacteristicProperties(rawValue: 1 << 1)
    public static let writeWithoutResponse = EmulatorBluetoothCharacteristicProperties(rawValue: 1 << 2)
    public static let notify = EmulatorBluetoothCharacteristicProperties(rawValue: 1 << 3)
}

public struct EmulatorBluetoothCharacteristicID: Hashable, Codable, Sendable {
    public let serviceUUID: EmulatorBluetoothServiceUUID
    public let characteristicUUID: String
    public let properties: EmulatorBluetoothCharacteristicProperties

    public init(
        serviceUUID: EmulatorBluetoothServiceUUID,
        characteristicUUID: String,
        properties: EmulatorBluetoothCharacteristicProperties
    ) {
        self.serviceUUID = serviceUUID
        self.characteristicUUID = characteristicUUID.uppercased()
        self.properties = properties
    }
}

public struct EmulatorBluetoothPeripheralSummary: Equatable, Codable, Sendable {
    public let id: EmulatorBluetoothPeripheralID
    public let name: String
    public let rssi: Int
    public let advertisedServiceUUIDs: [EmulatorBluetoothServiceUUID]

    public init(
        id: EmulatorBluetoothPeripheralID,
        name: String,
        rssi: Int,
        advertisedServiceUUIDs: [EmulatorBluetoothServiceUUID]
    ) {
        self.id = id
        self.name = name
        self.rssi = rssi
        self.advertisedServiceUUIDs = advertisedServiceUUIDs
    }
}

public enum EmulatorBluetoothWriteMode: String, Codable, Equatable, Sendable {
    case withResponse
    case withoutResponse
}

public struct EmulatorBluetoothNotification: Equatable, Sendable {
    public let peripheralID: EmulatorBluetoothPeripheralID
    public let characteristicID: EmulatorBluetoothCharacteristicID
    public let value: Data
    public let timestamp: Date

    public init(
        peripheralID: EmulatorBluetoothPeripheralID,
        characteristicID: EmulatorBluetoothCharacteristicID,
        value: Data,
        timestamp: Date = Date()
    ) {
        self.peripheralID = peripheralID
        self.characteristicID = characteristicID
        self.value = value
        self.timestamp = timestamp
    }
}

public enum EmulatorBluetoothServiceError: Error, Equatable, CustomStringConvertible {
    case unavailable(String)
    case adapterUnavailable
    case scanFailed(String)
    case connectFailed(String)
    case discoveryFailed(String)
    case readFailed(String)
    case writeFailed(String)
    case subscribeFailed(String)
    case invalidCharacteristic(String)

    public var description: String {
        switch self {
        case .unavailable(let message),
             .scanFailed(let message),
             .connectFailed(let message),
             .discoveryFailed(let message),
             .readFailed(let message),
             .writeFailed(let message),
             .subscribeFailed(let message),
             .invalidCharacteristic(let message):
            return message
        case .adapterUnavailable:
            return "Bluetooth adapter is unavailable."
        }
    }
}

public protocol EmulatorBluetoothService: Sendable {
    var backendMode: EmulatorBluetoothBackendMode { get }
    func adapterState() -> EmulatorBluetoothAdapterState
    func scan(filter: EmulatorBluetoothScanFilter, timeoutMilliseconds: Int32) async throws -> [EmulatorBluetoothPeripheralSummary]
    func connect(to peripheralID: EmulatorBluetoothPeripheralID) async throws
    func disconnect(from peripheralID: EmulatorBluetoothPeripheralID) async
    func discoverServices(for peripheralID: EmulatorBluetoothPeripheralID) async throws -> [EmulatorBluetoothServiceUUID]
    func discoverCharacteristics(
        for peripheralID: EmulatorBluetoothPeripheralID,
        serviceUUID: EmulatorBluetoothServiceUUID
    ) async throws -> [EmulatorBluetoothCharacteristicID]
    func readValue(
        for characteristicID: EmulatorBluetoothCharacteristicID,
        peripheralID: EmulatorBluetoothPeripheralID
    ) async throws -> Data
    func writeValue(
        _ value: Data,
        for characteristicID: EmulatorBluetoothCharacteristicID,
        peripheralID: EmulatorBluetoothPeripheralID,
        mode: EmulatorBluetoothWriteMode
    ) async throws
    func subscribe(
        to characteristicID: EmulatorBluetoothCharacteristicID,
        peripheralID: EmulatorBluetoothPeripheralID
    ) async throws -> AsyncThrowingStream<EmulatorBluetoothNotification, Error>
}

public final class UnavailableBluetoothService: EmulatorBluetoothService, @unchecked Sendable {
    public let backendMode: EmulatorBluetoothBackendMode
    private let message: String

    public init(backendMode: EmulatorBluetoothBackendMode, message: String) {
        self.backendMode = backendMode
        self.message = message
    }

    public func adapterState() -> EmulatorBluetoothAdapterState {
        .unavailable
    }

    public func scan(filter: EmulatorBluetoothScanFilter, timeoutMilliseconds: Int32) async throws -> [EmulatorBluetoothPeripheralSummary] {
        throw EmulatorBluetoothServiceError.unavailable(message)
    }

    public func connect(to peripheralID: EmulatorBluetoothPeripheralID) async throws {
        throw EmulatorBluetoothServiceError.unavailable(message)
    }

    public func disconnect(from peripheralID: EmulatorBluetoothPeripheralID) async {}

    public func discoverServices(for peripheralID: EmulatorBluetoothPeripheralID) async throws -> [EmulatorBluetoothServiceUUID] {
        throw EmulatorBluetoothServiceError.unavailable(message)
    }

    public func discoverCharacteristics(
        for peripheralID: EmulatorBluetoothPeripheralID,
        serviceUUID: EmulatorBluetoothServiceUUID
    ) async throws -> [EmulatorBluetoothCharacteristicID] {
        throw EmulatorBluetoothServiceError.unavailable(message)
    }

    public func readValue(
        for characteristicID: EmulatorBluetoothCharacteristicID,
        peripheralID: EmulatorBluetoothPeripheralID
    ) async throws -> Data {
        throw EmulatorBluetoothServiceError.unavailable(message)
    }

    public func writeValue(
        _ value: Data,
        for characteristicID: EmulatorBluetoothCharacteristicID,
        peripheralID: EmulatorBluetoothPeripheralID,
        mode: EmulatorBluetoothWriteMode
    ) async throws {
        throw EmulatorBluetoothServiceError.unavailable(message)
    }

    public func subscribe(
        to characteristicID: EmulatorBluetoothCharacteristicID,
        peripheralID: EmulatorBluetoothPeripheralID
    ) async throws -> AsyncThrowingStream<EmulatorBluetoothNotification, Error> {
        throw EmulatorBluetoothServiceError.unavailable(message)
    }
}

public final class MockBluetoothService: EmulatorBluetoothService, @unchecked Sendable {
    public let backendMode: EmulatorBluetoothBackendMode = .mock

    private struct MockPeripheral {
        let summary: EmulatorBluetoothPeripheralSummary
        let services: [EmulatorBluetoothServiceUUID]
        let characteristics: [EmulatorBluetoothServiceUUID: [EmulatorBluetoothCharacteristicID]]
        let initialValues: [EmulatorBluetoothCharacteristicID: Data]
        let notificationValues: [EmulatorBluetoothCharacteristicID: [Data]]
    }

    private let lock = NSLock()
    private let uartService = EmulatorBluetoothServiceUUID(rawValue: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    private let txCharacteristic: EmulatorBluetoothCharacteristicID
    private let rxCharacteristic: EmulatorBluetoothCharacteristicID
    private let peripherals: [EmulatorBluetoothPeripheralID: MockPeripheral]
    private var connectedPeripheralIDs: Set<EmulatorBluetoothPeripheralID> = []

    public init() {
        txCharacteristic = EmulatorBluetoothCharacteristicID(
            serviceUUID: uartService,
            characteristicUUID: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E",
            properties: [.read, .notify]
        )
        rxCharacteristic = EmulatorBluetoothCharacteristicID(
            serviceUUID: uartService,
            characteristicUUID: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E",
            properties: [.write, .writeWithoutResponse]
        )

        let peripheralID = EmulatorBluetoothPeripheralID(rawValue: "mock-uart-01")
        let summary = EmulatorBluetoothPeripheralSummary(
            id: peripheralID,
            name: "Mock UART Telemetry",
            rssi: -48,
            advertisedServiceUUIDs: [uartService]
        )
        let notificationPackets = [
            Data("speed=128;lap=1".utf8),
            Data("speed=132;lap=1".utf8),
            Data("speed=136;lap=2".utf8),
            Data("speed=141;lap=2".utf8),
            Data("speed=145;lap=3".utf8),
        ]
        let peripheral = MockPeripheral(
            summary: summary,
            services: [uartService],
            characteristics: [uartService: [txCharacteristic, rxCharacteristic]],
            initialValues: [txCharacteristic: notificationPackets[0], rxCharacteristic: Data()],
            notificationValues: [txCharacteristic: notificationPackets]
        )
        peripherals = [peripheralID: peripheral]
    }

    public func adapterState() -> EmulatorBluetoothAdapterState {
        .poweredOn
    }

    public func scan(
        filter: EmulatorBluetoothScanFilter,
        timeoutMilliseconds: Int32
    ) async throws -> [EmulatorBluetoothPeripheralSummary] {
        try await Task.sleep(nanoseconds: UInt64(max(10, timeoutMilliseconds)) * 1_000_000)
        let discovered = Array(peripherals.values.map(\.summary))
        return discovered.filter { summary in
            let matchesName = filter.namePrefix.map { summary.name.localizedCaseInsensitiveContains($0) } ?? true
            let matchesServices = filter.serviceUUIDs.isEmpty || !Set(summary.advertisedServiceUUIDs).isDisjoint(with: filter.serviceUUIDs)
            return matchesName && matchesServices
        }
    }

    public func connect(to peripheralID: EmulatorBluetoothPeripheralID) async throws {
        guard peripherals[peripheralID] != nil else {
            throw EmulatorBluetoothServiceError.connectFailed("Unknown mock peripheral: \(peripheralID.rawValue)")
        }

        _ = lock.withLock {
            connectedPeripheralIDs.insert(peripheralID)
        }
    }

    public func disconnect(from peripheralID: EmulatorBluetoothPeripheralID) async {
        _ = lock.withLock {
            connectedPeripheralIDs.remove(peripheralID)
        }
    }

    public func discoverServices(for peripheralID: EmulatorBluetoothPeripheralID) async throws -> [EmulatorBluetoothServiceUUID] {
        try ensureConnected(peripheralID)
        guard let peripheral = peripherals[peripheralID] else {
            throw EmulatorBluetoothServiceError.discoveryFailed("Unknown mock peripheral: \(peripheralID.rawValue)")
        }

        return peripheral.services
    }

    public func discoverCharacteristics(
        for peripheralID: EmulatorBluetoothPeripheralID,
        serviceUUID: EmulatorBluetoothServiceUUID
    ) async throws -> [EmulatorBluetoothCharacteristicID] {
        try ensureConnected(peripheralID)
        guard
            let peripheral = peripherals[peripheralID],
            let characteristics = peripheral.characteristics[serviceUUID]
        else {
            throw EmulatorBluetoothServiceError.discoveryFailed("Unknown mock service \(serviceUUID.rawValue) for \(peripheralID.rawValue)")
        }

        return characteristics
    }

    public func readValue(
        for characteristicID: EmulatorBluetoothCharacteristicID,
        peripheralID: EmulatorBluetoothPeripheralID
    ) async throws -> Data {
        try ensureConnected(peripheralID)
        guard let peripheral = peripherals[peripheralID] else {
            throw EmulatorBluetoothServiceError.readFailed("Unknown mock peripheral: \(peripheralID.rawValue)")
        }

        return peripheral.initialValues[characteristicID] ?? Data()
    }

    public func writeValue(
        _ value: Data,
        for characteristicID: EmulatorBluetoothCharacteristicID,
        peripheralID: EmulatorBluetoothPeripheralID,
        mode: EmulatorBluetoothWriteMode
    ) async throws {
        try ensureConnected(peripheralID)
        guard characteristicID == rxCharacteristic else {
            throw EmulatorBluetoothServiceError.writeFailed("Mock write is only supported for the RX UART characteristic.")
        }
        _ = value
        _ = mode
    }

    public func subscribe(
        to characteristicID: EmulatorBluetoothCharacteristicID,
        peripheralID: EmulatorBluetoothPeripheralID
    ) async throws -> AsyncThrowingStream<EmulatorBluetoothNotification, Error> {
        try ensureConnected(peripheralID)
        guard let peripheral = peripherals[peripheralID] else {
            throw EmulatorBluetoothServiceError.subscribeFailed("Unknown mock peripheral: \(peripheralID.rawValue)")
        }
        guard let packets = peripheral.notificationValues[characteristicID] else {
            throw EmulatorBluetoothServiceError.subscribeFailed("Mock notifications are not available for \(characteristicID.characteristicUUID)")
        }

        return AsyncThrowingStream { continuation in
            let streamTask = Task {
                for packet in packets {
                    if Task.isCancelled || !self.isConnected(peripheralID) {
                        break
                    }
                    continuation.yield(
                        EmulatorBluetoothNotification(
                            peripheralID: peripheralID,
                            characteristicID: characteristicID,
                            value: packet
                        )
                    )
                    try? await Task.sleep(nanoseconds: 220_000_000)
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                streamTask.cancel()
            }
        }
    }

    private func ensureConnected(_ peripheralID: EmulatorBluetoothPeripheralID) throws {
        guard isConnected(peripheralID) else {
            throw EmulatorBluetoothServiceError.connectFailed("Peripheral \(peripheralID.rawValue) is not connected.")
        }
    }

    private func isConnected(_ peripheralID: EmulatorBluetoothPeripheralID) -> Bool {
        lock.lock()
        let connected = connectedPeripheralIDs.contains(peripheralID)
        lock.unlock()
        return connected
    }
}

public final class WinRTBluetoothService: EmulatorBluetoothService, @unchecked Sendable {
    public let backendMode: EmulatorBluetoothBackendMode = .winrt
    private let client: UnsafeMutableRawPointer?

    public init?() {
        guard bluetooth_winrt_is_supported() != 0 else {
            return nil
        }

        client = bluetooth_winrt_client_create()
        if client == nil {
            return nil
        }
    }

    deinit {
        if let client {
            bluetooth_winrt_client_destroy(client)
        }
    }

    public static func adapterStateValue() -> EmulatorBluetoothAdapterState {
        EmulatorBluetoothAdapterState(rawValue: bluetooth_winrt_adapter_state()) ?? .unknown
    }

    public static var isSupported: Bool {
        bluetooth_winrt_is_supported() != 0
    }

    public func adapterState() -> EmulatorBluetoothAdapterState {
        Self.adapterStateValue()
    }

    public func scan(
        filter: EmulatorBluetoothScanFilter,
        timeoutMilliseconds: Int32
    ) async throws -> [EmulatorBluetoothPeripheralSummary] {
        guard let client else {
            throw EmulatorBluetoothServiceError.unavailable("The WinRT Bluetooth backend is unavailable.")
        }

        guard let jsonPointer = bluetooth_winrt_scan_json(client, UInt32(max(50, timeoutMilliseconds))) else {
            throw EmulatorBluetoothServiceError.scanFailed("WinRT scan failed.")
        }
        defer { bluetooth_winrt_free_string(jsonPointer) }

        let data = Data(stringFromCString(jsonPointer).utf8)
        let summaries = try JSONDecoder().decode([BluetoothScanSummaryDTO].self, from: data).map(\.summary)
        return summaries.filter { summary in
            let matchesName = filter.namePrefix.map { summary.name.localizedCaseInsensitiveContains($0) } ?? true
            let matchesServices = filter.serviceUUIDs.isEmpty || !Set(summary.advertisedServiceUUIDs).isDisjoint(with: filter.serviceUUIDs)
            return matchesName && matchesServices
        }
    }

    public func connect(to peripheralID: EmulatorBluetoothPeripheralID) async throws {
        guard let client else {
            throw EmulatorBluetoothServiceError.unavailable("The WinRT Bluetooth backend is unavailable.")
        }
        let result = peripheralID.rawValue.withCString { bluetooth_winrt_connect(client, $0) }
        guard result == 0 else {
            throw EmulatorBluetoothServiceError.connectFailed("Failed to connect to \(peripheralID.rawValue) via WinRT.")
        }
    }

    public func disconnect(from peripheralID: EmulatorBluetoothPeripheralID) async {
        guard let client else { return }
        peripheralID.rawValue.withCString {
            bluetooth_winrt_disconnect(client, $0)
        }
    }

    public func discoverServices(for peripheralID: EmulatorBluetoothPeripheralID) async throws -> [EmulatorBluetoothServiceUUID] {
        guard let client else {
            throw EmulatorBluetoothServiceError.unavailable("The WinRT Bluetooth backend is unavailable.")
        }

        guard let jsonPointer = peripheralID.rawValue.withCString({ bluetooth_winrt_discover_services_json(client, $0) }) else {
            throw EmulatorBluetoothServiceError.discoveryFailed("Failed to discover GATT services for \(peripheralID.rawValue).")
        }
        defer { bluetooth_winrt_free_string(jsonPointer) }

        let data = Data(stringFromCString(jsonPointer).utf8)
        return try JSONDecoder().decode([String].self, from: data).map(EmulatorBluetoothServiceUUID.init(rawValue:))
    }

    public func discoverCharacteristics(
        for peripheralID: EmulatorBluetoothPeripheralID,
        serviceUUID: EmulatorBluetoothServiceUUID
    ) async throws -> [EmulatorBluetoothCharacteristicID] {
        guard let client else {
            throw EmulatorBluetoothServiceError.unavailable("The WinRT Bluetooth backend is unavailable.")
        }

        guard let jsonPointer = peripheralID.rawValue.withCString({ peripheralCString in
            serviceUUID.rawValue.withCString { serviceCString in
                bluetooth_winrt_discover_characteristics_json(client, peripheralCString, serviceCString)
            }
        }) else {
            throw EmulatorBluetoothServiceError.discoveryFailed("Failed to discover GATT characteristics for \(serviceUUID.rawValue).")
        }
        defer { bluetooth_winrt_free_string(jsonPointer) }

        let data = Data(stringFromCString(jsonPointer).utf8)
        let dtos = try JSONDecoder().decode([BluetoothCharacteristicDTO].self, from: data)
        return dtos.map(\.characteristicID)
    }

    public func readValue(
        for characteristicID: EmulatorBluetoothCharacteristicID,
        peripheralID: EmulatorBluetoothPeripheralID
    ) async throws -> Data {
        guard let client else {
            throw EmulatorBluetoothServiceError.unavailable("The WinRT Bluetooth backend is unavailable.")
        }

        var bytesPointer: UnsafeMutablePointer<UInt8>?
        var length: UInt32 = 0
        let result = peripheralID.rawValue.withCString { peripheralCString in
            characteristicID.serviceUUID.rawValue.withCString { serviceCString in
                characteristicID.characteristicUUID.withCString { characteristicCString in
                    bluetooth_winrt_read_value(
                        client,
                        peripheralCString,
                        serviceCString,
                        characteristicCString,
                        &bytesPointer,
                        &length
                    )
                }
            }
        }

        guard result == 0, let bytesPointer else {
            throw EmulatorBluetoothServiceError.readFailed("Failed to read value for \(characteristicID.characteristicUUID).")
        }
        defer { bluetooth_winrt_free_bytes(bytesPointer) }
        return Data(bytes: bytesPointer, count: Int(length))
    }

    public func writeValue(
        _ value: Data,
        for characteristicID: EmulatorBluetoothCharacteristicID,
        peripheralID: EmulatorBluetoothPeripheralID,
        mode: EmulatorBluetoothWriteMode
    ) async throws {
        guard let client else {
            throw EmulatorBluetoothServiceError.unavailable("The WinRT Bluetooth backend is unavailable.")
        }

        let result = value.withUnsafeBytes { rawBuffer -> Int32 in
            let basePointer = rawBuffer.bindMemory(to: UInt8.self).baseAddress
            return peripheralID.rawValue.withCString { peripheralCString in
                characteristicID.serviceUUID.rawValue.withCString { serviceCString in
                    characteristicID.characteristicUUID.withCString { characteristicCString in
                        bluetooth_winrt_write_value(
                            client,
                            peripheralCString,
                            serviceCString,
                            characteristicCString,
                            basePointer,
                            UInt32(value.count),
                            mode == .withResponse ? 0 : 1
                        )
                    }
                }
            }
        }

        guard result == 0 else {
            throw EmulatorBluetoothServiceError.writeFailed("Failed to write value for \(characteristicID.characteristicUUID).")
        }
    }

    public func subscribe(
        to characteristicID: EmulatorBluetoothCharacteristicID,
        peripheralID: EmulatorBluetoothPeripheralID
    ) async throws -> AsyncThrowingStream<EmulatorBluetoothNotification, Error> {
        guard let client else {
            throw EmulatorBluetoothServiceError.unavailable("The WinRT Bluetooth backend is unavailable.")
        }

        return AsyncThrowingStream { continuation in
            let retained = Unmanaged.passRetained(NotificationCallbackBox { value in
                continuation.yield(
                    EmulatorBluetoothNotification(
                        peripheralID: peripheralID,
                        characteristicID: characteristicID,
                        value: value
                    )
                )
            }).toOpaque()

            let subscription = peripheralID.rawValue.withCString { peripheralCString in
                characteristicID.serviceUUID.rawValue.withCString { serviceCString in
                    characteristicID.characteristicUUID.withCString { characteristicCString in
                        bluetooth_winrt_subscribe(
                            client,
                            peripheralCString,
                            serviceCString,
                            characteristicCString,
                            bluetoothWinRTNotificationCallback,
                            retained
                        )
                    }
                }
            }

            if subscription == nil {
                Unmanaged<NotificationCallbackBox>.fromOpaque(retained).release()
                continuation.finish(throwing: EmulatorBluetoothServiceError.subscribeFailed("Failed to subscribe to \(characteristicID.characteristicUUID)."))
                return
            }

            let terminationBox = WinRTSubscriptionTerminationBox(
                client: client,
                subscription: subscription,
                retainedCallback: retained
            )
            continuation.onTermination = { _ in
                terminationBox.tearDown()
            }
        }
    }
}

private final class NotificationCallbackBox {
    let callback: (Data) -> Void

    init(callback: @escaping (Data) -> Void) {
        self.callback = callback
    }
}

private final class WinRTSubscriptionTerminationBox: @unchecked Sendable {
    private let client: UnsafeMutableRawPointer
    private let subscription: UnsafeMutableRawPointer?
    private let retainedCallback: UnsafeMutableRawPointer

    init(
        client: UnsafeMutableRawPointer,
        subscription: UnsafeMutableRawPointer?,
        retainedCallback: UnsafeMutableRawPointer
    ) {
        self.client = client
        self.subscription = subscription
        self.retainedCallback = retainedCallback
    }

    func tearDown() {
        if let subscription {
            bluetooth_winrt_unsubscribe(client, subscription)
        }
        Unmanaged<NotificationCallbackBox>.fromOpaque(retainedCallback).release()
    }
}

private let bluetoothWinRTNotificationCallback: @convention(c) (
    UnsafeMutableRawPointer?,
    UnsafePointer<CChar>?,
    UnsafePointer<CChar>?,
    UnsafePointer<CChar>?,
    UnsafePointer<UInt8>?,
    UInt32
) -> Void = { context, _, _, _, bytes, length in
    guard let context else {
        return
    }

    let box = Unmanaged<NotificationCallbackBox>.fromOpaque(context).takeUnretainedValue()
    let data: Data
    if let bytes, length > 0 {
        data = Data(bytes: bytes, count: Int(length))
    } else {
        data = Data()
    }
    box.callback(data)
}

private func stringFromCString(_ pointer: UnsafePointer<CChar>) -> String {
    String(cString: pointer)
}

private struct BluetoothScanSummaryDTO: Codable {
    let id: String
    let name: String
    let rssi: Int
    let advertisedServiceUUIDs: [String]

    var summary: EmulatorBluetoothPeripheralSummary {
        EmulatorBluetoothPeripheralSummary(
            id: EmulatorBluetoothPeripheralID(rawValue: id),
            name: name,
            rssi: rssi,
            advertisedServiceUUIDs: advertisedServiceUUIDs.map(EmulatorBluetoothServiceUUID.init(rawValue:))
        )
    }
}

private struct BluetoothCharacteristicDTO: Codable {
    let serviceUUID: String
    let characteristicUUID: String
    let properties: Int

    var characteristicID: EmulatorBluetoothCharacteristicID {
        EmulatorBluetoothCharacteristicID(
            serviceUUID: EmulatorBluetoothServiceUUID(rawValue: serviceUUID),
            characteristicUUID: characteristicUUID,
            properties: EmulatorBluetoothCharacteristicProperties(rawValue: properties)
        )
    }
}
