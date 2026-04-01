import EmulatorAppSDK
import Foundation

public enum StarterTelemetryRegistration: EmulatorServiceAwareAppRegistration {
    public static let manifest = EmulatorAppManifest(
        appID: "example.starter-telemetry",
        displayName: "Starter Telemetry",
        defaultViewport: .graphicalPhone,
        supportedRenderers: [.text, .win32],
        requiredCapabilities: [.clock, .logging, .storage],
        preferredLocales: ["en", "fr"]
    )

    public static func makeController() -> any EmulatorAppController {
        makeController(services: .defaults(appID: manifest.appID, rendererMode: manifest.defaultRenderer))
    }

    public static func makeController(services: EmulatorHostServices) -> any EmulatorAppController {
        StarterTelemetryController(services: services)
    }
}

private enum StarterRoute: Hashable, Sendable {
    case dashboard
    case sessions
    case sessionDetail(String)
}

private enum StarterAction {
    static let openSessions = "starter.nav.sessions"
    static let back = "starter.nav.back"
    static let boost = "starter.telemetry.boost"
    static let cool = "starter.telemetry.cool"
    static let toggleRecorder = "starter.recorder.toggle"

    static func openSession(_ id: String) -> UIActionID {
        "starter.session.open:\(id)"
    }
}

public final class StarterTelemetryController: EmulatorAppController {
    private let assets = EmulatorAssetCatalog(bundle: .module)
    private let services: EmulatorHostServices
    private let banner: RasterImageAsset
    private let accent: UIColor
    private let success: UIColor
    private let loadedAt: String
    private var launchCount: Int
    private var route = NavigationPathState(root: StarterRoute.dashboard)
    private var selection = ListSelectionState<String>()
    private var speed = 142.0
    private var recorderEnabled = false

    private let sessions: [SessionSummary] = [
        SessionSummary(id: "session-01", titleKey: "sessions.first", subtitleKey: "sessions.first.subtitle", speed: 138),
        SessionSummary(id: "session-02", titleKey: "sessions.second", subtitleKey: "sessions.second.subtitle", speed: 151),
        SessionSummary(id: "session-03", titleKey: "sessions.third", subtitleKey: "sessions.third.subtitle", speed: 126),
    ]

    public init(services: EmulatorHostServices = .defaults(appID: StarterTelemetryRegistration.manifest.appID, rendererMode: StarterTelemetryRegistration.manifest.defaultRenderer)) {
        self.services = services
        guard let banner = assets.image(named: "telemetry-banner") else {
            fatalError("Missing telemetry-banner.png in StarterTelemetryApp resources.")
        }

        self.banner = banner
        self.accent = assets.color(named: "telemetryAccent") ?? .accentStrong
        self.success = assets.color(named: "telemetrySuccess") ?? .success
        self.loadedAt = Self.formatTime(services.clock.now)
        self.launchCount = Self.readLaunchCount(from: services.storage)
        self.launchCount += 1
        try? services.storage.writeString(String(launchCount), forKey: "launch-count.txt")
        services.logging.log(.info, "Initialized StarterTelemetry launch #\(launchCount).")
    }

    public func makeDocument() -> ScreenDocument {
        UI.screen(title: text("app.title")) {
            UI.navigationStack(
                title: navigationTitle,
                canGoBack: route.canGoBack,
                backAction: route.canGoBack ? StarterAction.back : nil
            ) {
                body(for: route.current)
            }
        }
    }

    @discardableResult
    public func handle(action: UIActionID) -> Bool {
        switch action {
        case StarterAction.openSessions:
            route.push(.sessions)
            services.logging.log(.debug, "Opened sessions list.")
            return true
        case StarterAction.back:
            _ = route.pop()
            services.logging.log(.debug, "Navigated back.")
            return true
        case StarterAction.boost:
            speed = min(220, speed + 10)
            services.logging.log(.debug, "Boosted telemetry speed to \(Int(speed)).")
            return true
        case StarterAction.cool:
            speed = max(0, speed - 10)
            services.logging.log(.debug, "Reduced telemetry speed to \(Int(speed)).")
            return true
        case StarterAction.toggleRecorder:
            recorderEnabled.toggle()
            services.logging.log(.info, recorderEnabled ? "Recorder enabled." : "Recorder disabled.")
            return true
        default:
            guard action.hasPrefix("starter.session.open:") else {
                return false
            }

            let id = String(action.dropFirst("starter.session.open:".count))
            selection.select(id)
            route.push(.sessionDetail(id))
            services.logging.log(.debug, "Opened session detail for \(id).")
            return true
        }
    }

    private var navigationTitle: String {
        switch route.current {
        case .dashboard:
            return text("nav.dashboard")
        case .sessions:
            return text("nav.sessions")
        case .sessionDetail(let id):
            return sessions.first(where: { $0.id == id }).map { text($0.titleKey) } ?? text("nav.sessions")
        }
    }

    private func body(for route: StarterRoute) -> RenderNode {
        switch route {
        case .dashboard:
            return dashboard()
        case .sessions:
            return sessionsScreen()
        case .sessionDetail(let id):
            return sessionDetail(id: id)
        }
    }

    private func dashboard() -> RenderNode {
        UI.padding(.uniform(20), UI.vStack(spacing: 18) {
            UI.frame(height: 144, fillsWidth: true, alignment: .center, UI.image(banner, accessibilityLabel: text("hero.alt")))
            UI.text(text("hero.headline"), style: .headline)
            UI.text(text(recorderEnabled ? "hero.mode.recording" : "hero.mode.preview"), style: .caption)
            UI.text("\(text("dashboard.launchCount")): \(launchCount)", style: .caption)
            UI.text("\(text("dashboard.loadedAt")): \(loadedAt)", style: .caption)
            UI.gauge(
                label: text("dashboard.speed"),
                value: speed,
                range: 0...220,
                unit: "km/h",
                accentColor: recorderEnabled ? accent : success
            )
            UI.hStack(spacing: 12) {
                UI.frame(fillsWidth: true, alignment: .center, UI.button(text("dashboard.cool"), action: StarterAction.cool, style: .secondary))
                UI.frame(fillsWidth: true, alignment: .center, UI.button(text("dashboard.boost"), action: StarterAction.boost))
            }
            UI.hStack(spacing: 12) {
                UI.frame(fillsWidth: true, alignment: .center, UI.button(text("dashboard.sessions"), action: StarterAction.openSessions, style: .secondary))
                UI.frame(fillsWidth: true, alignment: .center, UI.button(text(recorderEnabled ? "dashboard.stop" : "dashboard.record"), action: StarterAction.toggleRecorder))
            }
        })
    }

    private func sessionsScreen() -> RenderNode {
        UI.padding(.uniform(20), UI.vStack(spacing: 18) {
            UI.text(text("sessions.headline"), style: .headline)
            UI.text(text("sessions.caption"), style: .caption)
            UI.list(
                items: sessions.map {
                    ListItemModel(
                        id: $0.id,
                        title: text($0.titleKey),
                        subtitle: text($0.subtitleKey),
                        action: StarterAction.openSession($0.id)
                    )
                },
                selectedID: selection.selectedID
            )
        })
    }

    private func sessionDetail(id: String) -> RenderNode {
        let session = sessions.first(where: { $0.id == id }) ?? sessions[0]
        return UI.padding(.uniform(20), UI.vStack(spacing: 18) {
            UI.text(text(session.titleKey), style: .title)
            UI.text(text(session.subtitleKey), style: .caption)
            UI.gauge(
                label: text("detail.average"),
                value: session.speed,
                range: 0...220,
                unit: "km/h",
                accentColor: accent
            )
            UI.text(text("detail.caption"), style: .body)
            UI.frame(fillsWidth: true, alignment: .center, UI.button(text("detail.back"), action: StarterAction.back, style: .plain))
        })
    }

    private func text(_ key: String) -> String {
        assets.localizedString(key)
    }

    private static func readLaunchCount(from storage: any EmulatorStorageService) -> Int {
        guard
            let rawValue = try? storage.readString(forKey: "launch-count.txt"),
            let parsed = Int(rawValue.trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            return 0
        }

        return parsed
    }

    private static func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

private struct SessionSummary {
    let id: String
    let titleKey: String
    let subtitleKey: String
    let speed: Double
}
