import RendererCore

public struct TerminalRenderer: ScreenRenderer {
    public init() {}

    public func render(_ document: ScreenDocument, in viewport: DeviceViewport) -> String {
        let output = RenderPipeline.makeDisplayList(for: document, in: viewport)
        let contentFrame = output.layoutTree.children.first?.frame
        let innerWidth = max(12, min(viewport.width - 4, Int(contentFrame?.width.rounded(.down) ?? Double(viewport.width - 4))))
        let totalHeight = max(6, min(viewport.height, Int((contentFrame?.height ?? Double(viewport.height)).rounded(.up)) + 2))
        let border = "+" + String(repeating: "-", count: innerWidth + 2) + "+"
        var bodyLines: [String] = [
            centered(document.title, width: innerWidth),
            String(repeating: "-", count: innerWidth),
        ]

        if let content = output.layoutTree.children.first {
            bodyLines.append(contentsOf: lines(for: content, width: innerWidth))
        }

        if bodyLines.count > totalHeight - 2 {
            bodyLines = Array(bodyLines.prefix(totalHeight - 2))
        }

        while bodyLines.count < totalHeight - 2 {
            bodyLines.append("")
        }

        let framedLines = bodyLines.map { "| " + padded($0, width: innerWidth) + " |" }
        return ([border] + framedLines + [border]).joined(separator: "\n")
    }

    private func lines(for node: LayoutNode, width: Int) -> [String] {
        switch node.element {
        case .screen:
            return orderedChildren(node).flatMap { lines(for: $0, width: width) }
        case .vStack, .padding, .frame, .list, .navigationStack, .gestureSurface:
            return orderedChildren(node).flatMap { lines(for: $0, width: width) }
        case .hStack:
            return horizontalLines(for: node, width: width)
        case .navigationBar(let title):
            let hasBackButton = node.children.contains { child in
                if case .button = child.element {
                    return true
                }
                return false
            }
            let prefix = hasBackButton ? "< Back | " : ""
            return [truncate(prefix + title, width: width)]
        case .text(let text):
            return wrap(text.content, width: width)
        case .image(let image):
            return [truncate("[image: \(image.asset.name)]", width: width)]
        case .textField(let model):
            let visible = model.text.isEmpty ? model.placeholder : model.text
            let prefix = model.text.isEmpty ? "[field: " : "[input: "
            let caret = model.text.isEmpty ? "" : "|"
            return [truncate("\(prefix)\(visible)\(caret)]", width: width)]
        case .divider:
            return [String(repeating: "-", count: width)]
        case .button(let button):
            return ["[ \(truncate(button.title, width: max(1, width - 4))) ]"]
        case .gauge(let model):
            return [gaugeLine(model, width: width)]
        case .spacer:
            return [""]
        case .listRow(let item, let selected):
            var rendered = ["\(selected ? ">" : "-") \(item.title)"]
            if let subtitle = item.subtitle {
                rendered.append(contentsOf: wrap(subtitle, width: max(1, width - 2)).map { "  \($0)" })
            }
            return rendered
        }
    }

    private func gaugeLine(_ model: GaugeModel, width: Int) -> String {
        let normalized = model.normalizedValue
        let label = "\(model.label) "
        let valueText = " \(Int(model.value)) \(model.unit)"
        let barWidth = max(8, width - label.count - valueText.count - 3)
        let filledWidth = Int((Double(barWidth) * normalized).rounded())
        let bar = "[" + String(repeating: "#", count: filledWidth) + String(repeating: "-", count: max(0, barWidth - filledWidth)) + "]"
        return truncate(label + bar + valueText, width: width)
    }

    private func wrap(_ text: String, width: Int) -> [String] {
        guard width > 0 else {
            return [""]
        }

        var lines: [String] = []
        var currentLine = ""

        for word in text.split(separator: " ") {
            let candidate = currentLine.isEmpty ? String(word) : currentLine + " " + word
            if candidate.count <= width {
                currentLine = candidate
            } else {
                if !currentLine.isEmpty {
                    lines.append(currentLine)
                }
                currentLine = truncate(String(word), width: width)
            }
        }

        if !currentLine.isEmpty {
            lines.append(currentLine)
        }

        return lines.isEmpty ? [""] : lines
    }

    private func centered(_ value: String, width: Int) -> String {
        let clipped = truncate(value, width: width)
        let padding = max(0, width - clipped.count)
        let left = padding / 2
        let right = padding - left
        return String(repeating: " ", count: left) + clipped + String(repeating: " ", count: right)
    }

    private func padded(_ value: String, width: Int) -> String {
        let clipped = truncate(value, width: width)
        return clipped + String(repeating: " ", count: max(0, width - clipped.count))
    }

    private func truncate(_ value: String, width: Int) -> String {
        guard value.count > width else {
            return value
        }

        return String(value.prefix(max(0, width)))
    }

    private func orderedChildren(_ node: LayoutNode) -> [LayoutNode] {
        node.children.sorted { lhs, rhs in
            if abs(lhs.frame.minY - rhs.frame.minY) < 0.5 {
                return lhs.frame.minX < rhs.frame.minX
            }
            return lhs.frame.minY < rhs.frame.minY
        }
    }

    private func horizontalLines(for node: LayoutNode, width: Int) -> [String] {
        let children = orderedChildren(node)
        guard !children.isEmpty else {
            return [""]
        }

        let spacing = 2
        let totalSpacing = spacing * max(0, children.count - 1)
        let availableWidth = max(children.count, width - totalSpacing)
        let resolvedWidths = childWidths(for: children, totalWidth: availableWidth)
        let renderedChildren = zip(children, resolvedWidths).map { child, childWidth in
            lines(for: child, width: childWidth)
        }
        let lineCount = renderedChildren.map(\.count).max() ?? 0
        var mergedLines: [String] = []

        for lineIndex in 0..<lineCount {
            let segments = zip(renderedChildren, resolvedWidths).map { childLines, childWidth in
                let value = lineIndex < childLines.count ? childLines[lineIndex] : ""
                return padded(value, width: childWidth)
            }
            mergedLines.append(truncate(segments.joined(separator: String(repeating: " ", count: spacing)), width: width))
        }

        return mergedLines
    }

    private func childWidths(for children: [LayoutNode], totalWidth: Int) -> [Int] {
        let measuredWidths = children.map { max(1.0, $0.frame.width) }
        let totalMeasured = measuredWidths.reduce(0, +)
        guard totalMeasured > 0 else {
            return Array(repeating: max(1, totalWidth / max(1, children.count)), count: children.count)
        }

        var widths = measuredWidths.map { measured in
            max(1, Int((measured / totalMeasured * Double(totalWidth)).rounded(.down)))
        }

        var remainder = totalWidth - widths.reduce(0, +)
        var index = 0
        while remainder > 0 && !widths.isEmpty {
            widths[index % widths.count] += 1
            remainder -= 1
            index += 1
        }

        return widths
    }
}
