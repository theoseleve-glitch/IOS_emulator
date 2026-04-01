import EmulatorAppSDK
import Foundation

public enum DeviceShowcaseRegistration: EmulatorAppRegistration {
    public static let manifest = EmulatorAppManifest(
        appID: "example.device-showcase",
        displayName: "Device Showcase",
        defaultViewport: .graphicalPhone,
        defaultDevicePreset: .phoneCompact,
        defaultOrientation: .portrait,
        supportedRenderers: [.text, .win32]
    )

    public static func makeController() -> any EmulatorAppController {
        DeviceShowcaseController()
    }
}

private enum DeviceShowcaseRoute: Hashable, Sendable {
    case overview
    case focusLab
    case detail(String)
}

private enum DeviceShowcaseAction {
    static let back = "showcase.nav.back"
    static let openFocusLab = "showcase.nav.focusLab"
    static let openOverview = "showcase.nav.overview"

    static func openDetail(_ id: String) -> UIActionID {
        "showcase.detail.open:\(id)"
    }
}

public final class DeviceShowcaseController: EmulatorRenderEnvironmentAwareAppController, EmulatorInputAwareAppController, EmulatorLifecycleEventAwareAppController, @unchecked Sendable {
    private var route = NavigationPathState(root: DeviceShowcaseRoute.overview)
    private var selection = ListSelectionState<String>()
    private var lifecycleLabel = "Foreground"
    private var lastInputLabel = "none"
    private var transitionCount = 0
    private var rotationCount = 0

    private let examples: [ExampleCard] = [
        ExampleCard(id: "safe-area", title: "Safe Area", subtitle: "Insets come from the emulator device environment."),
        ExampleCard(id: "orientation", title: "Orientation", subtitle: "Landscape swaps the summary and control panes."),
        ExampleCard(id: "lifecycle", title: "Lifecycle", subtitle: "Foreground and background events update the visible banner."),
    ]

    public init() {}

    public func makeDocument() -> ScreenDocument {
        makeDocument(
            environment: DeviceShowcaseRegistration.manifest.resolvedRenderEnvironment(rendererMode: .win32)
        )
    }

    public func makeDocument(environment: EmulatorRenderEnvironment) -> ScreenDocument {
        UI.screen(
            title: "Device Showcase",
            backgroundColor: .canvas,
            rootLayoutMode: .safeArea,
            safeAreaInsets: environment.device.safeAreaInsets
        ) {
            UI.navigationStack(
                title: title(for: route.current),
                canGoBack: route.canGoBack,
                backAction: route.canGoBack ? DeviceShowcaseAction.back : nil
            ) {
                body(for: route.current, environment: environment)
            }
        }
    }

    @discardableResult
    public func handle(action: UIActionID) -> Bool {
        switch action {
        case DeviceShowcaseAction.back:
            _ = route.pop()
            return true
        case DeviceShowcaseAction.openFocusLab:
            route.push(.focusLab)
            return true
        case DeviceShowcaseAction.openOverview:
            route.popToRoot()
            return true
        default:
            guard action.hasPrefix("showcase.detail.open:") else {
                return false
            }
            let id = String(action.dropFirst("showcase.detail.open:".count))
            selection.select(id)
            route.push(.detail(id))
            return true
        }
    }

    @discardableResult
    public func handle(input: EmulatorInputEvent) -> Bool {
        lastInputLabel = input.rawValue
        if input == .back, route.canGoBack {
            _ = route.pop()
            return true
        }
        return false
    }

    public func handle(lifecycleEvent: EmulatorLifecycleEvent) {
        switch lifecycleEvent {
        case .didLaunch:
            lifecycleLabel = "Launched"
        case .didEnterForeground:
            lifecycleLabel = "Foreground"
            transitionCount += 1
        case .didEnterBackground:
            lifecycleLabel = "Background"
            transitionCount += 1
        case .willTerminate:
            lifecycleLabel = "Terminating"
        case .deviceEnvironmentChanged(let deviceEnvironment):
            lifecycleLabel = "Changed to \(deviceEnvironment.orientation.rawValue)"
            rotationCount += 1
        }
    }

    private func title(for route: DeviceShowcaseRoute) -> String {
        switch route {
        case .overview:
            return "Overview"
        case .focusLab:
            return "Focus Lab"
        case .detail(let id):
            return examples.first(where: { $0.id == id })?.title ?? "Detail"
        }
    }

    private func body(for route: DeviceShowcaseRoute, environment: EmulatorRenderEnvironment) -> RenderNode {
        switch route {
        case .overview:
            return overview(environment: environment)
        case .focusLab:
            return focusLab(environment: environment)
        case .detail(let id):
            return detail(id: id, environment: environment)
        }
    }

    private func overview(environment: EmulatorRenderEnvironment) -> RenderNode {
        let summary = summaryPanel(environment: environment)
        let cards = UI.vStack(spacing: 14) {
            UI.text("Keyboard focus can move across both buttons and list rows.", style: .caption)
            UI.hStack(spacing: 12) {
                UI.frame(fillsWidth: true, alignment: .center, UI.button("Focus Lab", action: DeviceShowcaseAction.openFocusLab))
                UI.frame(fillsWidth: true, alignment: .center, UI.button("Overview", action: DeviceShowcaseAction.openOverview, style: .secondary))
            }
            UI.list(
                items: examples.map {
                    ListItemModel(
                        id: $0.id,
                        title: $0.title,
                        subtitle: $0.subtitle,
                        action: DeviceShowcaseAction.openDetail($0.id)
                    )
                },
                selectedID: selection.selectedID
            )
        }

        return UI.padding(.uniform(20), UI.vStack(spacing: 18) {
            lifecycleBanner(environment: environment)
            if environment.device.orientation == .portrait {
                summary
                cards
            } else {
                UI.hStack(spacing: 16) {
                    UI.frame(width: max(220, Double(environment.device.viewport.width) * 0.32), summary)
                    UI.frame(fillsWidth: true, alignment: .leading, cards)
                }
            }
        })
    }

    private func focusLab(environment: EmulatorRenderEnvironment) -> RenderNode {
        UI.padding(.uniform(20), UI.vStack(spacing: 18) {
            lifecycleBanner(environment: environment)
            UI.text("Tab, Shift+Tab, arrows, Enter, Space, and Escape are the first keyboard layer in block 6.", style: .body)
            UI.hStack(spacing: 12) {
                UI.frame(fillsWidth: true, alignment: .center, UI.button("Safe Area Detail", action: DeviceShowcaseAction.openDetail("safe-area")))
                UI.frame(fillsWidth: true, alignment: .center, UI.button("Lifecycle Detail", action: DeviceShowcaseAction.openDetail("lifecycle"), style: .secondary))
            }
            UI.hStack(spacing: 12) {
                UI.frame(fillsWidth: true, alignment: .center, UI.button("Orientation Detail", action: DeviceShowcaseAction.openDetail("orientation"), style: .secondary))
                UI.frame(fillsWidth: true, alignment: .center, UI.button("Back", action: DeviceShowcaseAction.back, style: .plain))
            }
            UI.text("Last input: \(lastInputLabel)", style: .caption)
        })
    }

    private func detail(id: String, environment: EmulatorRenderEnvironment) -> RenderNode {
        let card = examples.first(where: { $0.id == id }) ?? examples[0]
        return UI.padding(.uniform(20), UI.vStack(spacing: 18) {
            lifecycleBanner(environment: environment)
            UI.text(card.title, style: .title)
            UI.text(card.subtitle, style: .body)
            UI.gauge(
                label: "Orientation changes seen",
                value: Double(rotationCount),
                range: 0...4,
                unit: "evt",
                accentColor: .accentStrong
            )
            UI.text("Use Escape or the Back button to return to the previous route.", style: .caption)
            UI.frame(fillsWidth: true, alignment: .center, UI.button("Back", action: DeviceShowcaseAction.back, style: .plain))
        })
    }

    private func summaryPanel(environment: EmulatorRenderEnvironment) -> RenderNode {
        UI.vStack(spacing: 10) {
            UI.text("Preset: \(environment.device.preset.rawValue)", style: .headline)
            UI.text("Orientation: \(environment.device.orientation.rawValue)", style: .caption)
            UI.text("Viewport: \(environment.device.viewport.width)x\(environment.device.viewport.height)", style: .caption)
            UI.text("Safe area top: \(Int(environment.device.safeAreaInsets.top))", style: .caption)
            UI.text("Lifecycle transitions: \(transitionCount)", style: .caption)
        }
    }

    private func lifecycleBanner(environment: EmulatorRenderEnvironment) -> RenderNode {
        UI.frame(
            fillsWidth: true,
            alignment: .leading,
            UI.padding(
                UIInsets(top: 10, leading: 12, bottom: 10, trailing: 12),
                UI.text(
                    "State: \(lifecycleLabel) | Renderer: \(environment.rendererMode.rawValue) | Last input: \(lastInputLabel)",
                    style: .caption
                )
            )
        )
    }
}

private struct ExampleCard {
    let id: String
    let title: String
    let subtitle: String
}
