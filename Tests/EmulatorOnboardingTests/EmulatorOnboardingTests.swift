import Foundation
import XCTest
@testable import EmulatorOnboarding

final class EmulatorOnboardingTests: XCTestCase {
    func testLoadConfigurationParsesExpectedFields() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(atPath: root) }

        let configPath = URL(fileURLWithPath: root).appendingPathComponent("EmulatorApp.json")
        try """
        {
          "product": "ExampleProduct",
          "module": "ExampleModule",
          "registrationType": "ExampleRegistration"
        }
        """.write(to: configPath, atomically: true, encoding: .utf8)

        let configuration = try EmulatorOnboarding.loadConfiguration(at: root)

        XCTAssertEqual(configuration, ExternalAppConfiguration(
            product: "ExampleProduct",
            module: "ExampleModule",
            registrationType: "ExampleRegistration"
        ))
    }

    func testPrepareRunnerWorkspaceWritesPackageAndSourceFiles() throws {
        let foundationRoot = try makeTemporaryDirectory()
        let appRoot = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(atPath: foundationRoot)
            try? FileManager.default.removeItem(atPath: appRoot)
        }

        try """
        {
          "product": "ExampleProduct",
          "module": "ExampleModule",
          "registrationType": "ExampleRegistration"
        }
        """.write(
            to: URL(fileURLWithPath: appRoot).appendingPathComponent("EmulatorApp.json"),
            atomically: true,
            encoding: .utf8
        )

        let workspace = try EmulatorOnboarding.prepareRunnerWorkspace(
            foundationPackagePath: foundationRoot,
            appPackagePath: appRoot
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: URL(fileURLWithPath: workspace.rootPath).appendingPathComponent("Package.swift").path))
        let packageSource = try String(
            contentsOf: URL(fileURLWithPath: workspace.rootPath).appendingPathComponent("Package.swift"),
            encoding: .utf8
        )
        let mainSource = try String(
            contentsOf: URL(fileURLWithPath: workspace.rootPath)
                .appendingPathComponent("Sources")
                .appendingPathComponent(workspace.executableName)
                .appendingPathComponent("main.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(packageSource.contains("ExampleProduct"))
        XCTAssertTrue(packageSource.contains(foundationRoot.replacingOccurrences(of: "\\", with: "/")))
        XCTAssertTrue(packageSource.contains(appRoot.replacingOccurrences(of: "\\", with: "/")))
        XCTAssertTrue(packageSource.contains(".product(name: \"EmulatorOnboarding\""))
        XCTAssertTrue(mainSource.contains("import ExampleModule"))
        XCTAssertTrue(mainSource.contains("ExampleRegistration"))
        XCTAssertTrue(mainSource.contains("import EmulatorOnboarding"))
        XCTAssertTrue(mainSource.contains("ExternalRunnerSupport.run"))
        XCTAssertTrue(mainSource.contains(appRoot.replacingOccurrences(of: "\\", with: "/")))
    }

    private func makeTemporaryDirectory() throws -> String {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("emulator-onboarding-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        return url.path
    }
}
