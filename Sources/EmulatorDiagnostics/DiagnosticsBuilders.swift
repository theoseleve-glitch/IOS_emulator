import EmulatorAppSDK
import Foundation
import RendererCore

public enum EmulatorInspectionBuilder {
    public static func makeSnapshot(
        manifest: EmulatorAppManifest,
        environment: EmulatorRenderEnvironment,
        document: ScreenDocument,
        output: RenderPipelineOutput,
        focusedAction: UIActionID? = nil
    ) -> EmulatorInspectionSnapshot {
        let contentFrame = output.layoutTree.children.first?.frame ?? output.layoutTree.frame
        let viewTree = flattenTree(root: output.layoutTree)
        let warnings = layoutWarnings(
            document: document,
            contentFrame: contentFrame,
            output: output
        )

        return EmulatorInspectionSnapshot(
            appID: manifest.appID,
            displayName: manifest.displayName,
            rendererMode: environment.rendererMode.rawValue,
            locale: environment.locale,
            device: inspectionDevice(from: environment.device),
            documentTitle: document.title,
            rootLayoutMode: document.rootLayoutMode.rawValue,
            contentFrame: inspectionRect(from: contentFrame),
            focusedTargetKind: output.focusedTarget.map(focusedTargetKind),
            focusedTargetIdentifier: output.focusedTarget.map(focusedTargetIdentifier),
            focusedAction: focusedAction ?? output.focusedTarget.flatMap {
                if case .action(let action) = $0 {
                    return action
                }
                return nil
            },
            nodeCount: viewTree.count,
            actionCount: output.interactions.count,
            commandCount: output.commands.count,
            viewTree: viewTree,
            interactions: output.interactions.enumerated().map { index, interaction in
                EmulatorInteractionSnapshot(
                    action: interaction.action,
                    rect: inspectionRect(from: interaction.rect),
                    orderIndex: index,
                    isFocused: interaction.action == focusedAction
                )
            },
            warnings: warnings
        )
    }

    static func layoutWarnings(
        document: ScreenDocument,
        contentFrame: UIRect,
        output: RenderPipelineOutput
    ) -> [String] {
        var warnings: [String] = []

        for command in output.commands {
            switch command {
            case .text(let value, let rect, let style):
                if rect.maxX > contentFrame.maxX + 0.5 || rect.maxY > contentFrame.maxY + 0.5 {
                    warnings.append("text clipped outside content frame: \(trimmed(value))")
                } else if estimatedTextWidth(value, fontSize: style.font.size) > rect.width + 0.5 {
                    warnings.append("text may be truncated: \(trimmed(value))")
                } else if let lineLimit = style.lineLimit, wrappedLineCount(for: value, width: rect.width, fontSize: style.font.size) > lineLimit {
                    warnings.append("text exceeded line limit: \(trimmed(value))")
                }
            case .image(let assetName, let assetPath, let rect):
                if !FileManager.default.fileExists(atPath: assetPath) {
                    warnings.append("image asset missing: \(assetName)")
                }
                if rect.maxX > contentFrame.maxX + 0.5 || rect.maxY > contentFrame.maxY + 0.5 {
                    warnings.append("image clipped outside content frame: \(assetName)")
                }
            default:
                break
            }
        }

        if document.rootLayoutMode == .safeArea, contentFrame.width <= 1 || contentFrame.height <= 1 {
            warnings.append("safe-area content frame collapsed to a near-zero region")
        }

        return Array(NSOrderedSet(array: warnings).compactMap { $0 as? String })
    }

    private static func flattenTree(root: LayoutNode) -> [EmulatorViewTreeNode] {
        var nodes: [EmulatorViewTreeNode] = []
        var nextID = 0

        func visit(node: LayoutNode, parentID: String?) {
            let nodeID = "node-\(nextID)"
            nextID += 1
            nodes.append(
                EmulatorViewTreeNode(
                    id: nodeID,
                    parentID: parentID,
                    elementKind: elementKind(for: node.element),
                    frame: inspectionRect(from: node.frame),
                    action: node.action,
                    summary: summary(for: node.element),
                    childCount: node.children.count
                )
            )
            for child in node.children {
                visit(node: child, parentID: nodeID)
            }
        }

        visit(node: root, parentID: nil)
        return nodes
    }

    private static func elementKind(for element: LayoutElement) -> String {
        switch element {
        case .screen:
            return "screen"
        case .vStack:
            return "vStack"
        case .hStack:
            return "hStack"
        case .text:
            return "text"
        case .image:
            return "image"
        case .textField:
            return "textField"
        case .gestureSurface:
            return "gestureSurface"
        case .divider:
            return "divider"
        case .button:
            return "button"
        case .gauge:
            return "gauge"
        case .spacer:
            return "spacer"
        case .list:
            return "list"
        case .listRow:
            return "listRow"
        case .navigationStack:
            return "navigationStack"
        case .navigationBar:
            return "navigationBar"
        case .padding:
            return "padding"
        case .frame:
            return "frame"
        }
    }

    private static func summary(for element: LayoutElement) -> String? {
        switch element {
        case .screen(let title, _):
            return title
        case .text(let text):
            return trimmed(text.content)
        case .image(let image):
            return image.asset.name
        case .textField(let textField):
            return textField.text.isEmpty ? textField.placeholder : textField.text
        case .gestureSurface(let id):
            return id
        case .button(let button):
            return button.title
        case .gauge(let gauge):
            return "\(gauge.label): \(Int(gauge.value)) \(gauge.unit)"
        case .listRow(let item, _):
            return item.title
        case .navigationBar(let title):
            return title
        case .navigationStack(let navigation):
            return navigation.title
        case .list(let list):
            return "\(list.items.count) items"
        case .divider, .spacer, .padding, .frame, .vStack, .hStack:
            return nil
        }
    }

    private static func trimmed(_ value: String) -> String {
        let sanitized = value.replacingOccurrences(of: "\n", with: " ")
        if sanitized.count <= 60 {
            return sanitized
        }
        return String(sanitized.prefix(57)) + "..."
    }

    private static func inspectionDevice(from environment: EmulatorDeviceEnvironment) -> EmulatorInspectionDevice {
        EmulatorInspectionDevice(
            preset: environment.preset.rawValue,
            orientation: environment.orientation.rawValue,
            viewportWidth: environment.viewport.width,
            viewportHeight: environment.viewport.height,
            scale: environment.scale,
            safeAreaInsets: EmulatorInspectionInsets(
                top: environment.safeAreaInsets.top,
                leading: environment.safeAreaInsets.leading,
                bottom: environment.safeAreaInsets.bottom,
                trailing: environment.safeAreaInsets.trailing
            )
        )
    }

    private static func focusedTargetKind(_ target: FocusableTarget) -> String {
        switch target {
        case .action:
            return "action"
        case .textField:
            return "textField"
        case .gestureSurface:
            return "gestureSurface"
        }
    }

    private static func focusedTargetIdentifier(_ target: FocusableTarget) -> String {
        switch target {
        case .action(let value), .textField(let value), .gestureSurface(let value):
            return value
        }
    }

    static func inspectionRect(from rect: UIRect) -> EmulatorInspectionRect {
        EmulatorInspectionRect(
            x: rect.minX,
            y: rect.minY,
            width: rect.width,
            height: rect.height
        )
    }

    private static func estimatedTextWidth(_ text: String, fontSize: Double) -> Double {
        Double(text.count) * fontSize * 0.56
    }

    private static func wrappedLineCount(for text: String, width: Double, fontSize: Double) -> Int {
        let characterCapacity = max(1, Int((width / max(1, fontSize * 0.56)).rounded(.down)))
        var lines = 1
        var currentCount = 0

        for word in text.split(separator: " ") {
            let wordCount = word.count
            if currentCount == 0 {
                currentCount = wordCount
                continue
            }

            if currentCount + 1 + wordCount > characterCapacity {
                lines += 1
                currentCount = wordCount
            } else {
                currentCount += 1 + wordCount
            }
        }

        return lines
    }
}

public final class EmulatorTraceRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let timeProvider: @Sendable () -> UInt64
    private var events: [EmulatorTraceEvent] = []

    public init(timeProvider: @escaping @Sendable () -> UInt64 = EmulatorTraceRecorder.defaultTimeProvider) {
        self.timeProvider = timeProvider
    }

    public func record(category: String, name: String, metadata: [String: String] = [:]) {
        let event = EmulatorTraceEvent(
            timestampMilliseconds: timeProvider(),
            category: category,
            name: name,
            metadata: metadata
        )
        lock.withLock {
            events.append(event)
        }
    }

    public func recordAppDiagnostics(_ diagnostics: [EmulatorRecordedDiagnostic]) {
        for diagnostic in diagnostics {
            let event = EmulatorTraceEvent(
                timestampMilliseconds: diagnostic.timestampMilliseconds,
                category: diagnostic.kind.rawValue,
                name: diagnostic.label,
                metadata: diagnostic.metadata
            )
            lock.withLock {
                events.append(event)
            }
        }
    }

    public func snapshot() -> [EmulatorTraceEvent] {
        lock.withLock {
            events.sorted {
                if $0.timestampMilliseconds == $1.timestampMilliseconds {
                    if $0.category == $1.category {
                        return $0.name < $1.name
                    }
                    return $0.category < $1.category
                }
                return $0.timestampMilliseconds < $1.timestampMilliseconds
            }
        }
    }

    public static func defaultTimeProvider() -> UInt64 {
        UInt64(ProcessInfo.processInfo.systemUptime * 1000.0)
    }
}
