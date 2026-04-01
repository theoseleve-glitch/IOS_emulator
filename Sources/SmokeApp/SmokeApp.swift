import Foundation
import RendererCore
import RuntimeCore

public final class SmokeAppModule: AppModule {
    public static let moduleIdentifier = "smoke-app"
    public static let descriptor = AppModuleDescriptor(
        identifier: moduleIdentifier,
        displayName: "Smoke App",
        makeModule: { SmokeAppModule() }
    )

    public let identifier = SmokeAppModule.moduleIdentifier

    public init() {}

    public func start(context: RuntimeContext) throws {
        try context.fileSystem.createDirectoryIfNeeded(at: context.workingDirectory)
        context.log(.info, "app start: \(identifier)")
        context.log(.debug, "working directory ready: \(context.workingDirectory)")
    }

    public func stop(context: RuntimeContext) throws {
        context.log(.info, "app stop: \(identifier)")
    }

    public func makeDashboardDocument() -> ScreenDocument {
        SmokeDemoState().makeDocument()
    }
}
