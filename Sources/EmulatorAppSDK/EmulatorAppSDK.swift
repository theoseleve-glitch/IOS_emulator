@_exported import RendererCore
import Foundation

public enum EmulatorRendererMode: String, CaseIterable, Codable, Hashable, Sendable {
    case text
    case win32
}

public struct EmulatorAppManifest: Equatable, Sendable {
    public let appID: String
    public let displayName: String
    public let defaultViewport: DeviceViewport
    public let defaultDevicePreset: EmulatorDevicePreset?
    public let defaultOrientation: EmulatorDeviceOrientation
    public let supportedRenderers: Set<EmulatorRendererMode>
    public let requiredCapabilities: Set<EmulatorCapability>
    public let preferredLocales: [String]

    public init(
        appID: String,
        displayName: String,
        defaultViewport: DeviceViewport = .graphicalPhone,
        defaultDevicePreset: EmulatorDevicePreset? = nil,
        defaultOrientation: EmulatorDeviceOrientation = .portrait,
        supportedRenderers: Set<EmulatorRendererMode> = Set(EmulatorRendererMode.allCases),
        requiredCapabilities: Set<EmulatorCapability> = [],
        preferredLocales: [String] = []
    ) {
        self.appID = appID
        self.displayName = displayName
        self.defaultViewport = defaultViewport
        self.defaultDevicePreset = defaultDevicePreset
        self.defaultOrientation = defaultOrientation
        self.supportedRenderers = supportedRenderers
        self.requiredCapabilities = requiredCapabilities
        self.preferredLocales = preferredLocales
    }
}

public extension EmulatorAppManifest {
    var defaultRenderer: EmulatorRendererMode {
        if supportedRenderers.contains(.win32) {
            return .win32
        }

        return supportedRenderers.first ?? .text
    }
}

public protocol EmulatorAppController: AnyObject {
    func makeDocument() -> ScreenDocument
    @discardableResult
    func handle(action: UIActionID) -> Bool
}

public protocol EmulatorRenderEnvironmentAwareAppController: EmulatorAppController {
    func makeDocument(environment: EmulatorRenderEnvironment) -> ScreenDocument
}

public protocol EmulatorInputAwareAppController: EmulatorAppController {
    @discardableResult
    func handle(input: EmulatorInputEvent) -> Bool
}

public protocol EmulatorLifecycleEventAwareAppController: EmulatorAppController {
    func handle(lifecycleEvent: EmulatorLifecycleEvent)
}

public protocol EmulatorAppRegistration {
    static var manifest: EmulatorAppManifest { get }
    static func makeController() -> any EmulatorAppController
}

public protocol EmulatorServiceAwareAppRegistration: EmulatorAppRegistration {
    static func makeController(services: EmulatorHostServices) -> any EmulatorAppController
}

public enum EmulatorAppRegistrationResolver {
    public static func makeController<Registration: EmulatorAppRegistration>(
        for registration: Registration.Type,
        services: EmulatorHostServices
    ) -> any EmulatorAppController {
        if let serviceAwareRegistration = registration as? any EmulatorServiceAwareAppRegistration.Type {
            return serviceAwareRegistration.makeController(services: services)
        }

        return registration.makeController()
    }
}

public enum EmulatorAssetCatalogError: Error, Equatable {
    case bundleNotFound(String)
    case invalidColorsJSON
    case invalidStringsJSON
}

public final class EmulatorAssetCatalog: @unchecked Sendable {
    private let bundle: Bundle
    private let fileManager: FileManager
    private var colorsCache: [String: UIColor]?
    private var stringsCache: [String: [String: String]] = [:]

    public init(bundle: Bundle, fileManager: FileManager = .default) {
        self.bundle = bundle
        self.fileManager = fileManager
    }

    public func image(named name: String) -> RasterImageAsset? {
        guard let url = locateResource(named: name, withExtension: "png") else {
            return nil
        }

        return RasterImageAsset(name: name, filePath: url.path)
    }

    public func color(named name: String) -> UIColor? {
        if colorsCache == nil {
            colorsCache = (try? loadColors()) ?? [:]
        }

        return colorsCache?[name]
    }

    public func localizedString(_ key: String, locale: String? = nil) -> String {
        let preferredLocales = resolvedLocales(from: locale)
        for candidate in preferredLocales {
            if let table = stringsTable(for: candidate), let value = table[key] {
                return value
            }
        }

        return key
    }

    private func loadColors() throws -> [String: UIColor] {
        guard let url = locateResource(named: "Colors", withExtension: "json") else {
            return [:]
        }

        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let mapping = object as? [String: Any] else {
            throw EmulatorAssetCatalogError.invalidColorsJSON
        }

        var colors: [String: UIColor] = [:]
        for (name, rawValue) in mapping {
            if let value = rawValue as? String, let color = Self.parseHexColor(value) {
                colors[name] = color
                continue
            }

            if
                let channels = rawValue as? [String: Any],
                let red = channels["red"] as? Double,
                let green = channels["green"] as? Double,
                let blue = channels["blue"] as? Double
            {
                let alpha = channels["alpha"] as? Double ?? 1.0
                colors[name] = UIColor(red: red, green: green, blue: blue, alpha: alpha)
                continue
            }
        }

        return colors
    }

    private func stringsTable(for locale: String) -> [String: String]? {
        if let cached = stringsCache[locale] {
            return cached
        }

        guard let url = locateStringTable(for: locale) else {
            stringsCache[locale] = [:]
            return nil
        }

        guard
            let data = try? Data(contentsOf: url),
            let object = try? JSONSerialization.jsonObject(with: data),
            let table = object as? [String: String]
        else {
            stringsCache[locale] = [:]
            return nil
        }

        stringsCache[locale] = table
        return table
    }

    private func resolvedLocales(from requestedLocale: String?) -> [String] {
        var locales: [String] = []

        if let requestedLocale, !requestedLocale.isEmpty {
            locales.append(requestedLocale)
            if let separator = requestedLocale.firstIndex(where: { $0 == "-" || $0 == "_" }) {
                locales.append(String(requestedLocale[..<separator]))
            }
        }

        if let preferred = Locale.preferredLanguages.first, !preferred.isEmpty {
            locales.append(preferred)
            if let separator = preferred.firstIndex(where: { $0 == "-" || $0 == "_" }) {
                locales.append(String(preferred[..<separator]))
            }
        }

        locales.append("en")
        return Array(NSOrderedSet(array: locales).compactMap { $0 as? String })
    }

    private func locateStringTable(for locale: String) -> URL? {
        if let direct = bundle.url(forResource: locale, withExtension: "json", subdirectory: "Strings") {
            return direct
        }

        if let recursive = recursiveResourceURL(matchingFileName: "\(locale).json") {
            return recursive
        }

        return bundle.url(forResource: locale, withExtension: "json")
    }

    private func locateResource(named name: String, withExtension ext: String) -> URL? {
        if let direct = bundle.url(forResource: name, withExtension: ext) {
            return direct
        }

        return recursiveResourceURL(matchingFileName: "\(name).\(ext)")
    }

    private func recursiveResourceURL(matchingFileName fileName: String) -> URL? {
        let searchRoots = [bundle.resourceURL, bundle.bundleURL].compactMap { $0 }
        for root in searchRoots {
            let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            while let url = enumerator?.nextObject() as? URL {
                if url.lastPathComponent.caseInsensitiveCompare(fileName) == .orderedSame {
                    return url
                }
            }
        }

        return nil
    }

    private static func parseHexColor(_ value: String) -> UIColor? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let hex = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        let scanner = Scanner(string: hex)
        var number: UInt64 = 0

        guard scanner.scanHexInt64(&number) else {
            return nil
        }

        switch hex.count {
        case 6:
            return UIColor(
                red: Double((number & 0xFF0000) >> 16) / 255.0,
                green: Double((number & 0x00FF00) >> 8) / 255.0,
                blue: Double(number & 0x0000FF) / 255.0,
                alpha: 1.0
            )
        case 8:
            return UIColor(
                red: Double((number & 0xFF000000) >> 24) / 255.0,
                green: Double((number & 0x00FF0000) >> 16) / 255.0,
                blue: Double((number & 0x0000FF00) >> 8) / 255.0,
                alpha: Double(number & 0x000000FF) / 255.0
            )
        default:
            return nil
        }
    }
}
