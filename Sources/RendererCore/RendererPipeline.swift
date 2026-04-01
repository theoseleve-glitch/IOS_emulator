import Foundation

public struct UIPoint: Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct UISize: Equatable, Sendable {
    public let width: Double
    public let height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public struct UIRect: Equatable, Sendable {
    public let origin: UIPoint
    public let size: UISize

    public init(origin: UIPoint, size: UISize) {
        self.origin = origin
        self.size = size
    }

    public var minX: Double { origin.x }
    public var minY: Double { origin.y }
    public var maxX: Double { origin.x + size.width }
    public var maxY: Double { origin.y + size.height }
    public var width: Double { size.width }
    public var height: Double { size.height }

    public func contains(_ point: UIPoint) -> Bool {
        point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
    }
}

public struct ProposedSize: Equatable, Sendable {
    public let width: Double?
    public let height: Double?

    public init(width: Double?, height: Double?) {
        self.width = width
        self.height = height
    }
}

public enum LayoutElement: Equatable, Sendable {
    case screen(title: String, backgroundColor: UIColor)
    case vStack(StackNode)
    case hStack(StackNode)
    case text(TextNode)
    case image(ImageNode)
    case textField(UITextFieldModel)
    case gestureSurface(id: UIGestureSurfaceID)
    case divider(DividerNode)
    case button(ButtonNode)
    case gauge(GaugeModel)
    case spacer(SpacerNode)
    case list(ListNode)
    case listRow(item: ListItemModel, selected: Bool)
    case navigationStack(NavigationNode)
    case navigationBar(title: String)
    case padding
    case frame
}

public struct LayoutNode: Equatable, Sendable {
    public let element: LayoutElement
    public let frame: UIRect
    public let children: [LayoutNode]
    public let action: UIActionID?
    public let focusTarget: FocusableTarget?

    public init(
        element: LayoutElement,
        frame: UIRect,
        children: [LayoutNode] = [],
        action: UIActionID? = nil,
        focusTarget: FocusableTarget? = nil
    ) {
        self.element = element
        self.frame = frame
        self.children = children
        self.action = action
        self.focusTarget = focusTarget
    }
}

public enum DrawCommand: Equatable, Sendable {
    case fill(rect: UIRect, color: UIColor, cornerRadius: Double)
    case stroke(rect: UIRect, color: UIColor, lineWidth: Double, cornerRadius: Double)
    case line(from: UIPoint, to: UIPoint, color: UIColor, lineWidth: Double)
    case text(value: String, rect: UIRect, style: TextStyle)
    case image(assetName: String, assetPath: String, rect: UIRect)
}

public enum FocusableTarget: Hashable, Equatable, Sendable {
    case action(UIActionID)
    case textField(UITextFieldID)
    case gestureSurface(UIGestureSurfaceID)
}

public struct InteractionRegion: Equatable, Sendable {
    public let rect: UIRect
    public let action: UIActionID

    public init(rect: UIRect, action: UIActionID) {
        self.rect = rect
        self.action = action
    }
}

public struct FocusableRegion: Equatable, Sendable {
    public let rect: UIRect
    public let target: FocusableTarget

    public init(rect: UIRect, target: FocusableTarget) {
        self.rect = rect
        self.target = target
    }
}

public struct RenderPipelineOutput: Equatable, Sendable {
    public let viewport: DeviceViewport
    public let layoutTree: LayoutNode
    public let commands: [DrawCommand]
    public let interactions: [InteractionRegion]
    public let focusRegions: [FocusableRegion]
    public let focusedTarget: FocusableTarget?
    public let defaultBackAction: UIActionID?

    public init(
        viewport: DeviceViewport,
        layoutTree: LayoutNode,
        commands: [DrawCommand],
        interactions: [InteractionRegion],
        focusRegions: [FocusableRegion],
        focusedTarget: FocusableTarget? = nil,
        defaultBackAction: UIActionID? = nil
    ) {
        self.viewport = viewport
        self.layoutTree = layoutTree
        self.commands = commands
        self.interactions = interactions
        self.focusRegions = focusRegions
        self.focusedTarget = focusedTarget
        self.defaultBackAction = defaultBackAction
    }
}

public enum InteractionRouter {
    public static func action(at point: UIPoint, in output: RenderPipelineOutput) -> UIActionID? {
        output.interactions.reversed().first(where: { $0.rect.contains(point) })?.action
    }
}

public enum RenderPipeline {
    public static func makeDisplayList(
        for document: ScreenDocument,
        in viewport: DeviceViewport,
        focusedTarget: FocusableTarget? = nil,
        focusedAction: UIActionID? = nil
    ) -> RenderPipelineOutput {
        let resolvedFocusedTarget = focusedTarget ?? focusedAction.map(FocusableTarget.action)
        let rootFrame = UIRect(
            origin: UIPoint(x: 0, y: 0),
            size: UISize(width: Double(viewport.width), height: Double(viewport.height))
        )
        let contentFrame = rootContentFrame(for: document, in: rootFrame)
        let rootProposal = ProposedSize(width: contentFrame.width, height: contentFrame.height)
        let contentLayout = layout(node: document.root, origin: contentFrame.origin, proposal: rootProposal)
        let rootNode = LayoutNode(
            element: .screen(title: document.title, backgroundColor: document.backgroundColor),
            frame: rootFrame,
            children: [contentLayout]
        )

        var commands: [DrawCommand] = [
            .fill(rect: rootFrame, color: document.backgroundColor, cornerRadius: 0)
        ]
        var interactions: [InteractionRegion] = []
        var focusRegions: [FocusableRegion] = []
        appendDrawing(
            from: contentLayout,
            focusedTarget: resolvedFocusedTarget,
            commands: &commands,
            interactions: &interactions,
            focusRegions: &focusRegions
        )

        return RenderPipelineOutput(
            viewport: viewport,
            layoutTree: rootNode,
            commands: commands,
            interactions: interactions,
            focusRegions: focusRegions,
            focusedTarget: resolvedFocusedTarget,
            defaultBackAction: defaultBackAction(from: document.root)
        )
    }

    private static func rootContentFrame(for document: ScreenDocument, in rootFrame: UIRect) -> UIRect {
        guard document.rootLayoutMode == .safeArea else {
            return rootFrame
        }

        return inset(rootFrame, by: document.safeAreaInsets)
    }

    private static func layout(node: RenderNode, origin: UIPoint, proposal: ProposedSize) -> LayoutNode {
        switch node {
        case .text(let text):
            let size = measureText(text, constrainedTo: proposal.width)
            return LayoutNode(
                element: .text(text),
                frame: UIRect(origin: origin, size: size)
            )
        case .image(let image):
            let size = measureImage(image, proposal: proposal)
            return LayoutNode(
                element: .image(image),
                frame: UIRect(origin: origin, size: size)
            )
        case .textField(let textField):
            let size = measureTextField(textField, constrainedTo: proposal.width)
            return LayoutNode(
                element: .textField(textField),
                frame: UIRect(origin: origin, size: size),
                focusTarget: .textField(textField.id)
            )
        case .gestureSurface(let surface):
            let child = layout(node: surface.child, origin: origin, proposal: proposal)
            return LayoutNode(
                element: .gestureSurface(id: surface.id),
                frame: child.frame,
                children: [child],
                focusTarget: .gestureSurface(surface.id)
            )
        case .button(let button):
            let size = measureButton(button, constrainedTo: proposal.width)
            return LayoutNode(
                element: .button(button),
                frame: UIRect(origin: origin, size: size),
                action: button.action,
                focusTarget: .action(button.action)
            )
        case .divider(let divider):
            let width = proposal.width ?? 120
            return LayoutNode(
                element: .divider(divider),
                frame: UIRect(origin: origin, size: UISize(width: width, height: divider.thickness))
            )
        case .gauge(let gauge):
            let width = proposal.width ?? 280
            return LayoutNode(
                element: .gauge(gauge),
                frame: UIRect(origin: origin, size: UISize(width: width, height: 54))
            )
        case .spacer(let spacer):
            return LayoutNode(
                element: .spacer(spacer),
                frame: UIRect(
                    origin: origin,
                    size: UISize(width: proposal.width ?? 0, height: proposal.height ?? spacer.minLength)
                )
            )
        case .padding(let padding):
            let innerProposal = ProposedSize(
                width: proposal.width.map { max(0, $0 - padding.insets.leading - padding.insets.trailing) },
                height: proposal.height.map { max(0, $0 - padding.insets.top - padding.insets.bottom) }
            )
            let childOrigin = UIPoint(
                x: origin.x + padding.insets.leading,
                y: origin.y + padding.insets.top
            )
            let child = layout(node: padding.child, origin: childOrigin, proposal: innerProposal)
            let size = UISize(
                width: proposal.width ?? (child.frame.width + padding.insets.leading + padding.insets.trailing),
                height: proposal.height ?? (child.frame.height + padding.insets.top + padding.insets.bottom)
            )
            return LayoutNode(
                element: .padding,
                frame: UIRect(origin: origin, size: size),
                children: [child]
            )
        case .frame(let frame):
            let childProposal = ProposedSize(
                width: frame.constraints.fillsWidth
                    ? proposal.width
                    : (frame.constraints.width ?? frame.constraints.maxWidth ?? proposal.width),
                height: frame.constraints.fillsHeight
                    ? proposal.height
                    : (frame.constraints.height ?? frame.constraints.maxHeight ?? proposal.height)
            )
            let provisionalChild = layout(node: frame.child, origin: origin, proposal: childProposal)
            let width = resolvedDimension(
                explicit: frame.constraints.width,
                maximum: frame.constraints.maxWidth,
                fills: frame.constraints.fillsWidth,
                proposal: proposal.width,
                measured: provisionalChild.frame.width
            )
            let height = resolvedDimension(
                explicit: frame.constraints.height,
                maximum: frame.constraints.maxHeight,
                fills: frame.constraints.fillsHeight,
                proposal: proposal.height,
                measured: provisionalChild.frame.height
            )
            let childOrigin = UIPoint(
                x: origin.x + alignmentOffset(
                    available: width,
                    measured: provisionalChild.frame.width,
                    alignment: frame.constraints.alignment
                ),
                y: origin.y + max(0, (height - provisionalChild.frame.height) / 2)
            )
            let child = layout(
                node: frame.child,
                origin: childOrigin,
                proposal: ProposedSize(width: min(width, provisionalChild.frame.width), height: min(height, provisionalChild.frame.height))
            )
            return LayoutNode(
                element: .frame,
                frame: UIRect(origin: origin, size: UISize(width: width, height: height)),
                children: [child]
            )
        case .vStack(let stack):
            return layoutStack(element: .vStack(stack), stack: stack, origin: origin, proposal: proposal, axis: .vertical)
        case .hStack(let stack):
            return layoutStack(element: .hStack(stack), stack: stack, origin: origin, proposal: proposal, axis: .horizontal)
        case .list(let list):
            return layoutList(list, origin: origin, proposal: proposal)
        case .navigationStack(let navigation):
            return layoutNavigation(navigation, origin: origin, proposal: proposal)
        }
    }

    private static func layoutStack(
        element: LayoutElement,
        stack: StackNode,
        origin: UIPoint,
        proposal: ProposedSize,
        axis: StackAxis
    ) -> LayoutNode {
        let availableWidth = proposal.width ?? naturalCrossSize(for: stack.children, axis: axis)
        let availableHeight = proposal.height ?? naturalMainSize(for: stack.children, axis: axis, constrainedWidth: availableWidth, spacing: stack.spacing)

        let measurements = stack.children.map { child in
            ChildMeasurement(
                node: child,
                size: measure(
                    node: child,
                    proposal: ProposedSize(
                        width: axis == .vertical ? availableWidth : nil,
                        height: axis == .horizontal ? availableHeight : nil
                    )
                ),
                isFlexibleSpacer: isFlexibleSpacer(child)
            )
        }

        let spacingTotal = Double(max(0, measurements.count - 1)) * stack.spacing
        let fixedMain = measurements.reduce(0) { partial, measurement in
            partial + mainValue(of: measurement.size, axis: axis)
        } + spacingTotal
        let availableMain = axis == .vertical ? availableHeight : availableWidth
        let flexibleCount = measurements.filter(\.isFlexibleSpacer).count
        let remaining = max(0, availableMain - fixedMain)
        let extraForSpacer = flexibleCount > 0 ? remaining / Double(flexibleCount) : 0

        var children: [LayoutNode] = []
        var cursorX = origin.x
        var cursorY = origin.y

        for (index, measurement) in measurements.enumerated() {
            let childMain = mainValue(of: measurement.size, axis: axis) + (measurement.isFlexibleSpacer ? extraForSpacer : 0)
            let childProposal = ProposedSize(
                width: axis == .vertical ? availableWidth : childMain,
                height: axis == .vertical ? childMain : availableHeight
            )
            let childCross = crossValue(of: measurement.size, axis: axis)
            let childOrigin = axis == .vertical
                ? UIPoint(
                    x: origin.x + alignmentOffset(available: availableWidth, measured: childCross, alignment: stack.alignment),
                    y: cursorY
                )
                : UIPoint(
                    x: cursorX,
                    y: origin.y + max(0, (availableHeight - childCross) / 2)
                )
            let child = layout(node: measurement.node, origin: childOrigin, proposal: childProposal)
            children.append(child)

            if axis == .vertical {
                cursorY += childMain
            } else {
                cursorX += childMain
            }

            if index < measurements.count - 1 {
                if axis == .vertical {
                    cursorY += stack.spacing
                } else {
                    cursorX += stack.spacing
                }
            }
        }

        let frame = UIRect(
            origin: origin,
            size: UISize(width: availableWidth, height: availableHeight)
        )
        return LayoutNode(element: element, frame: frame, children: children)
    }

    private static func layoutList(_ list: ListNode, origin: UIPoint, proposal: ProposedSize) -> LayoutNode {
        let width = proposal.width ?? 320
        let rowSpacing = 8.0
        var cursorY = origin.y
        var rows: [LayoutNode] = []

        for (index, item) in list.items.enumerated() {
            let rowHeight = item.subtitle == nil ? 58.0 : 72.0
            let rowFrame = UIRect(origin: UIPoint(x: origin.x, y: cursorY), size: UISize(width: width, height: rowHeight))
            let title = layout(
                node: .text(TextNode(content: item.title, style: .headline)),
                origin: UIPoint(x: rowFrame.minX + 18, y: rowFrame.minY + 14),
                proposal: ProposedSize(width: rowFrame.width - 36, height: nil)
            )

            var children = [title]
            if let subtitle = item.subtitle {
                let subtitleNode = layout(
                    node: .text(TextNode(content: subtitle, style: .caption)),
                    origin: UIPoint(x: rowFrame.minX + 18, y: rowFrame.minY + 42),
                    proposal: ProposedSize(width: rowFrame.width - 36, height: nil)
                )
                children.append(subtitleNode)
            }

            rows.append(
                LayoutNode(
                    element: .listRow(item: item, selected: list.selectedID == item.id),
                    frame: rowFrame,
                    children: children,
                    action: item.action,
                    focusTarget: item.action.map(FocusableTarget.action)
                )
            )

            cursorY += rowHeight
            if index < list.items.count - 1 {
                cursorY += rowSpacing
            }
        }

        let totalHeight = rows.last.map { $0.frame.maxY - origin.y } ?? 0
        return LayoutNode(
            element: .list(list),
            frame: UIRect(origin: origin, size: UISize(width: width, height: totalHeight)),
            children: rows
        )
    }

    private static func layoutNavigation(_ navigation: NavigationNode, origin: UIPoint, proposal: ProposedSize) -> LayoutNode {
        let width = proposal.width ?? 360
        let height = proposal.height ?? 640
        let barHeight = 66.0
        let barFrame = UIRect(origin: origin, size: UISize(width: width, height: barHeight))

        var barChildren: [LayoutNode] = []
        if navigation.canGoBack, let backAction = navigation.backAction {
            let backButton = layout(
                node: .button(ButtonNode(title: "Back", action: backAction, style: .plain)),
                origin: UIPoint(x: origin.x + 12, y: origin.y + 14),
                proposal: ProposedSize(width: 92, height: 36)
            )
            barChildren.append(backButton)
        }

        let titleNode = layout(
            node: .text(
                TextNode(
                    content: navigation.title,
                    style: TextStyle(font: FontSpec(size: 18, weight: .semibold), alignment: .center)
                )
            ),
            origin: UIPoint(x: origin.x + 90, y: origin.y + 18),
            proposal: ProposedSize(width: max(80, width - 180), height: nil)
        )
        barChildren.append(titleNode)

        let contentOrigin = UIPoint(x: origin.x, y: origin.y + barHeight)
        let content = layout(
            node: navigation.content,
            origin: contentOrigin,
            proposal: ProposedSize(width: width, height: max(0, height - barHeight))
        )

        return LayoutNode(
            element: .navigationStack(navigation),
            frame: UIRect(origin: origin, size: UISize(width: width, height: height)),
            children: [
                LayoutNode(element: .navigationBar(title: navigation.title), frame: barFrame, children: barChildren),
                content,
            ]
        )
    }

    private static func appendDrawing(
        from node: LayoutNode,
        focusedTarget: FocusableTarget?,
        commands: inout [DrawCommand],
        interactions: inout [InteractionRegion],
        focusRegions: inout [FocusableRegion]
    ) {
        switch node.element {
        case .screen:
            break
        case .navigationBar:
            commands.append(.fill(rect: node.frame, color: .surface, cornerRadius: 0))
            commands.append(
                .line(
                    from: UIPoint(x: node.frame.minX, y: node.frame.maxY - 1),
                    to: UIPoint(x: node.frame.maxX, y: node.frame.maxY - 1),
                    color: .separator,
                    lineWidth: 1
                )
            )
        case .button(let button):
            let palette = buttonPalette(for: button)
            commands.append(.fill(rect: node.frame, color: palette.fill, cornerRadius: palette.cornerRadius))
            if palette.stroke.alpha > 0 {
                commands.append(.stroke(rect: node.frame, color: palette.stroke, lineWidth: 1, cornerRadius: palette.cornerRadius))
            }
            commands.append(
                .text(
                    value: button.title,
                    rect: inset(node.frame, by: UIInsets(top: 8, leading: 12, bottom: 8, trailing: 12)),
                    style: TextStyle(
                        font: FontSpec(size: 15, weight: .semibold),
                        color: palette.text,
                        alignment: .center
                    )
                )
            )
        case .text(let text):
            commands.append(.text(value: text.content, rect: node.frame, style: text.style))
        case .image(let image):
            commands.append(.image(assetName: image.asset.name, assetPath: image.asset.filePath, rect: node.frame))
        case .textField(let textField):
            let fillColor = UIColor.surface
            let strokeColor = focusedTarget == node.focusTarget ? UIColor.accentStrong : UIColor.separator
            let displayValue = textField.text.isEmpty ? textField.placeholder : textField.text
            let textStyle: TextStyle = textField.text.isEmpty
                ? TextStyle(font: FontSpec(size: 15), color: .textSecondary, lineLimit: 1)
                : TextStyle(font: FontSpec(size: 15), color: .textPrimary, lineLimit: 1)
            let contentRect = inset(node.frame, by: UIInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
            commands.append(.fill(rect: node.frame, color: fillColor, cornerRadius: 12))
            commands.append(.stroke(rect: node.frame, color: strokeColor, lineWidth: 1, cornerRadius: 12))
            commands.append(.text(value: displayValue, rect: contentRect, style: textStyle))
            if focusedTarget == node.focusTarget {
                let caretOffset = estimatedTextWidth(
                    String(textField.text.prefix(textField.caretIndex)),
                    fontSize: 15
                )
                let caretX = min(contentRect.maxX - 2, contentRect.minX + caretOffset)
                commands.append(
                    .line(
                        from: UIPoint(x: caretX, y: contentRect.minY + 2),
                        to: UIPoint(x: caretX, y: contentRect.maxY - 2),
                        color: .accentStrong,
                        lineWidth: 1.5
                    )
                )
            }
        case .gestureSurface:
            break
        case .divider(let divider):
            commands.append(
                .line(
                    from: UIPoint(x: node.frame.minX, y: node.frame.minY),
                    to: UIPoint(x: node.frame.maxX, y: node.frame.minY),
                    color: divider.color,
                    lineWidth: divider.thickness
                )
            )
        case .gauge(let gauge):
            let barHeight = 14.0
            let labelRect = UIRect(
                origin: node.frame.origin,
                size: UISize(width: node.frame.width, height: 18)
            )
            let barRect = UIRect(
                origin: UIPoint(x: node.frame.minX, y: node.frame.minY + 24),
                size: UISize(width: node.frame.width, height: barHeight)
            )
            let normalized = normalizedGaugeValue(gauge)
            let fillWidth = max(0, barRect.width * normalized)
            let fillRect = UIRect(origin: barRect.origin, size: UISize(width: fillWidth, height: barRect.height))
            let valueRect = UIRect(
                origin: UIPoint(x: node.frame.minX, y: node.frame.minY + 40),
                size: UISize(width: node.frame.width, height: 14)
            )
            commands.append(
                .text(
                    value: gauge.label,
                    rect: labelRect,
                    style: TextStyle(font: FontSpec(size: 15, weight: .semibold))
                )
            )
            commands.append(.fill(rect: barRect, color: .surfaceMuted, cornerRadius: 6))
            commands.append(.fill(rect: fillRect, color: gauge.accentColor, cornerRadius: 6))
            commands.append(.stroke(rect: barRect, color: .separator, lineWidth: 1, cornerRadius: 6))
            commands.append(
                .text(
                    value: "\(Int(gauge.value.rounded())) \(gauge.unit)",
                    rect: valueRect,
                    style: .caption
                )
            )
        case .listRow(let item, let selected):
            commands.append(
                .fill(
                    rect: node.frame,
                    color: selected ? .surfaceMuted : .surface,
                    cornerRadius: 14
                )
            )
            commands.append(
                .stroke(
                    rect: node.frame,
                    color: selected ? .accent : .separator,
                    lineWidth: 1,
                    cornerRadius: 14
                )
            )
            if let action = item.action {
                interactions.append(InteractionRegion(rect: node.frame, action: action))
            }
        case .spacer, .padding, .frame, .list, .navigationStack, .vStack, .hStack:
            break
        }

        if let action = node.action, !interactions.contains(where: { $0.action == action && $0.rect == node.frame }) {
            interactions.append(InteractionRegion(rect: node.frame, action: action))
        }

        if let focusTarget = node.focusTarget, !focusRegions.contains(where: { $0.target == focusTarget && $0.rect == node.frame }) {
            focusRegions.append(FocusableRegion(rect: node.frame, target: focusTarget))
        }

        if let nodeFocusTarget = node.focusTarget, nodeFocusTarget == focusedTarget, shouldDrawFocusRing(for: node.element) {
            commands.append(
                .stroke(
                    rect: node.frame,
                    color: .accentStrong,
                    lineWidth: 2,
                    cornerRadius: focusCornerRadius(for: node.element)
                )
            )
        }

        for child in node.children {
            appendDrawing(
                from: child,
                focusedTarget: focusedTarget,
                commands: &commands,
                interactions: &interactions,
                focusRegions: &focusRegions
            )
        }
    }

    private static func measure(node: RenderNode, proposal: ProposedSize) -> UISize {
        switch node {
        case .text(let text):
            return measureText(text, constrainedTo: proposal.width)
        case .image(let image):
            return measureImage(image, proposal: proposal)
        case .textField(let textField):
            return measureTextField(textField, constrainedTo: proposal.width)
        case .gestureSurface(let surface):
            return measure(node: surface.child, proposal: proposal)
        case .button(let button):
            return measureButton(button, constrainedTo: proposal.width)
        case .divider(let divider):
            return UISize(width: proposal.width ?? 120, height: divider.thickness)
        case .gauge:
            return UISize(width: proposal.width ?? 280, height: 54)
        case .spacer(let spacer):
            return UISize(width: proposal.width ?? 0, height: spacer.minLength)
        case .padding(let padding):
            let child = measure(
                node: padding.child,
                proposal: ProposedSize(
                    width: proposal.width.map { max(0, $0 - padding.insets.leading - padding.insets.trailing) },
                    height: proposal.height.map { max(0, $0 - padding.insets.top - padding.insets.bottom) }
                )
            )
            return UISize(
                width: child.width + padding.insets.leading + padding.insets.trailing,
                height: child.height + padding.insets.top + padding.insets.bottom
            )
        case .frame(let frame):
            let child = measure(
                node: frame.child,
                proposal: ProposedSize(
                    width: frame.constraints.fillsWidth ? proposal.width : frame.constraints.width ?? frame.constraints.maxWidth ?? proposal.width,
                    height: frame.constraints.fillsHeight ? proposal.height : frame.constraints.height ?? frame.constraints.maxHeight ?? proposal.height
                )
            )
            return UISize(
                width: resolvedDimension(
                    explicit: frame.constraints.width,
                    maximum: frame.constraints.maxWidth,
                    fills: frame.constraints.fillsWidth,
                    proposal: proposal.width,
                    measured: child.width
                ),
                height: resolvedDimension(
                    explicit: frame.constraints.height,
                    maximum: frame.constraints.maxHeight,
                    fills: frame.constraints.fillsHeight,
                    proposal: proposal.height,
                    measured: child.height
                )
            )
        case .vStack(let stack):
            let width = proposal.width ?? naturalCrossSize(for: stack.children, axis: .vertical)
            let height = proposal.height ?? naturalMainSize(for: stack.children, axis: .vertical, constrainedWidth: width, spacing: stack.spacing)
            return UISize(width: width, height: height)
        case .hStack(let stack):
            let width = proposal.width ?? naturalMainSize(for: stack.children, axis: .horizontal, constrainedWidth: proposal.height, spacing: stack.spacing)
            let height = proposal.height ?? naturalCrossSize(for: stack.children, axis: .horizontal)
            return UISize(width: width, height: height)
        case .list(let list):
            let width = proposal.width ?? 320
            let rowsHeight = list.items.enumerated().reduce(0.0) { partial, entry in
                let (index, item) = entry
                let rowHeight = item.subtitle == nil ? 58.0 : 72.0
                return partial + rowHeight + (index < list.items.count - 1 ? 8.0 : 0)
            }
            return UISize(width: width, height: rowsHeight)
        case .navigationStack:
            return UISize(width: proposal.width ?? 360, height: proposal.height ?? 640)
        }
    }

    private static func measureText(_ node: TextNode, constrainedTo width: Double?) -> UISize {
        let averageCharacterWidth = node.style.font.size * 0.56
        let maxWidth = width ?? max(averageCharacterWidth, Double(node.content.count) * averageCharacterWidth)
        let maxCharacters = max(1, Int(floor(maxWidth / averageCharacterWidth)))
        let wrapped = wrappedLines(for: node.content, maxCharactersPerLine: maxCharacters)
        let visibleLines = node.style.lineLimit.map { Array(wrapped.prefix($0)) } ?? wrapped
        let measuredWidth = min(maxWidth, Double(visibleLines.map(\.count).max() ?? 0) * averageCharacterWidth)
        let lineHeight = node.style.font.size * 1.28
        return UISize(width: max(1, measuredWidth), height: max(lineHeight, lineHeight * Double(max(1, visibleLines.count))))
    }

    private static func measureButton(_ node: ButtonNode, constrainedTo width: Double?) -> UISize {
        let label = measureText(
            TextNode(
                content: node.title,
                style: TextStyle(font: FontSpec(size: 15, weight: .semibold), alignment: .center, lineLimit: 1)
            ),
            constrainedTo: width.map { max(1, $0 - 24) }
        )
        let naturalWidth = max(96, label.width + 24)
        let height = max(40, label.height + 14)
        return UISize(width: min(width ?? naturalWidth, naturalWidth), height: height)
    }

    private static func measureTextField(_ node: UITextFieldModel, constrainedTo width: Double?) -> UISize {
        let content = node.text.isEmpty ? node.placeholder : node.text
        let textWidth = max(96, estimatedTextWidth(content.isEmpty ? " " : content, fontSize: 15) + 28)
        let resolvedWidth = min(width ?? textWidth, max(160, textWidth))
        return UISize(width: resolvedWidth, height: 44)
    }

    private static func measureImage(_ node: ImageNode, proposal: ProposedSize) -> UISize {
        let width = node.width ?? proposal.width ?? 180
        let height = node.height ?? proposal.height ?? 96
        return UISize(width: max(1, width), height: max(1, height))
    }

    private static func naturalMainSize(
        for children: [RenderNode],
        axis: StackAxis,
        constrainedWidth: Double?,
        spacing: Double
    ) -> Double {
        let proposed = ProposedSize(
            width: axis == .vertical ? constrainedWidth : nil,
            height: axis == .horizontal ? constrainedWidth : nil
        )
        let total = children.reduce(0.0) { partial, child in
            partial + mainValue(of: measure(node: child, proposal: proposed), axis: axis)
        }
        return total + Double(max(0, children.count - 1)) * spacing
    }

    private static func naturalCrossSize(for children: [RenderNode], axis: StackAxis) -> Double {
        children.map {
            crossValue(
                of: measure(node: $0, proposal: ProposedSize(width: nil, height: nil)),
                axis: axis
            )
        }.max() ?? 0
    }

    private static func resolvedDimension(
        explicit: Double?,
        maximum: Double?,
        fills: Bool,
        proposal: Double?,
        measured: Double
    ) -> Double {
        var resolved = explicit ?? (fills ? (proposal ?? measured) : measured)
        if let maximum {
            resolved = min(resolved, maximum)
        }
        return max(0, resolved)
    }

    private static func mainValue(of size: UISize, axis: StackAxis) -> Double {
        axis == .vertical ? size.height : size.width
    }

    private static func crossValue(of size: UISize, axis: StackAxis) -> Double {
        axis == .vertical ? size.width : size.height
    }

    private static func alignmentOffset(available: Double, measured: Double, alignment: HorizontalAlignment) -> Double {
        switch alignment {
        case .leading:
            return 0
        case .center:
            return max(0, (available - measured) / 2)
        case .trailing:
            return max(0, available - measured)
        }
    }

    private static func inset(_ rect: UIRect, by insets: UIInsets) -> UIRect {
        UIRect(
            origin: UIPoint(x: rect.minX + insets.leading, y: rect.minY + insets.top),
            size: UISize(
                width: max(0, rect.width - insets.leading - insets.trailing),
                height: max(0, rect.height - insets.top - insets.bottom)
            )
        )
    }

    private static func focusCornerRadius(for element: LayoutElement) -> Double {
        switch element {
        case .button:
            return 12
        case .textField:
            return 12
        case .listRow:
            return 14
        case .gestureSurface:
            return 10
        default:
            return 6
        }
    }

    private static func shouldDrawFocusRing(for element: LayoutElement) -> Bool {
        switch element {
        case .textField, .gestureSurface, .button, .listRow:
            return true
        default:
            return false
        }
    }

    private static func defaultBackAction(from node: RenderNode) -> UIActionID? {
        switch node {
        case .navigationStack(let navigation):
            return navigation.backAction ?? defaultBackAction(from: navigation.content)
        case .padding(let padding):
            return defaultBackAction(from: padding.child)
        case .frame(let frame):
            return defaultBackAction(from: frame.child)
        case .vStack(let stack), .hStack(let stack):
            for child in stack.children {
                if let action = defaultBackAction(from: child) {
                    return action
                }
            }
            return nil
        default:
            return nil
        }
    }

    private static func isFlexibleSpacer(_ node: RenderNode) -> Bool {
        if case .spacer = node {
            return true
        }
        return false
    }

    private static func wrappedLines(for text: String, maxCharactersPerLine: Int) -> [String] {
        var lines: [String] = []
        var current = ""

        for word in text.split(separator: " ").map(String.init) {
            let candidate = current.isEmpty ? word : current + " " + word
            if candidate.count <= maxCharactersPerLine {
                current = candidate
            } else {
                if !current.isEmpty {
                    lines.append(current)
                }
                if word.count <= maxCharactersPerLine {
                    current = word
                } else {
                    var remainder = word[...]
                    while remainder.count > maxCharactersPerLine {
                        lines.append(String(remainder.prefix(maxCharactersPerLine)))
                        remainder = remainder.dropFirst(maxCharactersPerLine)
                    }
                    current = String(remainder)
                }
            }
        }

        if !current.isEmpty {
            lines.append(current)
        }

        return lines.isEmpty ? [""] : lines
    }

    private static func estimatedTextWidth(_ text: String, fontSize: Double) -> Double {
        let characterScale = fontSize * 0.56
        return Double(max(1, text.count)) * characterScale
    }

    private static func buttonPalette(for button: ButtonNode) -> (fill: UIColor, stroke: UIColor, text: UIColor, cornerRadius: Double) {
        guard button.state.isEnabled else {
            return (.surfaceMuted, .separator, .textSecondary, 12)
        }

        switch button.style {
        case .primary:
            return (.accent, .clear, .textPrimary, 12)
        case .secondary:
            return (.surfaceMuted, .separator, .textPrimary, 12)
        case .plain:
            return (.clear, .clear, .accent, 8)
        }
    }

    private static func normalizedGaugeValue(_ gauge: GaugeModel) -> Double {
        let span = gauge.range.upperBound - gauge.range.lowerBound
        guard span > 0 else {
            return 0
        }
        return min(1, max(0, (gauge.value - gauge.range.lowerBound) / span))
    }
}

private struct ChildMeasurement {
    let node: RenderNode
    let size: UISize
    let isFlexibleSpacer: Bool
}

private enum StackAxis {
    case vertical
    case horizontal
}

public enum FocusNavigationDirection: Equatable, Sendable {
    case next
    case previous
    case up
    case down
    case left
    case right
}

public enum FocusNavigator {
    public static func firstTarget(in output: RenderPipelineOutput) -> FocusableTarget? {
        uniqueFocusRegions(from: output).first?.target
    }

    public static func target(
        for direction: FocusNavigationDirection,
        from currentTarget: FocusableTarget?,
        in output: RenderPipelineOutput
    ) -> FocusableTarget? {
        let regions = uniqueFocusRegions(from: output)
        guard !regions.isEmpty else {
            return nil
        }

        guard let currentTarget, let currentIndex = regions.firstIndex(where: { $0.target == currentTarget }) else {
            return regions.first?.target
        }

        switch direction {
        case .next:
            return regions[(currentIndex + 1) % regions.count].target
        case .previous:
            return regions[(currentIndex - 1 + regions.count) % regions.count].target
        case .up, .down, .left, .right:
            return directionalTarget(
                for: direction,
                currentRegion: regions[currentIndex],
                candidates: regions
            ) ?? currentTarget
        }
    }

    public static func region(for target: FocusableTarget, in output: RenderPipelineOutput) -> FocusableRegion? {
        uniqueFocusRegions(from: output).first(where: { $0.target == target })
    }

    public static func firstAction(in output: RenderPipelineOutput) -> UIActionID? {
        uniqueInteractions(from: output).first?.action
    }

    public static func action(
        for direction: FocusNavigationDirection,
        from currentAction: UIActionID?,
        in output: RenderPipelineOutput
    ) -> UIActionID? {
        let interactions = uniqueInteractions(from: output)
        guard !interactions.isEmpty else {
            return nil
        }

        guard let currentAction, let currentIndex = interactions.firstIndex(where: { $0.action == currentAction }) else {
            return interactions.first?.action
        }

        switch direction {
        case .next:
            return interactions[(currentIndex + 1) % interactions.count].action
        case .previous:
            return interactions[(currentIndex - 1 + interactions.count) % interactions.count].action
        case .up, .down, .left, .right:
            return directionalAction(
                for: direction,
                currentRegion: interactions[currentIndex],
                candidates: interactions
            ) ?? currentAction
        }
    }

    private static func directionalTarget(
        for direction: FocusNavigationDirection,
        currentRegion: FocusableRegion,
        candidates: [FocusableRegion]
    ) -> FocusableTarget? {
        let currentCenter = center(of: currentRegion.rect)
        let scored = candidates.compactMap { candidate -> (score: Double, target: FocusableTarget)? in
            guard candidate.target != currentRegion.target else {
                return nil
            }

            let candidateCenter = center(of: candidate.rect)
            let dx = candidateCenter.x - currentCenter.x
            let dy = candidateCenter.y - currentCenter.y

            switch direction {
            case .up:
                guard dy < -0.5 else { return nil }
                return (abs(dy) * 1000 + abs(dx), candidate.target)
            case .down:
                guard dy > 0.5 else { return nil }
                return (abs(dy) * 1000 + abs(dx), candidate.target)
            case .left:
                guard dx < -0.5 else { return nil }
                return (abs(dx) * 1000 + abs(dy), candidate.target)
            case .right:
                guard dx > 0.5 else { return nil }
                return (abs(dx) * 1000 + abs(dy), candidate.target)
            case .next, .previous:
                return nil
            }
        }

        return scored.min(by: { $0.score < $1.score })?.target
    }

    private static func uniqueFocusRegions(from output: RenderPipelineOutput) -> [FocusableRegion] {
        var seen = Set<FocusableTarget>()
        var ordered: [FocusableRegion] = []
        for region in output.focusRegions {
            if seen.insert(region.target).inserted {
                ordered.append(region)
            }
        }
        return ordered
    }

    private static func directionalAction(
        for direction: FocusNavigationDirection,
        currentRegion: InteractionRegion,
        candidates: [InteractionRegion]
    ) -> UIActionID? {
        let currentCenter = center(of: currentRegion.rect)
        let scored = candidates.compactMap { candidate -> (score: Double, action: UIActionID)? in
            guard candidate.action != currentRegion.action else {
                return nil
            }

            let candidateCenter = center(of: candidate.rect)
            let dx = candidateCenter.x - currentCenter.x
            let dy = candidateCenter.y - currentCenter.y

            switch direction {
            case .up:
                guard dy < -0.5 else { return nil }
                return (abs(dy) * 1000 + abs(dx), candidate.action)
            case .down:
                guard dy > 0.5 else { return nil }
                return (abs(dy) * 1000 + abs(dx), candidate.action)
            case .left:
                guard dx < -0.5 else { return nil }
                return (abs(dx) * 1000 + abs(dy), candidate.action)
            case .right:
                guard dx > 0.5 else { return nil }
                return (abs(dx) * 1000 + abs(dy), candidate.action)
            case .next, .previous:
                return nil
            }
        }

        return scored.min(by: { $0.score < $1.score })?.action
    }

    private static func uniqueInteractions(from output: RenderPipelineOutput) -> [InteractionRegion] {
        var seen = Set<UIActionID>()
        var ordered: [InteractionRegion] = []
        for interaction in output.interactions {
            if seen.insert(interaction.action).inserted {
                ordered.append(interaction)
            }
        }
        return ordered
    }

    private static func center(of rect: UIRect) -> UIPoint {
        UIPoint(x: rect.minX + (rect.width / 2), y: rect.minY + (rect.height / 2))
    }
}
