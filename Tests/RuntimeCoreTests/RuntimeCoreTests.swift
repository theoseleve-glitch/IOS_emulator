import XCTest
@testable import RuntimeCore

private final class TestAppModule: AppModule {
    let identifier: String

    init(identifier: String) {
        self.identifier = identifier
    }

    func start(context: RuntimeContext) throws {}
    func stop(context: RuntimeContext) throws {}
}

final class RuntimeCoreTests: XCTestCase {
    func testBootConfigurationUsesStableDefaults() {
        let configuration = BootConfiguration(appModule: "sample")

        XCTAssertEqual(configuration.appModule, "sample")
        XCTAssertEqual(configuration.logLevel, .info)
        XCTAssertFalse(configuration.workingDirectory.isEmpty)
    }

    func testRegistryResolvesDescriptorsByIdentifier() throws {
        let registry = try AppModuleRegistry(descriptors: [
            AppModuleDescriptor(
                identifier: "sample-app",
                displayName: "Sample App",
                makeModule: { TestAppModule(identifier: "sample-app") }
            )
        ])

        let descriptor = try registry.descriptor(for: "sample-app")

        XCTAssertEqual(descriptor.identifier, "sample-app")
        XCTAssertEqual(descriptor.displayName, "Sample App")
        XCTAssertEqual(registry.registeredModules.map(\.identifier), ["sample-app"])
    }

    func testRegistryRejectsDuplicateIdentifiers() {
        XCTAssertThrowsError(try AppModuleRegistry(descriptors: [
            AppModuleDescriptor(
                identifier: "duplicate",
                displayName: "First",
                makeModule: { TestAppModule(identifier: "duplicate") }
            ),
            AppModuleDescriptor(
                identifier: "duplicate",
                displayName: "Second",
                makeModule: { TestAppModule(identifier: "duplicate") }
            )
        ])) { error in
            XCTAssertEqual(error as? AppModuleRegistryError, AppModuleRegistryError.duplicateIdentifier("duplicate"))
        }
    }

    func testRegistryFailsForUnknownModuleLookup() throws {
        let registry = try AppModuleRegistry(descriptors: [
            AppModuleDescriptor(
                identifier: "known",
                displayName: "Known",
                makeModule: { TestAppModule(identifier: "known") }
            )
        ])

        XCTAssertThrowsError(try registry.descriptor(for: "missing")) { error in
            XCTAssertEqual(error as? AppModuleRegistryError, AppModuleRegistryError.moduleNotFound("missing"))
        }
    }
}
