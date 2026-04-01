import Foundation

public enum EmulatorDevicePreset: String, CaseIterable, Codable, Hashable, Sendable {
    case phoneCompact
    case phoneTall
    case tablet
}

public enum EmulatorDeviceOrientation: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case portrait
    case landscape

    public var toggled: EmulatorDeviceOrientation {
        switch self {
        case .portrait:
            return .landscape
        case .landscape:
            return .portrait
        }
    }
}

public struct EmulatorDeviceEnvironment: Equatable, Sendable {
    public let preset: EmulatorDevicePreset
    public let orientation: EmulatorDeviceOrientation
    public let viewport: DeviceViewport
    public let scale: Double
    public let safeAreaInsets: UIInsets

    public init(
        preset: EmulatorDevicePreset,
        orientation: EmulatorDeviceOrientation,
        viewport: DeviceViewport,
        scale: Double,
        safeAreaInsets: UIInsets
    ) {
        self.preset = preset
        self.orientation = orientation
        self.viewport = viewport
        self.scale = scale
        self.safeAreaInsets = safeAreaInsets
    }
}

public struct EmulatorRenderEnvironment: Equatable, Sendable {
    public let device: EmulatorDeviceEnvironment
    public let rendererMode: EmulatorRendererMode
    public let locale: String

    public init(device: EmulatorDeviceEnvironment, rendererMode: EmulatorRendererMode, locale: String) {
        self.device = device
        self.rendererMode = rendererMode
        self.locale = locale
    }
}

public enum EmulatorInputEvent: String, Codable, Equatable, Sendable {
    case focusNext
    case focusPrevious
    case moveUp
    case moveDown
    case moveLeft
    case moveRight
    case activateFocused
    case back
}

public enum EmulatorLifecycleEvent: Equatable, Sendable {
    case didLaunch
    case didEnterForeground
    case didEnterBackground
    case willTerminate
    case deviceEnvironmentChanged(EmulatorDeviceEnvironment)
}

public extension EmulatorAppManifest {
    func resolvedDeviceEnvironment(
        rendererMode: EmulatorRendererMode,
        devicePresetOverride: EmulatorDevicePreset? = nil,
        orientationOverride: EmulatorDeviceOrientation? = nil,
        viewportOverride: DeviceViewport? = nil
    ) -> EmulatorDeviceEnvironment {
        let orientation = orientationOverride ?? defaultOrientation
        let preset = devicePresetOverride ?? defaultDevicePreset ?? inferredPreset(from: defaultViewport)
        let metrics = presetMetrics(for: preset, rendererMode: rendererMode, orientation: orientation)

        let resolvedViewport: DeviceViewport
        if let viewportOverride {
            resolvedViewport = viewportOverride
        } else if devicePresetOverride == nil && defaultDevicePreset == nil {
            switch rendererMode {
            case .text:
                resolvedViewport = viewport(for: .terminalPhone, orientation: orientation)
            case .win32:
                resolvedViewport = viewport(for: defaultViewport, orientation: orientation)
            }
        } else {
            resolvedViewport = metrics.viewport
        }

        return EmulatorDeviceEnvironment(
            preset: preset,
            orientation: orientation,
            viewport: resolvedViewport,
            scale: metrics.scale,
            safeAreaInsets: metrics.safeAreaInsets
        )
    }

    func resolvedRenderEnvironment(
        rendererMode: EmulatorRendererMode,
        locale: String? = nil,
        devicePresetOverride: EmulatorDevicePreset? = nil,
        orientationOverride: EmulatorDeviceOrientation? = nil,
        viewportOverride: DeviceViewport? = nil
    ) -> EmulatorRenderEnvironment {
        EmulatorRenderEnvironment(
            device: resolvedDeviceEnvironment(
                rendererMode: rendererMode,
                devicePresetOverride: devicePresetOverride,
                orientationOverride: orientationOverride,
                viewportOverride: viewportOverride
            ),
            rendererMode: rendererMode,
            locale: preferredLocale(fallback: locale)
        )
    }

    func preferredLocale(fallback: String? = Locale.preferredLanguages.first) -> String {
        preferredLocales.first ?? fallback ?? "en"
    }
}

public final class EmulatorRenderEnvironmentState: @unchecked Sendable {
    private let manifest: EmulatorAppManifest
    private let rendererMode: EmulatorRendererMode
    private let locale: String
    private let lock = NSLock()
    private var devicePresetOverride: EmulatorDevicePreset?
    private var orientation: EmulatorDeviceOrientation
    private var viewportOverride: DeviceViewport?

    public init(
        manifest: EmulatorAppManifest,
        rendererMode: EmulatorRendererMode,
        devicePresetOverride: EmulatorDevicePreset? = nil,
        orientationOverride: EmulatorDeviceOrientation? = nil,
        locale: String? = nil
    ) {
        self.manifest = manifest
        self.rendererMode = rendererMode
        self.locale = manifest.preferredLocale(fallback: locale)
        self.devicePresetOverride = devicePresetOverride
        self.orientation = orientationOverride ?? manifest.defaultOrientation
    }

    public func snapshot(viewport: DeviceViewport? = nil) -> EmulatorRenderEnvironment {
        lock.withLock {
            if let viewport {
                viewportOverride = viewport
            }

            return manifest.resolvedRenderEnvironment(
                rendererMode: rendererMode,
                locale: locale,
                devicePresetOverride: devicePresetOverride,
                orientationOverride: orientation,
                viewportOverride: viewportOverride
            )
        }
    }

    @discardableResult
    public func rotate() -> EmulatorRenderEnvironment {
        lock.withLock {
            orientation = orientation.toggled
            return manifest.resolvedRenderEnvironment(
                rendererMode: rendererMode,
                locale: locale,
                devicePresetOverride: devicePresetOverride,
                orientationOverride: orientation,
                viewportOverride: viewportOverride
            )
        }
    }

    @discardableResult
    public func updatePreset(_ preset: EmulatorDevicePreset?) -> EmulatorRenderEnvironment {
        lock.withLock {
            devicePresetOverride = preset
            return manifest.resolvedRenderEnvironment(
                rendererMode: rendererMode,
                locale: locale,
                devicePresetOverride: devicePresetOverride,
                orientationOverride: orientation,
                viewportOverride: viewportOverride
            )
        }
    }
}

public enum EmulatorAppControllerBridge {
    public static func makeDocument(
        from controller: any EmulatorAppController,
        environment: EmulatorRenderEnvironment
    ) -> ScreenDocument {
        if let environmentAware = controller as? any EmulatorRenderEnvironmentAwareAppController {
            return environmentAware.makeDocument(environment: environment)
        }

        return controller.makeDocument()
    }

    @discardableResult
    public static func handleInput(
        _ input: EmulatorInputEvent,
        on controller: any EmulatorAppController
    ) -> Bool {
        guard let inputAware = controller as? any EmulatorInputAwareAppController else {
            return false
        }

        return inputAware.handle(input: input)
    }

    public static func handleLifecycleEvent(
        _ event: EmulatorLifecycleEvent,
        on controller: any EmulatorAppController
    ) {
        guard let lifecycleAware = controller as? any EmulatorLifecycleEventAwareAppController else {
            return
        }

        lifecycleAware.handle(lifecycleEvent: event)
    }

    @discardableResult
    public static func handleTextInput(
        _ input: EmulatorTextInputEvent,
        fieldID: UITextFieldID,
        on controller: any EmulatorAppController
    ) -> Bool {
        guard let textInputAware = controller as? any EmulatorTextInputAwareAppController else {
            return false
        }

        return textInputAware.handle(textInput: input, for: fieldID)
    }

    @discardableResult
    public static func handlePointer(
        _ pointer: EmulatorPointerEvent,
        surfaceID: UIGestureSurfaceID?,
        on controller: any EmulatorAppController
    ) -> Bool {
        guard let pointerAware = controller as? any EmulatorPointerAwareAppController else {
            return false
        }

        return pointerAware.handle(pointer: pointer, on: surfaceID)
    }

    @discardableResult
    public static func handleGesture(
        _ gesture: EmulatorGestureEvent,
        surfaceID: UIGestureSurfaceID,
        on controller: any EmulatorAppController
    ) -> Bool {
        guard let gestureAware = controller as? any EmulatorGestureAwareAppController else {
            return false
        }

        return gestureAware.handle(gesture: gesture, on: surfaceID)
    }
}

private struct DevicePresetMetrics {
    let viewport: DeviceViewport
    let scale: Double
    let safeAreaInsets: UIInsets
}

private extension EmulatorAppManifest {
    func inferredPreset(from viewport: DeviceViewport) -> EmulatorDevicePreset {
        let longest = max(viewport.width, viewport.height)
        let shortest = min(viewport.width, viewport.height)

        if longest >= 900 || shortest >= 700 {
            return .tablet
        }
        if longest >= 840 {
            return .phoneTall
        }
        return .phoneCompact
    }

    func presetMetrics(
        for preset: EmulatorDevicePreset,
        rendererMode: EmulatorRendererMode,
        orientation: EmulatorDeviceOrientation
    ) -> DevicePresetMetrics {
        switch rendererMode {
        case .text:
            switch (preset, orientation) {
            case (.phoneCompact, .portrait):
                return DevicePresetMetrics(
                    viewport: DeviceViewport(width: 36, height: 16),
                    scale: 1.0,
                    safeAreaInsets: UIInsets(top: 1, leading: 2, bottom: 1, trailing: 2)
                )
            case (.phoneCompact, .landscape):
                return DevicePresetMetrics(
                    viewport: DeviceViewport(width: 48, height: 14),
                    scale: 1.0,
                    safeAreaInsets: UIInsets(top: 1, leading: 1, bottom: 1, trailing: 1)
                )
            case (.phoneTall, .portrait):
                return DevicePresetMetrics(
                    viewport: DeviceViewport(width: 42, height: 18),
                    scale: 1.0,
                    safeAreaInsets: UIInsets(top: 1, leading: 2, bottom: 1, trailing: 2)
                )
            case (.phoneTall, .landscape):
                return DevicePresetMetrics(
                    viewport: DeviceViewport(width: 54, height: 16),
                    scale: 1.0,
                    safeAreaInsets: UIInsets(top: 1, leading: 1, bottom: 1, trailing: 1)
                )
            case (.tablet, .portrait):
                return DevicePresetMetrics(
                    viewport: DeviceViewport(width: 58, height: 22),
                    scale: 1.0,
                    safeAreaInsets: UIInsets(top: 1, leading: 2, bottom: 1, trailing: 2)
                )
            case (.tablet, .landscape):
                return DevicePresetMetrics(
                    viewport: DeviceViewport(width: 72, height: 18),
                    scale: 1.0,
                    safeAreaInsets: UIInsets(top: 1, leading: 2, bottom: 1, trailing: 2)
                )
            }
        case .win32:
            switch (preset, orientation) {
            case (.phoneCompact, .portrait):
                return DevicePresetMetrics(
                    viewport: DeviceViewport(width: 390, height: 760),
                    scale: 2.0,
                    safeAreaInsets: UIInsets(top: 24, leading: 18, bottom: 20, trailing: 18)
                )
            case (.phoneCompact, .landscape):
                return DevicePresetMetrics(
                    viewport: DeviceViewport(width: 760, height: 390),
                    scale: 2.0,
                    safeAreaInsets: UIInsets(top: 18, leading: 24, bottom: 18, trailing: 24)
                )
            case (.phoneTall, .portrait):
                return DevicePresetMetrics(
                    viewport: DeviceViewport(width: 420, height: 860),
                    scale: 2.0,
                    safeAreaInsets: UIInsets(top: 28, leading: 18, bottom: 22, trailing: 18)
                )
            case (.phoneTall, .landscape):
                return DevicePresetMetrics(
                    viewport: DeviceViewport(width: 860, height: 420),
                    scale: 2.0,
                    safeAreaInsets: UIInsets(top: 18, leading: 28, bottom: 18, trailing: 28)
                )
            case (.tablet, .portrait):
                return DevicePresetMetrics(
                    viewport: DeviceViewport(width: 768, height: 1024),
                    scale: 2.0,
                    safeAreaInsets: UIInsets(top: 24, leading: 24, bottom: 24, trailing: 24)
                )
            case (.tablet, .landscape):
                return DevicePresetMetrics(
                    viewport: DeviceViewport(width: 1024, height: 768),
                    scale: 2.0,
                    safeAreaInsets: UIInsets(top: 24, leading: 24, bottom: 24, trailing: 24)
                )
            }
        }
    }

    func viewport(for viewport: DeviceViewport, orientation: EmulatorDeviceOrientation) -> DeviceViewport {
        switch orientation {
        case .portrait:
            return viewport
        case .landscape:
            return DeviceViewport(width: viewport.height, height: viewport.width)
        }
    }
}
