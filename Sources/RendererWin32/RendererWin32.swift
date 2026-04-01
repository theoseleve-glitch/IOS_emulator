import CRendererWin32Shim
import EmulatorAppSDK
import Foundation
import RendererCore

public struct Win32WindowOptions: Sendable {
    public let title: String
    public let width: Int32
    public let height: Int32
    public let autoCloseMilliseconds: Int32
    public let scriptedAction: UIActionID?
    public let scriptedActionDelayMilliseconds: Int32

    public init(
        title: String,
        width: Int32,
        height: Int32,
        autoCloseMilliseconds: Int32 = 0,
        scriptedAction: UIActionID? = nil,
        scriptedActionDelayMilliseconds: Int32 = 0
    ) {
        self.title = title
        self.width = width
        self.height = height
        self.autoCloseMilliseconds = autoCloseMilliseconds
        self.scriptedAction = scriptedAction
        self.scriptedActionDelayMilliseconds = scriptedActionDelayMilliseconds
    }
}

public struct Win32PresentationReport: Sendable {
    public let frameCount: Int
    public let scriptedActionRequested: Bool
    public let scriptedActionDispatched: Bool
    public let focusChangeCount: Int
    public let keyActivationCount: Int
    public let textInputCount: Int
    public let gestureEventCount: Int
}

public enum Win32PresentationEvent: Sendable {
    case windowReady
    case frameGenerated(viewport: DeviceViewport, commandCount: Int, interactionCount: Int)
    case inputReceived(EmulatorInputEvent)
    case textInputReceived(fieldID: UITextFieldID, event: EmulatorTextInputEvent)
    case pointerReceived(surfaceID: UIGestureSurfaceID?, target: FocusableTarget?, event: EmulatorPointerEvent)
    case gestureDispatched(surfaceID: UIGestureSurfaceID, event: EmulatorGestureEvent)
    case focusChanged(FocusableTarget?)
    case actionDispatched(action: UIActionID, source: String)
}

public enum Win32VirtualKey: UInt32, Sendable {
    case tab = 0x09
    case enter = 0x0D
    case escape = 0x1B
    case space = 0x20
    case left = 0x25
    case up = 0x26
    case right = 0x27
    case down = 0x28
    case backspace = 0x08
    case home = 0x24
    case end = 0x23
    case delete = 0x2E
}

public final class Win32RedrawHandle: @unchecked Sendable {
    private let rawHandle: renderer_win32_redraw_handle_t?
    private let textInputDispatcher: ((UITextFieldID, EmulatorTextInputEvent) -> Void)?
    private let gestureDispatcher: ((EmulatorGestureEvent, UIGestureSurfaceID) -> Void)?

    init(
        rawHandle: renderer_win32_redraw_handle_t?,
        textInputDispatcher: ((UITextFieldID, EmulatorTextInputEvent) -> Void)? = nil,
        gestureDispatcher: ((EmulatorGestureEvent, UIGestureSurfaceID) -> Void)? = nil
    ) {
        self.rawHandle = rawHandle
        self.textInputDispatcher = textInputDispatcher
        self.gestureDispatcher = gestureDispatcher
    }

    public func requestRedraw() {
        renderer_win32_request_redraw(rawHandle)
    }

    public func sendKey(_ key: Win32VirtualKey, shiftDown: Bool = false) {
        renderer_win32_send_virtual_key(rawHandle, key.rawValue, shiftDown ? 1 : 0)
    }

    public func sendText(_ text: String) {
        for scalar in text.unicodeScalars {
            renderer_win32_send_character(rawHandle, scalar.value)
        }
    }

    public func dispatchTextInput(_ event: EmulatorTextInputEvent, fieldID: UITextFieldID) {
        textInputDispatcher?(fieldID, event)
        requestRedraw()
    }

    public func sendPointer(
        phase: EmulatorPointerPhase,
        at point: UIPoint,
        modifiers: Set<EmulatorInputModifier> = []
    ) {
        renderer_win32_send_pointer_event(
            rawHandle,
            nativePointerPhase(phase),
            point.x,
            point.y,
            nativeModifierMask(modifiers)
        )
    }

    public func sendWheel(
        delta: Int32,
        at point: UIPoint,
        modifiers: Set<EmulatorInputModifier> = []
    ) {
        renderer_win32_send_wheel_event(
            rawHandle,
            delta,
            point.x,
            point.y,
            nativeModifierMask(modifiers)
        )
    }

    public func dispatchGesture(_ event: EmulatorGestureEvent, on surfaceID: UIGestureSurfaceID) {
        gestureDispatcher?(event, surfaceID)
        requestRedraw()
    }
}

public final class Win32ScreenPresenter {
    public typealias DocumentProvider = @Sendable (DeviceViewport) -> ScreenDocument
    public typealias ActionHandler = @Sendable (UIActionID) -> Void
    public typealias InputHandler = @Sendable (EmulatorInputEvent) -> Bool
    public typealias TextInputHandler = @Sendable (UITextFieldID, EmulatorTextInputEvent) -> Bool
    public typealias PointerHandler = @Sendable (EmulatorPointerEvent, UIGestureSurfaceID?) -> Bool
    public typealias GestureHandler = @Sendable (EmulatorGestureEvent, UIGestureSurfaceID) -> Bool
    public typealias EventHandler = @Sendable (Win32PresentationEvent) -> Void
    public typealias WindowReadyHandler = @Sendable (Win32RedrawHandle) -> Void

    private let documentProvider: DocumentProvider
    private let actionHandler: ActionHandler
    private let inputHandler: InputHandler?
    private let textInputHandler: TextInputHandler?
    private let pointerHandler: PointerHandler?
    private let gestureHandler: GestureHandler?
    private let eventHandler: EventHandler?

    public init(
        documentProvider: @escaping DocumentProvider,
        actionHandler: @escaping ActionHandler,
        inputHandler: InputHandler? = nil,
        textInputHandler: TextInputHandler? = nil,
        pointerHandler: PointerHandler? = nil,
        gestureHandler: GestureHandler? = nil,
        eventHandler: EventHandler? = nil
    ) {
        self.documentProvider = documentProvider
        self.actionHandler = actionHandler
        self.inputHandler = inputHandler
        self.textInputHandler = textInputHandler
        self.pointerHandler = pointerHandler
        self.gestureHandler = gestureHandler
        self.eventHandler = eventHandler
    }

    @discardableResult
    public func run(
        options: Win32WindowOptions,
        onWindowReady: WindowReadyHandler? = nil
    ) throws -> Win32PresentationReport {
        let presenterBox = PresenterBox(
            documentProvider: documentProvider,
            actionHandler: actionHandler,
            inputHandler: inputHandler,
            textInputHandler: textInputHandler,
            pointerHandler: pointerHandler,
            gestureHandler: gestureHandler,
            eventHandler: eventHandler,
            windowReadyHandler: onWindowReady
        )
        let context = Unmanaged.passUnretained(presenterBox).toOpaque()
        var callbacks = renderer_win32_callbacks_t()
        callbacks.context = context
        callbacks.make_frame = rendererWin32MakeFrame
        callbacks.release_frame = rendererWin32ReleaseFrame
        callbacks.on_action = rendererWin32HandleAction
        callbacks.on_input = rendererWin32HandleInput
        callbacks.on_text_input = rendererWin32HandleTextInput
        callbacks.on_pointer = rendererWin32HandlePointer
        callbacks.on_gesture = rendererWin32HandleGesture
        callbacks.on_window_ready = rendererWin32WindowReady

        var report = renderer_win32_run_report_t()
        let exitCode = withNativeString(options.title) { titleString in
            withOptionalNativeString(options.scriptedAction) { scriptedAction in
                var runOptions = renderer_win32_run_options_t()
                runOptions.window_title = titleString
                runOptions.width = options.width
                runOptions.height = options.height
                runOptions.auto_close_ms = options.autoCloseMilliseconds
                runOptions.scripted_action = scriptedAction
                runOptions.scripted_action_delay_ms = options.scriptedActionDelayMilliseconds
                return renderer_win32_run_window(callbacks, runOptions, &report)
            }
        }

        if exitCode != 0 {
            throw NSError(domain: "Win32ScreenPresenter", code: Int(exitCode), userInfo: nil)
        }

        return Win32PresentationReport(
            frameCount: Int(report.frame_count),
            scriptedActionRequested: report.scripted_action_requested != 0,
            scriptedActionDispatched: report.scripted_action_dispatched != 0,
            focusChangeCount: presenterBox.focusChangeCount,
            keyActivationCount: presenterBox.keyActivationCount,
            textInputCount: presenterBox.textInputCount,
            gestureEventCount: presenterBox.gestureEventCount
        )
    }
}

private final class PresenterBox: @unchecked Sendable {
    let documentProvider: Win32ScreenPresenter.DocumentProvider
    let actionHandler: Win32ScreenPresenter.ActionHandler
    let inputHandler: Win32ScreenPresenter.InputHandler?
    let textInputHandler: Win32ScreenPresenter.TextInputHandler?
    let pointerHandler: Win32ScreenPresenter.PointerHandler?
    let gestureHandler: Win32ScreenPresenter.GestureHandler?
    let eventHandler: Win32ScreenPresenter.EventHandler?
    let windowReadyHandler: Win32ScreenPresenter.WindowReadyHandler?

    private(set) var lastOutput: RenderPipelineOutput?
    private(set) var focusedTarget: FocusableTarget?
    private(set) var focusChangeCount = 0
    private(set) var keyActivationCount = 0
    private(set) var textInputCount = 0
    private(set) var gestureEventCount = 0

    init(
        documentProvider: @escaping Win32ScreenPresenter.DocumentProvider,
        actionHandler: @escaping Win32ScreenPresenter.ActionHandler,
        inputHandler: Win32ScreenPresenter.InputHandler?,
        textInputHandler: Win32ScreenPresenter.TextInputHandler?,
        pointerHandler: Win32ScreenPresenter.PointerHandler?,
        gestureHandler: Win32ScreenPresenter.GestureHandler?,
        eventHandler: Win32ScreenPresenter.EventHandler?,
        windowReadyHandler: Win32ScreenPresenter.WindowReadyHandler?
    ) {
        self.documentProvider = documentProvider
        self.actionHandler = actionHandler
        self.inputHandler = inputHandler
        self.textInputHandler = textInputHandler
        self.pointerHandler = pointerHandler
        self.gestureHandler = gestureHandler
        self.eventHandler = eventHandler
        self.windowReadyHandler = windowReadyHandler
    }

    func makeFrame(width: Int32, height: Int32) -> UnsafeMutablePointer<renderer_win32_snapshot_t>? {
        let viewport = DeviceViewport(width: max(1, Int(width)), height: max(1, Int(height)))
        let document = documentProvider(viewport)
        let output = RenderPipeline.makeDisplayList(
            for: document,
            in: viewport,
            focusedTarget: focusedTarget
        )
        lastOutput = output
        eventHandler?(.frameGenerated(viewport: viewport, commandCount: output.commands.count, interactionCount: output.interactions.count))
        return ManagedSnapshot.makePointer(document: document, output: output)
    }

    func releaseFrame(_ snapshot: UnsafeMutablePointer<renderer_win32_snapshot_t>?) {
        ManagedSnapshot.releasePointer(snapshot)
    }

    func handleAction(_ action: UIActionID, source: String) {
        setFocusedTarget(.action(action))
        actionHandler(action)
        eventHandler?(.actionDispatched(action: action, source: source))
    }

    @discardableResult
    func handleInput(_ input: EmulatorInputEvent) -> Bool {
        eventHandler?(.inputReceived(input))
        if let inputHandler, inputHandler(input) {
            return true
        }

        guard let output = lastOutput else {
            return false
        }

        switch input {
        case .focusNext:
            return setFocusedTarget(FocusNavigator.target(for: .next, from: focusedTarget, in: output))
        case .focusPrevious:
            return setFocusedTarget(FocusNavigator.target(for: .previous, from: focusedTarget, in: output))
        case .moveUp:
            return setFocusedTarget(FocusNavigator.target(for: .up, from: focusedTarget, in: output))
        case .moveDown:
            return setFocusedTarget(FocusNavigator.target(for: .down, from: focusedTarget, in: output))
        case .moveLeft:
            return setFocusedTarget(FocusNavigator.target(for: .left, from: focusedTarget, in: output))
        case .moveRight:
            return setFocusedTarget(FocusNavigator.target(for: .right, from: focusedTarget, in: output))
        case .activateFocused:
            return activateFocused()
        case .back:
            if let action = output.defaultBackAction {
                keyActivationCount += 1
                handleAction(action, source: "keyboard")
                return true
            }
            return false
        }
    }

    @discardableResult
    func handleTextInput(_ fieldID: UITextFieldID, event: EmulatorTextInputEvent) -> Bool {
        textInputCount += 1
        setFocusedTarget(.textField(fieldID))
        eventHandler?(.textInputReceived(fieldID: fieldID, event: event))

        if let textInputHandler, textInputHandler(fieldID, event) {
            return true
        }

        guard case .submit = event, let submitAction = textFieldModel(id: fieldID)?.submitAction else {
            return false
        }

        keyActivationCount += 1
        handleAction(submitAction, source: "textSubmit")
        return true
    }

    @discardableResult
    func handlePointer(_ event: EmulatorPointerEvent, target: FocusableTarget?) -> Bool {
        let surfaceID = target.flatMap {
            if case .gestureSurface(let surfaceID) = $0 { return surfaceID }
            return nil
        }
        eventHandler?(.pointerReceived(surfaceID: surfaceID, target: target, event: event))
        let focusChanged = setFocusedTarget(target)
        let handled = pointerHandler?(event, surfaceID) ?? false
        return handled || focusChanged
    }

    @discardableResult
    func handleGesture(_ event: EmulatorGestureEvent, surfaceID: UIGestureSurfaceID) -> Bool {
        gestureEventCount += 1
        setFocusedTarget(.gestureSurface(surfaceID))
        eventHandler?(.gestureDispatched(surfaceID: surfaceID, event: event))
        return gestureHandler?(event, surfaceID) ?? false
    }

    func windowReady(_ handle: Win32RedrawHandle) {
        eventHandler?(.windowReady)
        windowReadyHandler?(handle)
    }

    @discardableResult
    private func setFocusedTarget(_ target: FocusableTarget?) -> Bool {
        guard focusedTarget != target else {
            return false
        }
        focusedTarget = target
        focusChangeCount += 1
        eventHandler?(.focusChanged(target))
        return true
    }

    private func activateFocused() -> Bool {
        guard let focusedTarget else {
            return false
        }

        switch focusedTarget {
        case .action(let action):
            keyActivationCount += 1
            handleAction(action, source: "keyboard")
            return true
        case .textField(let fieldID):
            return handleTextInput(fieldID, event: .submit)
        case .gestureSurface:
            return false
        }
    }

    private func textFieldModel(id: UITextFieldID) -> UITextFieldModel? {
        guard let layoutTree = lastOutput?.layoutTree else {
            return nil
        }
        return findTextField(in: layoutTree, id: id)
    }

    private func findTextField(in node: LayoutNode, id: UITextFieldID) -> UITextFieldModel? {
        if case .textField(let textField) = node.element, textField.id == id {
            return textField
        }
        for child in node.children {
            if let match = findTextField(in: child, id: id) {
                return match
            }
        }
        return nil
    }
}

private final class ManagedCString {
    let bytes: [UInt8]
    let pointer: UnsafePointer<CChar>?
    let length: UInt32

    init(_ value: String) {
        let encoded = Array(value.utf8) + [0]
        self.bytes = encoded
        self.length = UInt32(max(0, encoded.count - 1))
        self.pointer = encoded.withUnsafeBufferPointer { buffer in
            buffer.baseAddress.map { UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self) }
        }
    }

    var native: renderer_win32_string_t {
        renderer_win32_string_t(data: pointer, length: length)
    }
}

private final class ManagedSnapshot {
    private let titleStorage: ManagedCString
    private let fontStorages: [ManagedCString]
    private let textStorages: [ManagedCString]
    private let imageNameStorages: [ManagedCString]
    private let imagePathStorages: [ManagedCString]
    private let interactionStorages: [ManagedCString]
    private let focusStorages: [ManagedCString]
    private let commands: [renderer_win32_command_t]
    private let interactions: [renderer_win32_interaction_t]
    private let focusRegions: [renderer_win32_focus_region_t]
    private let commandPointer: UnsafePointer<renderer_win32_command_t>?
    private let interactionPointer: UnsafePointer<renderer_win32_interaction_t>?
    private let focusRegionPointer: UnsafePointer<renderer_win32_focus_region_t>?

    private init(document: ScreenDocument, output: RenderPipelineOutput) {
        titleStorage = ManagedCString(document.title)

        var fontStorages: [ManagedCString] = []
        var textStorages: [ManagedCString] = []
        var imageNameStorages: [ManagedCString] = []
        var imagePathStorages: [ManagedCString] = []
        var commands: [renderer_win32_command_t] = []

        for command in output.commands {
            switch command {
            case .fill(let rect, let color, let cornerRadius):
                commands.append(renderer_win32_command_t(
                    kind: Int32(RENDERER_WIN32_COMMAND_FILL),
                    rect: nativeRect(rect),
                    from_point: renderer_win32_point_t(),
                    to_point: renderer_win32_point_t(),
                    color: nativeColor(color),
                    line_width: 0,
                    corner_radius: cornerRadius,
                    text: renderer_win32_string_t(),
                    image_name: renderer_win32_string_t(),
                    image_path: renderer_win32_string_t(),
                    text_style: renderer_win32_text_style_t()
                ))
            case .stroke(let rect, let color, let lineWidth, let cornerRadius):
                commands.append(renderer_win32_command_t(
                    kind: Int32(RENDERER_WIN32_COMMAND_STROKE),
                    rect: nativeRect(rect),
                    from_point: renderer_win32_point_t(),
                    to_point: renderer_win32_point_t(),
                    color: nativeColor(color),
                    line_width: lineWidth,
                    corner_radius: cornerRadius,
                    text: renderer_win32_string_t(),
                    image_name: renderer_win32_string_t(),
                    image_path: renderer_win32_string_t(),
                    text_style: renderer_win32_text_style_t()
                ))
            case .line(let from, let to, let color, let lineWidth):
                commands.append(renderer_win32_command_t(
                    kind: Int32(RENDERER_WIN32_COMMAND_LINE),
                    rect: renderer_win32_rect_t(),
                    from_point: nativePoint(from),
                    to_point: nativePoint(to),
                    color: nativeColor(color),
                    line_width: lineWidth,
                    corner_radius: 0,
                    text: renderer_win32_string_t(),
                    image_name: renderer_win32_string_t(),
                    image_path: renderer_win32_string_t(),
                    text_style: renderer_win32_text_style_t()
                ))
            case .text(let value, let rect, let style):
                let textStorage = ManagedCString(value)
                let fontStorage = ManagedCString(style.font.family)
                textStorages.append(textStorage)
                fontStorages.append(fontStorage)
                commands.append(renderer_win32_command_t(
                    kind: Int32(RENDERER_WIN32_COMMAND_TEXT),
                    rect: nativeRect(rect),
                    from_point: renderer_win32_point_t(),
                    to_point: renderer_win32_point_t(),
                    color: renderer_win32_color_t(),
                    line_width: 0,
                    corner_radius: 0,
                    text: textStorage.native,
                    image_name: renderer_win32_string_t(),
                    image_path: renderer_win32_string_t(),
                    text_style: renderer_win32_text_style_t(
                        font_family: fontStorage.native,
                        font_size: style.font.size,
                        font_weight: nativeFontWeight(style.font.weight),
                        horizontal_alignment: nativeAlignment(style.alignment),
                        color: nativeColor(style.color)
                    )
                ))
            case .image(let assetName, let assetPath, let rect):
                let imageNameStorage = ManagedCString(assetName)
                let imagePathStorage = ManagedCString(assetPath)
                imageNameStorages.append(imageNameStorage)
                imagePathStorages.append(imagePathStorage)
                commands.append(renderer_win32_command_t(
                    kind: Int32(RENDERER_WIN32_COMMAND_IMAGE),
                    rect: nativeRect(rect),
                    from_point: renderer_win32_point_t(),
                    to_point: renderer_win32_point_t(),
                    color: renderer_win32_color_t(),
                    line_width: 0,
                    corner_radius: 0,
                    text: renderer_win32_string_t(),
                    image_name: imageNameStorage.native,
                    image_path: imagePathStorage.native,
                    text_style: renderer_win32_text_style_t()
                ))
            }
        }

        var interactionStorages: [ManagedCString] = []
        let interactions = output.interactions.map { interaction -> renderer_win32_interaction_t in
            let storage = ManagedCString(interaction.action)
            interactionStorages.append(storage)
            return renderer_win32_interaction_t(rect: nativeRect(interaction.rect), action: storage.native)
        }

        var focusStorages: [ManagedCString] = []
        let focusRegions = output.focusRegions.map { region -> renderer_win32_focus_region_t in
            let identifier = focusIdentifier(for: region.target)
            let storage = ManagedCString(identifier)
            focusStorages.append(storage)
            return renderer_win32_focus_region_t(
                rect: nativeRect(region.rect),
                kind: nativeFocusKind(region.target),
                identifier: storage.native,
                is_focused: output.focusedTarget == region.target ? 1 : 0
            )
        }

        self.fontStorages = fontStorages
        self.textStorages = textStorages
        self.imageNameStorages = imageNameStorages
        self.imagePathStorages = imagePathStorages
        self.interactionStorages = interactionStorages
        self.focusStorages = focusStorages
        self.commands = commands
        self.interactions = interactions
        self.focusRegions = focusRegions
        self.commandPointer = commands.withUnsafeBufferPointer { $0.baseAddress }
        self.interactionPointer = interactions.withUnsafeBufferPointer { $0.baseAddress }
        self.focusRegionPointer = focusRegions.withUnsafeBufferPointer { $0.baseAddress }
    }

    static func makePointer(
        document: ScreenDocument,
        output: RenderPipelineOutput
    ) -> UnsafeMutablePointer<renderer_win32_snapshot_t>? {
        let managed = ManagedSnapshot(document: document, output: output)
        let pointer = UnsafeMutablePointer<renderer_win32_snapshot_t>.allocate(capacity: 1)
        let retained = Unmanaged.passRetained(managed)
        pointer.initialize(
            to: renderer_win32_snapshot_t(
                user_data: retained.toOpaque(),
                title: managed.titleStorage.native,
                background_color: screenBackgroundColor(for: output.layoutTree),
                viewport_width: Int32(output.viewport.width),
                viewport_height: Int32(output.viewport.height),
                commands: managed.commandPointer,
                command_count: UInt32(managed.commands.count),
                interactions: managed.interactionPointer,
                interaction_count: UInt32(managed.interactions.count),
                focus_regions: managed.focusRegionPointer,
                focus_region_count: UInt32(managed.focusRegions.count)
            )
        )
        return pointer
    }

    static func releasePointer(_ pointer: UnsafeMutablePointer<renderer_win32_snapshot_t>?) {
        guard let pointer else {
            return
        }
        if let userData = pointer.pointee.user_data {
            Unmanaged<ManagedSnapshot>.fromOpaque(userData).release()
        }
        pointer.deinitialize(count: 1)
        pointer.deallocate()
    }
}

private func screenBackgroundColor(for layoutTree: LayoutNode) -> renderer_win32_color_t {
    if case .screen(_, let backgroundColor) = layoutTree.element {
        return nativeColor(backgroundColor)
    }
    return nativeColor(.canvas)
}

private func focusIdentifier(for target: FocusableTarget) -> String {
    switch target {
    case .action(let action):
        return action
    case .textField(let fieldID):
        return fieldID
    case .gestureSurface(let surfaceID):
        return surfaceID
    }
}

private func nativeFocusKind(_ target: FocusableTarget) -> Int32 {
    switch target {
    case .action:
        return Int32(RENDERER_WIN32_FOCUS_ACTION)
    case .textField:
        return Int32(RENDERER_WIN32_FOCUS_TEXT_FIELD)
    case .gestureSurface:
        return Int32(RENDERER_WIN32_FOCUS_GESTURE_SURFACE)
    }
}

private func nativePoint(_ point: UIPoint) -> renderer_win32_point_t {
    renderer_win32_point_t(x: point.x, y: point.y)
}

private func nativeRect(_ rect: UIRect) -> renderer_win32_rect_t {
    renderer_win32_rect_t(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
}

private func nativeColor(_ color: UIColor) -> renderer_win32_color_t {
    renderer_win32_color_t(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
}

private func nativeFontWeight(_ weight: FontWeight) -> Int32 {
    switch weight {
    case .regular:
        return 400
    case .semibold:
        return 600
    case .bold:
        return 700
    }
}

private func nativeAlignment(_ alignment: HorizontalAlignment) -> Int32 {
    switch alignment {
    case .leading:
        return 0
    case .center:
        return 1
    case .trailing:
        return 2
    }
}

private func nativePointerPhase(_ phase: EmulatorPointerPhase) -> Int32 {
    switch phase {
    case .down:
        return Int32(RENDERER_WIN32_POINTER_DOWN)
    case .move:
        return Int32(RENDERER_WIN32_POINTER_MOVE)
    case .up:
        return Int32(RENDERER_WIN32_POINTER_UP)
    case .cancel:
        return Int32(RENDERER_WIN32_POINTER_CANCEL)
    }
}

private func nativeModifierMask(_ modifiers: Set<EmulatorInputModifier>) -> Int32 {
    var mask: Int32 = 0
    if modifiers.contains(.shift) { mask |= 1 }
    if modifiers.contains(.control) { mask |= 2 }
    if modifiers.contains(.alt) { mask |= 4 }
    return mask
}

private func withNativeString<Result>(
    _ value: String,
    _ body: (renderer_win32_string_t) -> Result
) -> Result {
    let storage = ManagedCString(value)
    return body(storage.native)
}

private func withOptionalNativeString<Result>(
    _ value: String?,
    _ body: (renderer_win32_string_t) -> Result
) -> Result {
    if let value {
        return withNativeString(value, body)
    }
    return body(renderer_win32_string_t(data: nil, length: 0))
}

private func presenterBox(from context: UnsafeMutableRawPointer?) -> PresenterBox {
    Unmanaged<PresenterBox>.fromOpaque(context!).takeUnretainedValue()
}

private func targetFromNative(kind: Int32, identifier: renderer_win32_string_t) -> FocusableTarget? {
    guard identifier.data != nil else {
        return nil
    }
    let identifierValue = stringFromNative(identifier)
    switch kind {
    case Int32(RENDERER_WIN32_FOCUS_ACTION):
        return .action(identifierValue)
    case Int32(RENDERER_WIN32_FOCUS_TEXT_FIELD):
        return .textField(identifierValue)
    case Int32(RENDERER_WIN32_FOCUS_GESTURE_SURFACE):
        return .gestureSurface(identifierValue)
    default:
        return nil
    }
}

private func stringFromNative(_ value: renderer_win32_string_t) -> String {
    guard let data = value.data else {
        return ""
    }
    return String(decoding: UnsafeBufferPointer(start: UnsafeRawPointer(data).assumingMemoryBound(to: UInt8.self), count: Int(value.length)), as: UTF8.self)
}

private func makePointerEvent(from native: renderer_win32_pointer_event_t) -> EmulatorPointerEvent {
    let phase: EmulatorPointerPhase
    switch native.phase {
    case Int32(RENDERER_WIN32_POINTER_DOWN):
        phase = .down
    case Int32(RENDERER_WIN32_POINTER_MOVE):
        phase = .move
    case Int32(RENDERER_WIN32_POINTER_UP):
        phase = .up
    default:
        phase = .cancel
    }
    return EmulatorPointerEvent(
        phase: phase,
        location: UIPoint(x: native.x, y: native.y),
        modifiers: modifiers(from: native.modifiers),
        timestampMilliseconds: UInt64(native.timestamp_ms)
    )
}

private func modifiers(from mask: Int32) -> Set<EmulatorInputModifier> {
    var result: Set<EmulatorInputModifier> = []
    if (mask & 1) != 0 { result.insert(.shift) }
    if (mask & 2) != 0 { result.insert(.control) }
    if (mask & 4) != 0 { result.insert(.alt) }
    return result
}

private func textInputEvent(from native: renderer_win32_text_input_t) -> EmulatorTextInputEvent {
    switch native.kind {
    case Int32(RENDERER_WIN32_TEXT_DELETE_BACKWARD):
        return .deleteBackward
    case Int32(RENDERER_WIN32_TEXT_DELETE_FORWARD):
        return .deleteForward
    case Int32(RENDERER_WIN32_TEXT_MOVE_CARET_LEFT):
        return .moveCaretLeft
    case Int32(RENDERER_WIN32_TEXT_MOVE_CARET_RIGHT):
        return .moveCaretRight
    case Int32(RENDERER_WIN32_TEXT_MOVE_CARET_TO_START):
        return .moveCaretToStart
    case Int32(RENDERER_WIN32_TEXT_MOVE_CARET_TO_END):
        return .moveCaretToEnd
    case Int32(RENDERER_WIN32_TEXT_SUBMIT):
        return .submit
    default:
        return .insertText(stringFromNative(native.text))
    }
}

private func makeGestureEvent(from native: renderer_win32_gesture_event_t) -> EmulatorGestureEvent {
    switch native.kind {
    case Int32(RENDERER_WIN32_GESTURE_DRAG_BEGAN):
        return .dragBegan(start: UIPoint(x: native.start_x, y: native.start_y), current: UIPoint(x: native.current_x, y: native.current_y))
    case Int32(RENDERER_WIN32_GESTURE_DRAG_CHANGED):
        return .dragChanged(start: UIPoint(x: native.start_x, y: native.start_y), current: UIPoint(x: native.current_x, y: native.current_y))
    case Int32(RENDERER_WIN32_GESTURE_DRAG_ENDED):
        return .dragEnded(start: UIPoint(x: native.start_x, y: native.start_y), end: UIPoint(x: native.current_x, y: native.current_y))
    case Int32(RENDERER_WIN32_GESTURE_LONG_PRESS):
        return .longPress(location: UIPoint(x: native.current_x, y: native.current_y))
    case Int32(RENDERER_WIN32_GESTURE_PINCH):
        return .pinch(delta: native.delta, location: UIPoint(x: native.current_x, y: native.current_y))
    case Int32(RENDERER_WIN32_GESTURE_ROTATE):
        return .rotate(deltaDegrees: native.delta * 7.5, location: UIPoint(x: native.current_x, y: native.current_y))
    default:
        let direction: EmulatorSwipeDirection
        switch native.direction {
        case 1: direction = .right
        case 2: direction = .left
        case 3: direction = .down
        default: direction = .up
        }
        return .swipe(
            direction: direction,
            start: UIPoint(x: native.start_x, y: native.start_y),
            end: UIPoint(x: native.current_x, y: native.current_y)
        )
    }
}

private func decodeInputEvent(from native: Int32) -> EmulatorInputEvent? {
    switch native {
    case Int32(RENDERER_WIN32_INPUT_FOCUS_NEXT): return .focusNext
    case Int32(RENDERER_WIN32_INPUT_FOCUS_PREVIOUS): return .focusPrevious
    case Int32(RENDERER_WIN32_INPUT_MOVE_UP): return .moveUp
    case Int32(RENDERER_WIN32_INPUT_MOVE_DOWN): return .moveDown
    case Int32(RENDERER_WIN32_INPUT_MOVE_LEFT): return .moveLeft
    case Int32(RENDERER_WIN32_INPUT_MOVE_RIGHT): return .moveRight
    case Int32(RENDERER_WIN32_INPUT_ACTIVATE_FOCUSED): return .activateFocused
    case Int32(RENDERER_WIN32_INPUT_BACK): return .back
    default: return nil
    }
}

private func rendererWin32MakeFrame(
    context: UnsafeMutableRawPointer?,
    width: Int32,
    height: Int32
) -> UnsafeMutablePointer<renderer_win32_snapshot_t>? {
    presenterBox(from: context).makeFrame(width: width, height: height)
}

private func rendererWin32ReleaseFrame(
    context: UnsafeMutableRawPointer?,
    snapshot: UnsafeMutablePointer<renderer_win32_snapshot_t>?
) {
    presenterBox(from: context).releaseFrame(snapshot)
}

private func rendererWin32HandleAction(
    context: UnsafeMutableRawPointer?,
    action: renderer_win32_string_t
) {
    presenterBox(from: context).handleAction(stringFromNative(action), source: "pointer")
}

private func rendererWin32HandleInput(
    context: UnsafeMutableRawPointer?,
    inputEvent: Int32
) -> Int32 {
    guard let event = decodeInputEvent(from: inputEvent) else {
        return 0
    }
    return presenterBox(from: context).handleInput(event) ? 1 : 0
}

private func rendererWin32HandleTextInput(
    context: UnsafeMutableRawPointer?,
    inputEvent: renderer_win32_text_input_t
) -> Int32 {
    let fieldID = stringFromNative(inputEvent.field_id)
    return presenterBox(from: context).handleTextInput(fieldID, event: textInputEvent(from: inputEvent)) ? 1 : 0
}

private func rendererWin32HandlePointer(
    context: UnsafeMutableRawPointer?,
    pointerEvent: renderer_win32_pointer_event_t
) -> Int32 {
    let target = targetFromNative(kind: pointerEvent.target_kind, identifier: pointerEvent.target_identifier)
    return presenterBox(from: context).handlePointer(makePointerEvent(from: pointerEvent), target: target) ? 1 : 0
}

private func rendererWin32HandleGesture(
    context: UnsafeMutableRawPointer?,
    gestureEvent: renderer_win32_gesture_event_t
) -> Int32 {
    let surfaceID = stringFromNative(gestureEvent.surface_id)
    guard !surfaceID.isEmpty else {
        return 0
    }
    return presenterBox(from: context).handleGesture(makeGestureEvent(from: gestureEvent), surfaceID: surfaceID) ? 1 : 0
}

private func rendererWin32WindowReady(
    context: UnsafeMutableRawPointer?,
    handle: renderer_win32_redraw_handle_t?
) {
    let box = presenterBox(from: context)
    box.windowReady(
        Win32RedrawHandle(
            rawHandle: handle,
            textInputDispatcher: { fieldID, event in
                _ = box.handleTextInput(fieldID, event: event)
            },
            gestureDispatcher: { event, surfaceID in
                _ = box.handleGesture(event, surfaceID: surfaceID)
            }
        )
    )
}
