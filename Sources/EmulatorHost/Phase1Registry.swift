import RuntimeCore
import SmokeApp

enum Phase1Registry {
    static func make() throws -> AppModuleRegistry {
        try AppModuleRegistry(descriptors: [
            SmokeAppModule.descriptor
        ])
    }
}
