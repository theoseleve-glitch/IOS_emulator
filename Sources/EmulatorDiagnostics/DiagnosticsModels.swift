import EmulatorAppSDK
import Foundation
import RendererCore

public enum EmulatorDiagnosticsFormat: String, CaseIterable, Codable, Equatable, Sendable {
    case text
    case json
}

public struct EmulatorInspectionRect: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct EmulatorInspectionDevice: Codable, Equatable, Sendable {
    public let preset: String
    public let orientation: String
    public let viewportWidth: Int
    public let viewportHeight: Int
    public let scale: Double
    public let safeAreaInsets: EmulatorInspectionInsets

    public init(
        preset: String,
        orientation: String,
        viewportWidth: Int,
        viewportHeight: Int,
        scale: Double,
        safeAreaInsets: EmulatorInspectionInsets
    ) {
        self.preset = preset
        self.orientation = orientation
        self.viewportWidth = viewportWidth
        self.viewportHeight = viewportHeight
        self.scale = scale
        self.safeAreaInsets = safeAreaInsets
    }
}

public struct EmulatorInspectionInsets: Codable, Equatable, Sendable {
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
}

public struct EmulatorViewTreeNode: Codable, Equatable, Sendable {
    public let id: String
    public let parentID: String?
    public let elementKind: String
    public let frame: EmulatorInspectionRect
    public let action: String?
    public let summary: String?
    public let childCount: Int

    public init(
        id: String,
        parentID: String?,
        elementKind: String,
        frame: EmulatorInspectionRect,
        action: String?,
        summary: String?,
        childCount: Int
    ) {
        self.id = id
        self.parentID = parentID
        self.elementKind = elementKind
        self.frame = frame
        self.action = action
        self.summary = summary
        self.childCount = childCount
    }
}

public struct EmulatorInteractionSnapshot: Codable, Equatable, Sendable {
    public let action: String
    public let rect: EmulatorInspectionRect
    public let orderIndex: Int
    public let isFocused: Bool

    public init(action: String, rect: EmulatorInspectionRect, orderIndex: Int, isFocused: Bool) {
        self.action = action
        self.rect = rect
        self.orderIndex = orderIndex
        self.isFocused = isFocused
    }
}

public struct EmulatorInspectionSnapshot: Codable, Equatable, Sendable {
    public let appID: String
    public let displayName: String
    public let rendererMode: String
    public let locale: String
    public let device: EmulatorInspectionDevice
    public let documentTitle: String
    public let rootLayoutMode: String
    public let contentFrame: EmulatorInspectionRect
    public let focusedTargetKind: String?
    public let focusedTargetIdentifier: String?
    public let focusedAction: String?
    public let nodeCount: Int
    public let actionCount: Int
    public let commandCount: Int
    public let viewTree: [EmulatorViewTreeNode]
    public let interactions: [EmulatorInteractionSnapshot]
    public let warnings: [String]

    public init(
        appID: String,
        displayName: String,
        rendererMode: String,
        locale: String,
        device: EmulatorInspectionDevice,
        documentTitle: String,
        rootLayoutMode: String,
        contentFrame: EmulatorInspectionRect,
        focusedTargetKind: String?,
        focusedTargetIdentifier: String?,
        focusedAction: String?,
        nodeCount: Int,
        actionCount: Int,
        commandCount: Int,
        viewTree: [EmulatorViewTreeNode],
        interactions: [EmulatorInteractionSnapshot],
        warnings: [String]
    ) {
        self.appID = appID
        self.displayName = displayName
        self.rendererMode = rendererMode
        self.locale = locale
        self.device = device
        self.documentTitle = documentTitle
        self.rootLayoutMode = rootLayoutMode
        self.contentFrame = contentFrame
        self.focusedTargetKind = focusedTargetKind
        self.focusedTargetIdentifier = focusedTargetIdentifier
        self.focusedAction = focusedAction
        self.nodeCount = nodeCount
        self.actionCount = actionCount
        self.commandCount = commandCount
        self.viewTree = viewTree
        self.interactions = interactions
        self.warnings = warnings
    }
}

public struct EmulatorTraceEvent: Codable, Equatable, Sendable {
    public let timestampMilliseconds: UInt64
    public let category: String
    public let name: String
    public let metadata: [String: String]

    public init(
        timestampMilliseconds: UInt64,
        category: String,
        name: String,
        metadata: [String: String]
    ) {
        self.timestampMilliseconds = timestampMilliseconds
        self.category = category
        self.name = name
        self.metadata = metadata
    }
}

public enum EmulatorCompatibilitySeverity: String, Codable, Equatable, Sendable {
    case error
    case warning
    case info
}

public struct EmulatorCompatibilityIssue: Codable, Equatable, Sendable {
    public let severity: EmulatorCompatibilitySeverity
    public let code: String
    public let message: String
    public let rendererMode: String?
    public let metadata: [String: String]

    public init(
        severity: EmulatorCompatibilitySeverity,
        code: String,
        message: String,
        rendererMode: String?,
        metadata: [String: String] = [:]
    ) {
        self.severity = severity
        self.code = code
        self.message = message
        self.rendererMode = rendererMode
        self.metadata = metadata
    }
}

public struct EmulatorRendererCompatibilityReport: Codable, Equatable, Sendable {
    public let rendererMode: String
    public let issues: [EmulatorCompatibilityIssue]

    public init(rendererMode: String, issues: [EmulatorCompatibilityIssue]) {
        self.rendererMode = rendererMode
        self.issues = issues
    }
}

public struct EmulatorCompatibilityReport: Codable, Equatable, Sendable {
    public let appID: String
    public let displayName: String
    public let rendererReports: [EmulatorRendererCompatibilityReport]

    public init(appID: String, displayName: String, rendererReports: [EmulatorRendererCompatibilityReport]) {
        self.appID = appID
        self.displayName = displayName
        self.rendererReports = rendererReports
    }

    public var issues: [EmulatorCompatibilityIssue] {
        rendererReports.flatMap(\.issues)
    }

    public var hasErrors: Bool {
        issues.contains(where: { $0.severity == .error })
    }
}
