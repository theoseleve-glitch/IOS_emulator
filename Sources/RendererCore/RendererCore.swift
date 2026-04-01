import Foundation

public typealias UIActionID = String
public typealias UITextFieldID = String
public typealias UIGestureSurfaceID = String

public struct DeviceViewport: Equatable, Sendable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public static let terminalPhone = DeviceViewport(width: 42, height: 18)
    public static let graphicalPhone = DeviceViewport(width: 420, height: 860)
}

public struct UIInsets: Equatable, Sendable {
    public let top: Double
    public let leading: Double
    public let bottom: Double
    public let trailing: Double

    public init(top: Double, leading: Double, bottom: Double, trailing: Double) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }

    public static func uniform(_ value: Double) -> UIInsets {
        UIInsets(top: value, leading: value, bottom: value, trailing: value)
    }

    public static let zero = UIInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
}

public enum HorizontalAlignment: Int, Equatable, Sendable {
    case leading
    case center
    case trailing
}

public enum FontWeight: Int, Equatable, Sendable {
    case regular = 400
    case semibold = 600
    case bold = 700
}

public struct UIColor: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let canvas = UIColor(red: 0.06, green: 0.07, blue: 0.12)
    public static let surface = UIColor(red: 0.11, green: 0.13, blue: 0.20)
    public static let surfaceMuted = UIColor(red: 0.14, green: 0.16, blue: 0.24)
    public static let accent = UIColor(red: 0.14, green: 0.66, blue: 0.97)
    public static let accentStrong = UIColor(red: 0.99, green: 0.43, blue: 0.19)
    public static let textPrimary = UIColor(red: 0.96, green: 0.97, blue: 0.99)
    public static let textSecondary = UIColor(red: 0.72, green: 0.76, blue: 0.84)
    public static let separator = UIColor(red: 0.29, green: 0.32, blue: 0.42)
    public static let success = UIColor(red: 0.33, green: 0.82, blue: 0.54)
    public static let warning = UIColor(red: 0.95, green: 0.72, blue: 0.25)
    public static let clear = UIColor(red: 0, green: 0, blue: 0, alpha: 0)
}

public struct FontSpec: Equatable, Sendable {
    public let family: String
    public let size: Double
    public let weight: FontWeight

    public init(family: String = "Segoe UI", size: Double, weight: FontWeight = .regular) {
        self.family = family
        self.size = size
        self.weight = weight
    }
}

public struct TextStyle: Equatable, Sendable {
    public let font: FontSpec
    public let color: UIColor
    public let alignment: HorizontalAlignment
    public let lineLimit: Int?

    public init(
        font: FontSpec,
        color: UIColor = .textPrimary,
        alignment: HorizontalAlignment = .leading,
        lineLimit: Int? = nil
    ) {
        self.font = font
        self.color = color
        self.alignment = alignment
        self.lineLimit = lineLimit
    }

    public static let title = TextStyle(font: FontSpec(size: 28, weight: .bold))
    public static let headline = TextStyle(font: FontSpec(size: 20, weight: .semibold))
    public static let body = TextStyle(font: FontSpec(size: 16))
    public static let caption = TextStyle(font: FontSpec(size: 13), color: .textSecondary)
}

public enum ButtonVisualStyle: Equatable, Sendable {
    case primary
    case secondary
    case plain
}

public struct ButtonState: Equatable, Sendable {
    public let isEnabled: Bool

    public init(isEnabled: Bool = true) {
        self.isEnabled = isEnabled
    }
}

public struct UITextFieldModel: Equatable, Sendable {
    public let id: UITextFieldID
    public let text: String
    public let placeholder: String
    public let caretIndex: Int
    public let submitAction: UIActionID?

    public init(
        id: UITextFieldID,
        text: String,
        placeholder: String = "",
        caretIndex: Int? = nil,
        submitAction: UIActionID? = nil
    ) {
        self.id = id
        self.text = text
        self.placeholder = placeholder
        self.caretIndex = min(max(0, caretIndex ?? text.count), text.count)
        self.submitAction = submitAction
    }
}

public struct GaugeModel: Equatable, Sendable {
    public let label: String
    public let value: Double
    public let range: ClosedRange<Double>
    public let unit: String
    public let accentColor: UIColor

    public init(
        label: String,
        value: Double,
        range: ClosedRange<Double>,
        unit: String,
        accentColor: UIColor = .accent
    ) {
        self.label = label
        self.value = value
        self.range = range
        self.unit = unit
        self.accentColor = accentColor
    }

    public var normalizedValue: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else {
            return 0
        }

        return min(1, max(0, (value - range.lowerBound) / span))
    }
}

public struct RasterImageAsset: Equatable, Sendable {
    public let name: String
    public let filePath: String

    public init(name: String, filePath: String) {
        self.name = name
        self.filePath = filePath
    }
}

public struct ImageNode: Equatable, Sendable {
    public let asset: RasterImageAsset
    public let accessibilityLabel: String?
    public let width: Double?
    public let height: Double?

    public init(
        asset: RasterImageAsset,
        accessibilityLabel: String? = nil,
        width: Double? = nil,
        height: Double? = nil
    ) {
        self.asset = asset
        self.accessibilityLabel = accessibilityLabel
        self.width = width
        self.height = height
    }
}

public struct ListItemModel: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let action: UIActionID?

    public init(id: String, title: String, subtitle: String? = nil, action: UIActionID? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.action = action
    }
}

public struct NavigationPathState<Route: Hashable & Sendable>: Equatable, Sendable {
    public let root: Route
    public private(set) var stack: [Route]

    public init(root: Route, stack: [Route] = []) {
        self.root = root
        self.stack = stack
    }

    public var current: Route {
        stack.last ?? root
    }

    public var canGoBack: Bool {
        !stack.isEmpty
    }

    public mutating func push(_ route: Route) {
        stack.append(route)
    }

    @discardableResult
    public mutating func pop() -> Route? {
        stack.popLast()
    }

    public mutating func popToRoot() {
        stack.removeAll()
    }
}

public struct ListSelectionState<ID: Hashable & Sendable>: Equatable, Sendable {
    public private(set) var selectedID: ID?

    public init(selectedID: ID? = nil) {
        self.selectedID = selectedID
    }

    public mutating func select(_ id: ID) {
        selectedID = id
    }

    public mutating func clear() {
        selectedID = nil
    }
}

public struct StackNode: Equatable, Sendable {
    public let children: [RenderNode]
    public let spacing: Double
    public let alignment: HorizontalAlignment

    public init(children: [RenderNode], spacing: Double, alignment: HorizontalAlignment = .leading) {
        self.children = children
        self.spacing = spacing
        self.alignment = alignment
    }
}

public struct TextNode: Equatable, Sendable {
    public let content: String
    public let style: TextStyle

    public init(content: String, style: TextStyle = .body) {
        self.content = content
        self.style = style
    }
}

public struct ButtonNode: Equatable, Sendable {
    public let title: String
    public let action: UIActionID
    public let style: ButtonVisualStyle
    public let state: ButtonState

    public init(
        title: String,
        action: UIActionID,
        style: ButtonVisualStyle = .primary,
        state: ButtonState = ButtonState()
    ) {
        self.title = title
        self.action = action
        self.style = style
        self.state = state
    }
}

public struct DividerNode: Equatable, Sendable {
    public let color: UIColor
    public let thickness: Double

    public init(color: UIColor = .separator, thickness: Double = 1) {
        self.color = color
        self.thickness = thickness
    }
}

public struct GestureSurfaceNode: Equatable, Sendable {
    public let id: UIGestureSurfaceID
    public let child: RenderNode

    public init(id: UIGestureSurfaceID, child: RenderNode) {
        self.id = id
        self.child = child
    }
}

public struct SpacerNode: Equatable, Sendable {
    public let minLength: Double

    public init(minLength: Double = 0) {
        self.minLength = minLength
    }
}

public struct ListNode: Equatable, Sendable {
    public let items: [ListItemModel]
    public let selectedID: String?

    public init(items: [ListItemModel], selectedID: String? = nil) {
        self.items = items
        self.selectedID = selectedID
    }
}

public struct NavigationNode: Equatable, Sendable {
    public let title: String
    public let canGoBack: Bool
    public let backAction: UIActionID?
    public let content: RenderNode

    public init(title: String, canGoBack: Bool = false, backAction: UIActionID? = nil, content: RenderNode) {
        self.title = title
        self.canGoBack = canGoBack
        self.backAction = backAction
        self.content = content
    }
}

public struct PaddingNode: Equatable, Sendable {
    public let insets: UIInsets
    public let child: RenderNode

    public init(insets: UIInsets, child: RenderNode) {
        self.insets = insets
        self.child = child
    }
}

public struct FrameConstraints: Equatable, Sendable {
    public let width: Double?
    public let height: Double?
    public let maxWidth: Double?
    public let maxHeight: Double?
    public let fillsWidth: Bool
    public let fillsHeight: Bool
    public let alignment: HorizontalAlignment

    public init(
        width: Double? = nil,
        height: Double? = nil,
        maxWidth: Double? = nil,
        maxHeight: Double? = nil,
        fillsWidth: Bool = false,
        fillsHeight: Bool = false,
        alignment: HorizontalAlignment = .leading
    ) {
        self.width = width
        self.height = height
        self.maxWidth = maxWidth
        self.maxHeight = maxHeight
        self.fillsWidth = fillsWidth
        self.fillsHeight = fillsHeight
        self.alignment = alignment
    }
}

public struct FrameNode: Equatable, Sendable {
    public let constraints: FrameConstraints
    public let child: RenderNode

    public init(constraints: FrameConstraints, child: RenderNode) {
        self.constraints = constraints
        self.child = child
    }
}

public indirect enum RenderNode: Equatable, Sendable {
    case vStack(StackNode)
    case hStack(StackNode)
    case text(TextNode)
    case image(ImageNode)
    case textField(UITextFieldModel)
    case gestureSurface(GestureSurfaceNode)
    case divider(DividerNode)
    case button(ButtonNode)
    case gauge(GaugeModel)
    case spacer(SpacerNode)
    case list(ListNode)
    case navigationStack(NavigationNode)
    case padding(PaddingNode)
    case frame(FrameNode)
}

public enum ScreenRootLayoutMode: String, Equatable, Sendable {
    case safeArea
    case fullBleed
}

public struct ScreenDocument: Equatable, Sendable {
    public let title: String
    public let backgroundColor: UIColor
    public let rootLayoutMode: ScreenRootLayoutMode
    public let safeAreaInsets: UIInsets
    public let root: RenderNode

    public init(
        title: String,
        backgroundColor: UIColor = .canvas,
        rootLayoutMode: ScreenRootLayoutMode = .safeArea,
        safeAreaInsets: UIInsets = .zero,
        root: RenderNode
    ) {
        self.title = title
        self.backgroundColor = backgroundColor
        self.rootLayoutMode = rootLayoutMode
        self.safeAreaInsets = safeAreaInsets
        self.root = root
    }
}

@resultBuilder
public enum RenderNodeBuilder {
    public static func buildBlock(_ components: [RenderNode]...) -> [RenderNode] {
        components.flatMap { $0 }
    }

    public static func buildExpression(_ expression: RenderNode) -> [RenderNode] {
        [expression]
    }

    public static func buildExpression(_ expression: [RenderNode]) -> [RenderNode] {
        expression
    }

    public static func buildOptional(_ component: [RenderNode]?) -> [RenderNode] {
        component ?? []
    }

    public static func buildEither(first component: [RenderNode]) -> [RenderNode] {
        component
    }

    public static func buildEither(second component: [RenderNode]) -> [RenderNode] {
        component
    }

    public static func buildArray(_ components: [[RenderNode]]) -> [RenderNode] {
        components.flatMap { $0 }
    }
}

public enum UI {
    public static func screen(
        title: String,
        backgroundColor: UIColor = .canvas,
        rootLayoutMode: ScreenRootLayoutMode = .safeArea,
        safeAreaInsets: UIInsets = .zero,
        @RenderNodeBuilder content: () -> [RenderNode]
    ) -> ScreenDocument {
        ScreenDocument(
            title: title,
            backgroundColor: backgroundColor,
            rootLayoutMode: rootLayoutMode,
            safeAreaInsets: safeAreaInsets,
            root: stackOrSingle(content(), spacing: 16)
        )
    }

    public static func vStack(
        spacing: Double = 0,
        alignment: HorizontalAlignment = .leading,
        @RenderNodeBuilder content: () -> [RenderNode]
    ) -> RenderNode {
        .vStack(StackNode(children: content(), spacing: spacing, alignment: alignment))
    }

    public static func hStack(
        spacing: Double = 0,
        alignment: HorizontalAlignment = .leading,
        @RenderNodeBuilder content: () -> [RenderNode]
    ) -> RenderNode {
        .hStack(StackNode(children: content(), spacing: spacing, alignment: alignment))
    }

    public static func text(_ content: String, style: TextStyle = .body) -> RenderNode {
        .text(TextNode(content: content, style: style))
    }

    public static func image(
        _ asset: RasterImageAsset,
        accessibilityLabel: String? = nil,
        width: Double? = nil,
        height: Double? = nil
    ) -> RenderNode {
        .image(ImageNode(asset: asset, accessibilityLabel: accessibilityLabel, width: width, height: height))
    }

    public static func textField(
        id: UITextFieldID,
        text: String,
        placeholder: String = "",
        caretIndex: Int? = nil,
        submitAction: UIActionID? = nil
    ) -> RenderNode {
        .textField(
            UITextFieldModel(
                id: id,
                text: text,
                placeholder: placeholder,
                caretIndex: caretIndex,
                submitAction: submitAction
            )
        )
    }

    public static func button(
        _ title: String,
        action: UIActionID,
        style: ButtonVisualStyle = .primary,
        state: ButtonState = ButtonState()
    ) -> RenderNode {
        .button(ButtonNode(title: title, action: action, style: style, state: state))
    }

    public static func divider(color: UIColor = .separator, thickness: Double = 1) -> RenderNode {
        .divider(DividerNode(color: color, thickness: thickness))
    }

    public static func spacer(minLength: Double = 0) -> RenderNode {
        .spacer(SpacerNode(minLength: minLength))
    }

    public static func gauge(
        label: String,
        value: Double,
        range: ClosedRange<Double>,
        unit: String,
        accentColor: UIColor = .accent
    ) -> RenderNode {
        .gauge(GaugeModel(label: label, value: value, range: range, unit: unit, accentColor: accentColor))
    }

    public static func list(items: [ListItemModel], selectedID: String? = nil) -> RenderNode {
        .list(ListNode(items: items, selectedID: selectedID))
    }

    public static func gestureSurface(
        id: UIGestureSurfaceID,
        _ child: RenderNode
    ) -> RenderNode {
        .gestureSurface(GestureSurfaceNode(id: id, child: child))
    }

    public static func navigationStack(
        title: String,
        canGoBack: Bool = false,
        backAction: UIActionID? = nil,
        @RenderNodeBuilder content: () -> [RenderNode]
    ) -> RenderNode {
        .navigationStack(
            NavigationNode(
                title: title,
                canGoBack: canGoBack,
                backAction: backAction,
                content: stackOrSingle(content(), spacing: 16)
            )
        )
    }

    public static func padding(_ insets: UIInsets = .uniform(16), _ child: RenderNode) -> RenderNode {
        .padding(PaddingNode(insets: insets, child: child))
    }

    public static func frame(
        width: Double? = nil,
        height: Double? = nil,
        maxWidth: Double? = nil,
        maxHeight: Double? = nil,
        fillsWidth: Bool = false,
        fillsHeight: Bool = false,
        alignment: HorizontalAlignment = .leading,
        _ child: RenderNode
    ) -> RenderNode {
        .frame(
            FrameNode(
                constraints: FrameConstraints(
                    width: width,
                    height: height,
                    maxWidth: maxWidth,
                    maxHeight: maxHeight,
                    fillsWidth: fillsWidth,
                    fillsHeight: fillsHeight,
                    alignment: alignment
                ),
                child: child
            )
        )
    }

    private static func stackOrSingle(_ nodes: [RenderNode], spacing: Double) -> RenderNode {
        if let node = nodes.only {
            return node
        }

        return .vStack(StackNode(children: nodes, spacing: spacing))
    }
}

public protocol ScreenRenderer {
    func render(_ document: ScreenDocument, in viewport: DeviceViewport) -> String
}

private extension Array {
    var only: Element? {
        count == 1 ? first : nil
    }
}
