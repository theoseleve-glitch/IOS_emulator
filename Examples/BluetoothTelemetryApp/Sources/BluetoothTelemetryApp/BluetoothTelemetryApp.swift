import EmulatorAppSDK
import Foundation

public enum BluetoothTelemetryRegistration: EmulatorServiceAwareAppRegistration {
    public static let manifest = EmulatorAppManifest(
        appID: "example.bluetooth-telemetry",
        displayName: "Bluetooth Telemetry",
        defaultViewport: .graphicalPhone,
        supportedRenderers: [.text, .win32],
        requiredCapabilities: [.bluetooth, .logging, .clock]
    )

    public static func makeController() -> any EmulatorAppController {
        makeController(services: .defaults(appID: manifest.appID, rendererMode: manifest.defaultRenderer))
    }

    public static func makeController(services: EmulatorHostServices) -> any EmulatorAppController {
        BluetoothTelemetryController(services: services)
    }
}

private enum BluetoothTelemetryAction {
    static let scan = "ble.scan"
    static let disconnect = "ble.disconnect"

    static func connect(_ id: String) -> UIActionID {
        "ble.connect:\(id)"
    }
}

private struct BluetoothTelemetryViewState {
    var adapterState: EmulatorBluetoothAdapterState
    var backendMode: EmulatorBluetoothBackendMode
    var isScanning = false
    var connectionLabel = "Idle"
    var peripherals: [EmulatorBluetoothPeripheralSummary] = []
    var connectedPeripheralID: EmulatorBluetoothPeripheralID?
    var activeCharacteristic: EmulatorBluetoothCharacteristicID?
    var packetCount = 0
    var lastPayloadPreview = "No packets yet"
    var lastUpdatedLabel = "Never"
}

public final class BluetoothTelemetryController: EmulatorLifecycleAwareAppController, @unchecked Sendable {
    private let services: EmulatorHostServices
    private let lock = NSLock()
    private var state: BluetoothTelemetryViewState
    private var lifecycleTask: Task<Void, Never>?
    private var notificationTask: Task<Void, Never>?
    private var hasStarted = false

    public init(
        services: EmulatorHostServices = .defaults(
            appID: BluetoothTelemetryRegistration.manifest.appID,
            rendererMode: BluetoothTelemetryRegistration.manifest.defaultRenderer,
            bluetoothBackendMode: .auto
        )
    ) {
        self.services = services
        self.state = BluetoothTelemetryViewState(
            adapterState: services.bluetooth.adapterState(),
            backendMode: services.bluetooth.backendMode
        )
    }

    public func start() throws {
        let waitForInitialPacket = services.bluetooth.backendMode == .mock
        let startupSemaphore = DispatchSemaphore(value: 0)
        let didSignal = SignalState()

        let signalReady: @Sendable () -> Void = {
            if didSignal.markSignalled() {
                startupSemaphore.signal()
            }
        }

        lock.lock()
        if hasStarted {
            lock.unlock()
            return
        }
        hasStarted = true
        lock.unlock()

        lifecycleTask = Task { [weak self] in
            guard let self else {
                signalReady()
                return
            }
            await self.bootstrap(signalReady: signalReady)
        }

        if waitForInitialPacket {
            _ = startupSemaphore.wait(timeout: .now() + 2)
        }
    }

    public func stop() {
        lock.lock()
        let connectedPeripheralID = state.connectedPeripheralID
        lock.unlock()

        lifecycleTask?.cancel()
        notificationTask?.cancel()
        lifecycleTask = nil
        notificationTask = nil

        if let connectedPeripheralID {
            Task {
                await services.bluetooth.disconnect(from: connectedPeripheralID)
            }
        }
    }

    public func makeDocument() -> ScreenDocument {
        let snapshot = snapshotState()
        let peripheralItems = snapshot.peripherals.map { peripheral in
            ListItemModel(
                id: peripheral.id.rawValue,
                title: peripheral.name,
                subtitle: "RSSI \(peripheral.rssi) dBm | \(peripheral.id.rawValue)",
                action: BluetoothTelemetryAction.connect(peripheral.id.rawValue)
            )
        }

        return UI.screen(title: "Bluetooth Telemetry") {
            UI.padding(.uniform(20), UI.vStack(spacing: 16) {
                UI.text("Generic GATT Telemetry", style: .headline)
                UI.text("Backend: \(snapshot.backendMode.rawValue) | Adapter: \(describe(snapshot.adapterState))", style: .caption)
                UI.text("Connection: \(snapshot.connectionLabel)", style: .caption)
                UI.gauge(
                    label: "Packets",
                    value: Double(snapshot.packetCount),
                    range: 0...20,
                    unit: "pkts",
                    accentColor: snapshot.connectedPeripheralID == nil ? .warning : .accentStrong
                )
                UI.text("Last payload: \(snapshot.lastPayloadPreview)", style: .body)
                UI.text("Updated: \(snapshot.lastUpdatedLabel)", style: .caption)
                UI.hStack(spacing: 12) {
                    UI.frame(fillsWidth: true, alignment: .center, UI.button("Scan", action: BluetoothTelemetryAction.scan))
                    UI.frame(fillsWidth: true, alignment: .center, UI.button("Disconnect", action: BluetoothTelemetryAction.disconnect, style: .secondary))
                }
                UI.text("Peripherals", style: .headline)
                UI.list(items: peripheralItems, selectedID: snapshot.connectedPeripheralID?.rawValue)
            })
        }
    }

    @discardableResult
    public func handle(action: UIActionID) -> Bool {
        switch action {
        case BluetoothTelemetryAction.scan:
            beginScan(autoConnectFirst: false)
            return true
        case BluetoothTelemetryAction.disconnect:
            beginDisconnect()
            return true
        default:
            guard action.hasPrefix("ble.connect:") else {
                return false
            }
            let peripheralID = EmulatorBluetoothPeripheralID(rawValue: String(action.dropFirst("ble.connect:".count)))
            connectToPeripheral(peripheralID, signalReady: nil)
            return true
        }
    }

    private func bootstrap(signalReady: @escaping @Sendable () -> Void) async {
        await refreshAdapterState()
        await runScan(autoConnectFirst: true, signalReady: signalReady)
    }

    private func beginScan(autoConnectFirst: Bool) {
        Task { [weak self] in
            await self?.runScan(autoConnectFirst: autoConnectFirst, signalReady: nil)
        }
    }

    private func beginDisconnect() {
        Task { [weak self] in
            await self?.disconnectCurrentPeripheral()
        }
    }

    private func refreshAdapterState() async {
        updateState { current in
            current.adapterState = services.bluetooth.adapterState()
            current.backendMode = services.bluetooth.backendMode
            current.lastUpdatedLabel = Self.timestampLabel(services.clock.now)
        }
    }

    private func runScan(autoConnectFirst: Bool, signalReady: (@Sendable () -> Void)?) async {
        updateState {
            $0.isScanning = true
            $0.connectionLabel = "Scanning..."
        }
        services.logging.log(.info, "Starting Bluetooth scan using \(services.bluetooth.backendMode.rawValue).")

        do {
            let peripherals = try await services.bluetooth.scan(
                filter: EmulatorBluetoothScanFilter(),
                timeoutMilliseconds: services.bluetooth.backendMode == .mock ? 40 : 900
            )
            updateState {
                $0.peripherals = peripherals
                $0.isScanning = false
                $0.connectionLabel = peripherals.isEmpty ? "No peripherals found" : "Discovered \(peripherals.count) peripheral(s)"
                $0.lastUpdatedLabel = Self.timestampLabel(services.clock.now)
            }

            if autoConnectFirst, let first = peripherals.first {
                connectToPeripheral(first.id, signalReady: signalReady)
            } else {
                signalReady?()
            }
        } catch {
            services.logging.log(.error, "Bluetooth scan failed: \(error)")
            updateState {
                $0.isScanning = false
                $0.connectionLabel = "Scan failed"
                $0.lastPayloadPreview = String(describing: error)
                $0.lastUpdatedLabel = Self.timestampLabel(services.clock.now)
            }
            signalReady?()
        }
    }

    private func connectToPeripheral(
        _ peripheralID: EmulatorBluetoothPeripheralID,
        signalReady: (@Sendable () -> Void)?
    ) {
        Task { [weak self] in
            guard let self else {
                signalReady?()
                return
            }
            await self.performConnect(to: peripheralID, signalReady: signalReady)
        }
    }

    private func performConnect(
        to peripheralID: EmulatorBluetoothPeripheralID,
        signalReady: (@Sendable () -> Void)?
    ) async {
        notificationTask?.cancel()
        updateState {
            $0.connectionLabel = "Connecting to \(peripheralID.rawValue)..."
        }

        do {
            try await services.bluetooth.connect(to: peripheralID)
            let servicesUUIDs = try await services.bluetooth.discoverServices(for: peripheralID)
            guard let serviceUUID = servicesUUIDs.first else {
                throw EmulatorBluetoothServiceError.discoveryFailed("No services found for \(peripheralID.rawValue)")
            }
            let characteristics = try await services.bluetooth.discoverCharacteristics(for: peripheralID, serviceUUID: serviceUUID)
            guard
                let characteristic = characteristics.first(where: { $0.properties.contains(.notify) || $0.properties.contains(.read) })
                    ?? characteristics.first
            else {
                throw EmulatorBluetoothServiceError.discoveryFailed("No characteristics found for \(serviceUUID.rawValue)")
            }

            let initialValue = try await services.bluetooth.readValue(for: characteristic, peripheralID: peripheralID)
            updateState {
                $0.connectedPeripheralID = peripheralID
                $0.activeCharacteristic = characteristic
                $0.connectionLabel = "Connected to \(peripheralID.rawValue)"
                $0.lastPayloadPreview = initialValue.isEmpty ? "Connected - waiting for packets" : String(decoding: initialValue, as: UTF8.self)
                $0.lastUpdatedLabel = Self.timestampLabel(services.clock.now)
            }

            let stream = try await services.bluetooth.subscribe(to: characteristic, peripheralID: peripheralID)
            let onFirstPacket = signalReady
            notificationTask = Task { [weak self] in
                var firstPacketDelivered = false
                do {
                    for try await notification in stream {
                        guard let self else {
                            return
                        }
                        self.updateState {
                            $0.packetCount += 1
                            $0.lastPayloadPreview = String(decoding: notification.value, as: UTF8.self)
                            $0.lastUpdatedLabel = Self.timestampLabel(notification.timestamp)
                        }
                        if !firstPacketDelivered {
                            firstPacketDelivered = true
                            onFirstPacket?()
                        }
                    }
                    if !firstPacketDelivered {
                        onFirstPacket?()
                    }
                } catch {
                    self?.services.logging.log(.warning, "Bluetooth notification stream ended: \(error)")
                    self?.updateState {
                        $0.connectionLabel = "Notifications ended"
                        $0.lastUpdatedLabel = Self.timestampLabel(self?.services.clock.now ?? Date())
                    }
                    onFirstPacket?()
                }
            }

            if services.bluetooth.backendMode != .mock {
                signalReady?()
            }
        } catch {
            services.logging.log(.error, "Bluetooth connect failed: \(error)")
            updateState {
                $0.connectionLabel = "Connect failed"
                $0.lastPayloadPreview = String(describing: error)
                $0.lastUpdatedLabel = Self.timestampLabel(services.clock.now)
            }
            signalReady?()
        }
    }

    private func disconnectCurrentPeripheral() async {
        let connectedPeripheralID = lock.withLock {
            state.connectedPeripheralID
        }

        notificationTask?.cancel()
        notificationTask = nil

        guard let connectedPeripheralID else {
            updateState {
                $0.connectionLabel = "No active peripheral"
            }
            return
        }

        await services.bluetooth.disconnect(from: connectedPeripheralID)
        updateState {
            $0.connectedPeripheralID = nil
            $0.activeCharacteristic = nil
            $0.connectionLabel = "Disconnected"
            $0.lastUpdatedLabel = Self.timestampLabel(services.clock.now)
        }
    }

    private func snapshotState() -> BluetoothTelemetryViewState {
        lock.lock()
        let snapshot = state
        lock.unlock()
        return snapshot
    }

    private func updateState(_ mutate: (inout BluetoothTelemetryViewState) -> Void) {
        lock.lock()
        mutate(&state)
        lock.unlock()
        services.invalidation.requestRedraw()
    }

    private func describe(_ adapterState: EmulatorBluetoothAdapterState) -> String {
        switch adapterState {
        case .unknown:
            return "unknown"
        case .poweredOff:
            return "poweredOff"
        case .poweredOn:
            return "poweredOn"
        case .unavailable:
            return "unavailable"
        case .unauthorized:
            return "unauthorized"
        }
    }

    private static func timestampLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

private final class SignalState: @unchecked Sendable {
    private let lock = NSLock()
    private var didSignal = false

    func markSignalled() -> Bool {
        lock.withLock {
            guard !didSignal else {
                return false
            }
            didSignal = true
            return true
        }
    }
}
