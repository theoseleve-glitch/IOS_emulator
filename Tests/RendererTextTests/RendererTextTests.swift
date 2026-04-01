import XCTest
@testable import RendererCore
@testable import RendererText
@testable import SmokeApp

final class RendererTextTests: XCTestCase {
    func testTerminalRendererIncludesTitleGaugeAndButtons() {
        let renderer = TerminalRenderer()
        let document = SmokeAppModule().makeDashboardDocument()

        let rendered = renderer.render(document, in: .terminalPhone)

        XCTAssertTrue(rendered.contains("lap_mobile smoke"))
        XCTAssertTrue(rendered.contains("Speed"))
        XCTAssertTrue(rendered.contains("[ Sessions ]"))
        XCTAssertTrue(rendered.contains("[ Controls ]"))
    }

    func testRendererHonorsViewportHeight() {
        let renderer = TerminalRenderer()
        let document = UI.screen(title: "Viewport") {
            UI.vStack {
                UI.text("line 1")
                UI.text("line 2")
            }
        }

        let rendered = renderer.render(document, in: DeviceViewport(width: 24, height: 8))

        XCTAssertEqual(rendered.split(separator: "\n", omittingEmptySubsequences: false).count, 8)
    }

    func testRendererIncludesListRowsFromSharedPipeline() {
        let renderer = TerminalRenderer()
        let state = SmokeDemoState()
        XCTAssertTrue(state.handle(action: SmokeDemoAction.openSessions))
        let rendered = renderer.render(state.makeDocument(), in: .terminalPhone)

        XCTAssertTrue(rendered.contains("Sessions"))
        XCTAssertTrue(rendered.contains("Session 01"))
    }

    func testRendererShowsReadableImagePlaceholder() {
        let renderer = TerminalRenderer()
        let document = UI.screen(title: "Images") {
            UI.image(RasterImageAsset(name: "hero", filePath: "C:/example/hero.png"))
        }

        let rendered = renderer.render(document, in: .terminalPhone)

        XCTAssertTrue(rendered.contains("[image: hero]"))
    }
}
