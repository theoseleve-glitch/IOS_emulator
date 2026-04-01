import Foundation
import XCTest
@testable import EmulatorAppSDK

final class EmulatorAppSDKTests: XCTestCase {
    func testAssetCatalogLoadsImageColorAndStrings() throws {
        let catalog = EmulatorAssetCatalog(bundle: .module)

        let image = catalog.image(named: "test-banner")
        let accent = catalog.color(named: "accent")
        let englishTitle = catalog.localizedString("title", locale: "en")
        let frenchTitle = catalog.localizedString("title", locale: "fr")
        let missing = catalog.localizedString("missing.key", locale: "en")
        let resolvedAccent = try XCTUnwrap(accent)

        XCTAssertEqual(image?.name, "test-banner")
        XCTAssertEqual(URL(fileURLWithPath: image?.filePath ?? "").lastPathComponent, "test-banner.png")
        XCTAssertEqual(resolvedAccent.red, 28.0 / 255.0, accuracy: 0.0001)
        XCTAssertEqual(resolvedAccent.green, 107.0 / 255.0, accuracy: 0.0001)
        XCTAssertEqual(resolvedAccent.blue, 199.0 / 255.0, accuracy: 0.0001)
        XCTAssertEqual(resolvedAccent.alpha, 1.0, accuracy: 0.0001)
        XCTAssertEqual(englishTitle, "SDK Test")
        XCTAssertEqual(frenchTitle, "Test SDK")
        XCTAssertEqual(missing, "missing.key")
    }

    func testManifestPicksStableDefaultRenderer() {
        let textOnly = EmulatorAppManifest(
            appID: "test.text",
            displayName: "Text",
            defaultViewport: .terminalPhone,
            supportedRenderers: [.text]
        )
        let mixed = EmulatorAppManifest(
            appID: "test.mixed",
            displayName: "Mixed",
            defaultViewport: .graphicalPhone,
            supportedRenderers: [.text, .win32]
        )

        XCTAssertEqual(textOnly.defaultRenderer, .text)
        XCTAssertEqual(mixed.defaultRenderer, .win32)
    }

    func testServiceRegistryProvidesBuiltInServicesAndScopedStorage() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("emulator-app-sdk-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let manifest = EmulatorAppManifest(
            appID: "example.service-test",
            displayName: "Service Test",
            supportedRenderers: [.text],
            requiredCapabilities: [.clock, .logging, .storage, .clipboard]
        )
        let registry = EmulatorHostServiceRegistry(
            rendererMode: .text,
            foundationRootPath: tempRoot.path,
            environment: ["EMULATOR_APP_DATA_ROOT": tempRoot.path]
        )

        let report = registry.validationReport(for: manifest)
        XCTAssertTrue(report.launchable)
        XCTAssertEqual(report.statuses.count, 4)
        XCTAssertEqual(report.statuses.first(where: { $0.capability == .clock })?.availability, .available)
        XCTAssertEqual(report.statuses.first(where: { $0.capability == .clipboard })?.availability, .degraded)

        let services = try registry.makeServices(for: manifest)
        XCTAssertTrue(services.storage.rootPath.contains("example.service-test"))

        try services.storage.writeString("42", forKey: "launch-count.txt")
        XCTAssertEqual(try services.storage.readString(forKey: "launch-count.txt"), "42")

        services.logging.log(.info, "service test log")
        let logPath = URL(fileURLWithPath: services.storage.rootPath).appendingPathComponent("host.log").path
        let logContents = try String(contentsOfFile: logPath, encoding: .utf8)
        XCTAssertTrue(logContents.contains("service test log"))
    }

    func testBluetoothCapabilityFallsBackToMockInTextMode() throws {
        let manifest = EmulatorAppManifest(
            appID: "example.bluetooth",
            displayName: "Bluetooth Test",
            supportedRenderers: [.text],
            requiredCapabilities: [.bluetooth]
        )
        let registry = EmulatorHostServiceRegistry(rendererMode: .text)

        let report = registry.validationReport(for: manifest)
        XCTAssertTrue(report.launchable)
        XCTAssertEqual(report.statuses.first?.capability, .bluetooth)
        XCTAssertEqual(report.statuses.first?.availability, .degraded)
        XCTAssertTrue(report.statuses.first?.message.contains("mock backend") == true)

        let services = try registry.makeServices(for: manifest)
        XCTAssertEqual(services.bluetooth.backendMode, .mock)
    }

    func testWinRTRequirementFailsWhenLiveBackendCannotLaunch() {
        let manifest = EmulatorAppManifest(
            appID: "example.bluetooth.winrt",
            displayName: "WinRT Bluetooth",
            supportedRenderers: [.text],
            requiredCapabilities: [.bluetooth]
        )
        let registry = EmulatorHostServiceRegistry(rendererMode: .text, bluetoothBackendMode: .winrt)

        let report = registry.validationReport(for: manifest)
        XCTAssertFalse(report.launchable)
        XCTAssertEqual(report.unavailableCapabilities.map(\.capability), [.bluetooth])
        XCTAssertThrowsError(try registry.makeServices(for: manifest))
    }

    func testMockBluetoothServiceSupportsGattFlowAndNotifications() async throws {
        let service = MockBluetoothService()

        XCTAssertEqual(service.adapterState(), .poweredOn)

        let peripherals = try await service.scan(filter: EmulatorBluetoothScanFilter(namePrefix: "Mock"), timeoutMilliseconds: 10)
        let peripheral = try XCTUnwrap(peripherals.first)
        try await service.connect(to: peripheral.id)

        let services = try await service.discoverServices(for: peripheral.id)
        let serviceUUID = try XCTUnwrap(services.first)
        let characteristics = try await service.discoverCharacteristics(for: peripheral.id, serviceUUID: serviceUUID)
        let notifyingCharacteristic = try XCTUnwrap(characteristics.first(where: { $0.properties.contains(.notify) }))
        let writableCharacteristic = try XCTUnwrap(characteristics.first(where: { $0.properties.contains(.writeWithoutResponse) }))

        let readValue = try await service.readValue(for: notifyingCharacteristic, peripheralID: peripheral.id)
        XCTAssertFalse(readValue.isEmpty)

        try await service.writeValue(
            Data("ping".utf8),
            for: writableCharacteristic,
            peripheralID: peripheral.id,
            mode: .withoutResponse
        )

        let stream = try await service.subscribe(to: notifyingCharacteristic, peripheralID: peripheral.id)
        var iterator = stream.makeAsyncIterator()
        let notification = try await iterator.next()

        XCTAssertEqual(String(decoding: notification?.value ?? Data(), as: UTF8.self), "speed=128;lap=1")
        await service.disconnect(from: peripheral.id)
    }

    func testLifecycleControllerRunnerCallsStartAndStop() throws {
        let controller = LifecycleProbeController()

        try EmulatorLifecycleControllerRunner.startIfNeeded(controller)
        EmulatorLifecycleControllerRunner.stopIfNeeded(controller)

        XCTAssertEqual(controller.events, ["start", "stop"])
    }

    func testBufferedInvalidationServiceFlushesPendingRequest() {
        let invalidation = BufferedUIInvalidationService()
        var callCount = 0

        invalidation.requestRedraw()
        invalidation.bind {
            callCount += 1
        }
        invalidation.requestRedraw()

        XCTAssertEqual(callCount, 2)
    }

    func testManifestResolvesDeviceEnvironmentForPresetAndOrientation() {
        let manifest = EmulatorAppManifest(
            appID: "example.device",
            displayName: "Device",
            defaultViewport: .graphicalPhone,
            defaultDevicePreset: .tablet,
            defaultOrientation: .landscape,
            supportedRenderers: [.text, .win32]
        )

        let renderEnvironment = manifest.resolvedRenderEnvironment(rendererMode: .win32)

        XCTAssertEqual(renderEnvironment.device.preset, .tablet)
        XCTAssertEqual(renderEnvironment.device.orientation, .landscape)
        XCTAssertEqual(renderEnvironment.device.viewport, DeviceViewport(width: 1024, height: 768))
        XCTAssertGreaterThan(renderEnvironment.device.safeAreaInsets.leading, 0)
    }

    func testEnvironmentAwareControllerBridgeFallsBackToLegacyDocument() {
        let controller = LegacyProbeController()
        let environment = EmulatorAppManifest(
            appID: "example.legacy",
            displayName: "Legacy",
            supportedRenderers: [.text]
        ).resolvedRenderEnvironment(rendererMode: .text)

        let document = EmulatorAppControllerBridge.makeDocument(from: controller, environment: environment)

        XCTAssertEqual(document.title, "Legacy Probe")
    }

    func testEnvironmentAwareControllerBridgePrefersEnvironmentDocumentAndLifecycleEvents() {
        let controller = EnvironmentProbeController()
        let environmentState = EmulatorRenderEnvironmentState(
            manifest: EmulatorAppManifest(
                appID: "example.environment",
                displayName: "Environment",
                defaultDevicePreset: .phoneCompact,
                supportedRenderers: [.win32]
            ),
            rendererMode: .win32,
            devicePresetOverride: .tablet,
            orientationOverride: .landscape
        )
        let environment = environmentState.snapshot()

        let document = EmulatorAppControllerBridge.makeDocument(from: controller, environment: environment)
        EmulatorLifecycleControllerRunner.emitIfNeeded(.didEnterBackground, on: controller)

        XCTAssertEqual(document.title, "tablet-landscape")
        XCTAssertEqual(controller.events, ["background"])
    }
}

private final class LifecycleProbeController: EmulatorLifecycleAwareAppController {
    var events: [String] = []

    func start() throws {
        events.append("start")
    }

    func stop() {
        events.append("stop")
    }

    func makeDocument() -> ScreenDocument {
        UI.screen(title: "Probe") {
            UI.text("Probe", style: .headline)
        }
    }

    @discardableResult
    func handle(action: UIActionID) -> Bool {
        false
    }
}

private final class LegacyProbeController: EmulatorAppController {
    func makeDocument() -> ScreenDocument {
        UI.screen(title: "Legacy Probe") {
            UI.text("Legacy")
        }
    }

    @discardableResult
    func handle(action: UIActionID) -> Bool {
        false
    }
}

private final class EnvironmentProbeController: EmulatorRenderEnvironmentAwareAppController, EmulatorLifecycleEventAwareAppController {
    var events: [String] = []

    func makeDocument() -> ScreenDocument {
        UI.screen(title: "Legacy") {
            UI.text("Legacy")
        }
    }

    func makeDocument(environment: EmulatorRenderEnvironment) -> ScreenDocument {
        UI.screen(
            title: "\(environment.device.preset.rawValue)-\(environment.device.orientation.rawValue)",
            rootLayoutMode: .safeArea,
            safeAreaInsets: environment.device.safeAreaInsets
        ) {
            UI.text(environment.rendererMode.rawValue)
        }
    }

    @discardableResult
    func handle(action: UIActionID) -> Bool {
        false
    }

    func handle(lifecycleEvent: EmulatorLifecycleEvent) {
        switch lifecycleEvent {
        case .didEnterBackground:
            events.append("background")
        default:
            break
        }
    }
}
