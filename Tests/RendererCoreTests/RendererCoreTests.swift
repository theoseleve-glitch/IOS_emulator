import XCTest
@testable import RendererCore

final class RendererCoreTests: XCTestCase {
    func testVerticalStackLayoutRespectsSpacing() throws {
        let document = UI.screen(title: "Layout") {
            UI.vStack(spacing: 10) {
                UI.text("First")
                UI.text("Second")
            }
        }

        let output = RenderPipeline.makeDisplayList(for: document, in: DeviceViewport(width: 240, height: 180))
        let stack = try XCTUnwrap(firstNode(in: output.layoutTree) {
            if case .vStack = $0.element {
                return true
            }
            return false
        })

        XCTAssertEqual(stack.children.count, 2)
        XCTAssertEqual(stack.children[1].frame.minY, stack.children[0].frame.maxY + 10, accuracy: 0.5)
    }

    func testHorizontalStackDistributesFlexibleSpacer() throws {
        let document = UI.screen(title: "Spacer") {
            UI.hStack(spacing: 10) {
                UI.text("Left")
                UI.spacer(minLength: 8)
                UI.text("Right")
            }
        }

        let output = RenderPipeline.makeDisplayList(for: document, in: DeviceViewport(width: 320, height: 120))
        let stack = try XCTUnwrap(firstNode(in: output.layoutTree) {
            if case .hStack = $0.element {
                return true
            }
            return false
        })
        let spacer = try XCTUnwrap(firstNode(in: stack) {
            if case .spacer = $0.element {
                return true
            }
            return false
        })

        XCTAssertGreaterThan(spacer.frame.width, 8)
        XCTAssertGreaterThan(stack.children[2].frame.minX, stack.children[0].frame.maxX)
    }

    func testPaddingAndFrameLayoutStayStableAcrossViewportResize() {
        let document = UI.screen(title: "Resize") {
            UI.padding(.uniform(16), UI.frame(fillsWidth: true, alignment: .center, UI.button("Resize Me", action: "resize")))
        }

        let narrow = RenderPipeline.makeDisplayList(for: document, in: DeviceViewport(width: 220, height: 180))
        let wide = RenderPipeline.makeDisplayList(for: document, in: DeviceViewport(width: 360, height: 180))

        XCTAssertEqual(narrow.commands.count, wide.commands.count)
        XCTAssertEqual(narrow.layoutTree.frame.width, 220, accuracy: 0.1)
        XCTAssertEqual(wide.layoutTree.frame.width, 360, accuracy: 0.1)
    }

    func testInteractionRouterReturnsButtonAction() throws {
        let document = UI.screen(title: "Actions") {
            UI.padding(.uniform(20), UI.button("Tap Me", action: "tap.primary"))
        }

        let output = RenderPipeline.makeDisplayList(for: document, in: DeviceViewport(width: 260, height: 160))
        let button = try XCTUnwrap(firstNode(in: output.layoutTree) {
            if case .button = $0.element {
                return true
            }
            return false
        })
        let center = UIPoint(x: button.frame.minX + (button.frame.width / 2), y: button.frame.minY + (button.frame.height / 2))

        XCTAssertEqual(InteractionRouter.action(at: center, in: output), "tap.primary")
    }

    func testGaugeNormalizationAndListSelectionState() {
        let gauge = GaugeModel(label: "Speed", value: 110, range: 0...220, unit: "km/h")
        var selection = ListSelectionState<String>()

        selection.select("session-02")

        XCTAssertEqual(gauge.normalizedValue, 0.5, accuracy: 0.0001)
        XCTAssertEqual(selection.selectedID, "session-02")
    }

    func testImageNodeGeneratesDeterministicDrawCommand() {
        let asset = RasterImageAsset(name: "banner", filePath: "C:/example/banner.png")
        let document = UI.screen(title: "Image") {
            UI.frame(width: 120, height: 64, UI.image(asset))
        }

        let output = RenderPipeline.makeDisplayList(for: document, in: DeviceViewport(width: 240, height: 180))

        XCTAssertTrue(output.commands.contains(.image(assetName: "banner", assetPath: "C:/example/banner.png", rect: UIRect(origin: UIPoint(x: 0, y: 0), size: UISize(width: 120, height: 64)))))
    }

    func testSafeAreaRootLayoutInsetsContentFrame() throws {
        let document = UI.screen(
            title: "Safe Area",
            rootLayoutMode: .safeArea,
            safeAreaInsets: UIInsets(top: 10, leading: 8, bottom: 6, trailing: 8)
        ) {
            UI.frame(fillsWidth: true, fillsHeight: true, UI.text("Inset content"))
        }

        let output = RenderPipeline.makeDisplayList(for: document, in: DeviceViewport(width: 240, height: 160))
        let content = try XCTUnwrap(output.layoutTree.children.first)

        XCTAssertEqual(content.frame.minX, 8, accuracy: 0.1)
        XCTAssertEqual(content.frame.minY, 10, accuracy: 0.1)
        XCTAssertEqual(content.frame.width, 224, accuracy: 0.1)
        XCTAssertEqual(content.frame.height, 144, accuracy: 0.1)
    }

    func testFocusNavigatorCyclesAndMovesSpatially() {
        let document = UI.screen(title: "Focus") {
            UI.vStack(spacing: 12) {
                UI.button("Alpha", action: "action.alpha")
                UI.hStack(spacing: 12) {
                    UI.button("Beta", action: "action.beta")
                    UI.button("Gamma", action: "action.gamma")
                }
            }
        }

        let output = RenderPipeline.makeDisplayList(for: document, in: DeviceViewport(width: 320, height: 240))

        XCTAssertEqual(FocusNavigator.firstAction(in: output), "action.alpha")
        XCTAssertEqual(FocusNavigator.action(for: .next, from: nil, in: output), "action.alpha")
        XCTAssertEqual(FocusNavigator.action(for: .next, from: "action.alpha", in: output), "action.beta")
        XCTAssertEqual(FocusNavigator.action(for: .previous, from: "action.alpha", in: output), "action.gamma")
        XCTAssertEqual(FocusNavigator.action(for: .right, from: "action.beta", in: output), "action.gamma")
        XCTAssertEqual(FocusNavigator.action(for: .up, from: "action.beta", in: output), "action.alpha")
    }

    func testTextFieldAndGestureSurfaceProduceFocusableRegions() {
        let document = UI.screen(title: "Input") {
            UI.vStack(spacing: 12) {
                UI.textField(id: "field.primary", text: "GO", placeholder: "Type", caretIndex: 2, submitAction: "submit.primary")
                UI.gestureSurface(id: "gesture.pad", UI.frame(width: 120, height: 80, UI.text("Pad")))
            }
        }

        let output = RenderPipeline.makeDisplayList(
            for: document,
            in: DeviceViewport(width: 320, height: 220),
            focusedTarget: .textField("field.primary")
        )

        XCTAssertTrue(output.focusRegions.contains { $0.target == FocusableTarget.textField("field.primary") })
        XCTAssertTrue(output.focusRegions.contains { $0.target == FocusableTarget.gestureSurface("gesture.pad") })
        XCTAssertTrue(output.commands.contains { command in
            if case .line = command { return true }
            return false
        }, "Focused text field should emit a caret line draw command.")
    }

    private func firstNode(in node: LayoutNode, matching predicate: (LayoutNode) -> Bool) -> LayoutNode? {
        if predicate(node) {
            return node
        }

        for child in node.children {
            if let match = firstNode(in: child, matching: predicate) {
                return match
            }
        }

        return nil
    }
}
