import EmulatorAppSDK
import Foundation
import RendererCore

public struct EmulatorRendererCompatibilityInput: Sendable {
    public let rendererMode: EmulatorRendererMode
    public let manifest: EmulatorAppManifest
    public let packageRootPath: String
    public let capabilityStatuses: [EmulatorCapabilityStatus]
    public let inspectionSnapshot: EmulatorInspectionSnapshot?
    public let output: RenderPipelineOutput?

    public init(
        rendererMode: EmulatorRendererMode,
        manifest: EmulatorAppManifest,
        packageRootPath: String,
        capabilityStatuses: [EmulatorCapabilityStatus],
        inspectionSnapshot: EmulatorInspectionSnapshot?,
        output: RenderPipelineOutput?
    ) {
        self.rendererMode = rendererMode
        self.manifest = manifest
        self.packageRootPath = packageRootPath
        self.capabilityStatuses = capabilityStatuses
        self.inspectionSnapshot = inspectionSnapshot
        self.output = output
    }
}

public enum EmulatorCompatibilityAnalyzer {
    public static func makeReport(inputs: [EmulatorRendererCompatibilityInput]) -> EmulatorCompatibilityReport {
        let rendererReports = inputs.map(makeRendererReport).sorted { $0.rendererMode < $1.rendererMode }
        let manifest = inputs.first?.manifest ?? EmulatorAppManifest(appID: "unknown", displayName: "Unknown")
        return EmulatorCompatibilityReport(
            appID: manifest.appID,
            displayName: manifest.displayName,
            rendererReports: rendererReports
        )
    }

    private static func makeRendererReport(input: EmulatorRendererCompatibilityInput) -> EmulatorRendererCompatibilityReport {
        var issues: [EmulatorCompatibilityIssue] = []

        if !input.manifest.supportedRenderers.contains(input.rendererMode) {
            issues.append(
                EmulatorCompatibilityIssue(
                    severity: .error,
                    code: "renderer.unsupported",
                    message: "Renderer \(input.rendererMode.rawValue) is not listed in supportedRenderers.",
                    rendererMode: input.rendererMode.rawValue
                )
            )
        }

        for status in input.capabilityStatuses {
            switch status.availability {
            case .available:
                continue
            case .degraded:
                issues.append(
                    EmulatorCompatibilityIssue(
                        severity: .warning,
                        code: "capability.degraded",
                        message: status.message,
                        rendererMode: input.rendererMode.rawValue,
                        metadata: ["capability": status.capability.rawValue]
                    )
                )
            case .unavailable:
                issues.append(
                    EmulatorCompatibilityIssue(
                        severity: .error,
                        code: "capability.unavailable",
                        message: status.message,
                        rendererMode: input.rendererMode.rawValue,
                        metadata: ["capability": status.capability.rawValue]
                    )
                )
            }
        }

        if let inspectionSnapshot = input.inspectionSnapshot {
            for warning in inspectionSnapshot.warnings {
                let severity: EmulatorCompatibilitySeverity = warning.contains("missing") ? .error : .warning
                let code: String
                if warning.contains("image asset missing") {
                    code = "resource.missing"
                } else if warning.contains("clipped") {
                    code = "layout.clipped"
                } else {
                    code = "layout.truncated"
                }
                issues.append(
                    EmulatorCompatibilityIssue(
                        severity: severity,
                        code: code,
                        message: warning,
                        rendererMode: input.rendererMode.rawValue
                    )
                )
            }
        }

        if let output = input.output {
            for interaction in output.interactions where interaction.rect.width <= 1 || interaction.rect.height <= 1 {
                issues.append(
                    EmulatorCompatibilityIssue(
                        severity: .warning,
                        code: "focus.unreachable",
                        message: "Action \(interaction.action) has a near-zero interaction region.",
                        rendererMode: input.rendererMode.rawValue,
                        metadata: ["action": interaction.action]
                    )
                )
            }
        }

        issues.append(contentsOf: localeIssues(for: input))
        return EmulatorRendererCompatibilityReport(rendererMode: input.rendererMode.rawValue, issues: issues)
    }

    private static func localeIssues(for input: EmulatorRendererCompatibilityInput) -> [EmulatorCompatibilityIssue] {
        guard let preferredLocale = input.manifest.preferredLocales.first else {
            return []
        }

        let availableLocales = availableStringLocales(in: input.packageRootPath)
        guard !availableLocales.isEmpty else {
            return []
        }

        guard !availableLocales.contains(preferredLocale) else {
            return []
        }

        return [
            EmulatorCompatibilityIssue(
                severity: .info,
                code: "locale.fallback",
                message: "Preferred locale \(preferredLocale) was not found in the app package; runtime will fall back to another locale.",
                rendererMode: input.rendererMode.rawValue,
                metadata: ["preferredLocale": preferredLocale, "availableLocales": availableLocales.sorted().joined(separator: ",")]
            )
        ]
    }

    private static func availableStringLocales(in packageRootPath: String) -> Set<String> {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: packageRootPath) else {
            return []
        }

        let rootURL = URL(fileURLWithPath: packageRootPath)
        let enumerator = fileManager.enumerator(at: rootURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        var locales = Set<String>()

        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension.caseInsensitiveCompare("json") == .orderedSame else {
                continue
            }
            guard fileURL.deletingLastPathComponent().lastPathComponent == "Strings" else {
                continue
            }
            locales.insert(fileURL.deletingPathExtension().lastPathComponent)
        }

        return locales
    }
}

public enum EmulatorDiagnosticsFormatter {
    public static func formatInspection(_ snapshot: EmulatorInspectionSnapshot, format: EmulatorDiagnosticsFormat) throws -> String {
        switch format {
        case .json:
            return try encodeJSON(snapshot)
        case .text:
            let warnings = snapshot.warnings.isEmpty ? "none" : snapshot.warnings.joined(separator: " | ")
            let interactions = snapshot.interactions
                .map { "\($0.orderIndex):\($0.action)\($0.isFocused ? "*" : "")" }
                .joined(separator: ", ")
            return [
                "inspect: \(snapshot.displayName) [\(snapshot.appID)]",
                "renderer: \(snapshot.rendererMode) locale: \(snapshot.locale)",
                "device: \(snapshot.device.preset) \(snapshot.device.orientation) \(snapshot.device.viewportWidth)x\(snapshot.device.viewportHeight)",
                "document: \(snapshot.documentTitle) layout=\(snapshot.rootLayoutMode)",
                "content-frame: \(formatRect(snapshot.contentFrame))",
                "focus: \(snapshot.focusedTargetKind ?? "none") \(snapshot.focusedTargetIdentifier ?? snapshot.focusedAction ?? "none")",
                "counts: nodes=\(snapshot.nodeCount) actions=\(snapshot.actionCount) commands=\(snapshot.commandCount)",
                "interactions: \(interactions.isEmpty ? "none" : interactions)",
                "warnings: \(warnings)",
            ].joined(separator: "\n")
        }
    }

    public static func formatTrace(_ events: [EmulatorTraceEvent], format: EmulatorDiagnosticsFormat) throws -> String {
        switch format {
        case .json:
            return try encodeJSON(events)
        case .text:
            return events.map { event in
                let metadata = event.metadata
                    .sorted(by: { $0.key < $1.key })
                    .map { "\($0.key)=\($0.value)" }
                    .joined(separator: " ")
                return "[\(event.timestampMilliseconds)] \(event.category).\(event.name)\(metadata.isEmpty ? "" : " \(metadata)")"
            }.joined(separator: "\n")
        }
    }

    public static func formatCompatibility(_ report: EmulatorCompatibilityReport, format: EmulatorDiagnosticsFormat) throws -> String {
        switch format {
        case .json:
            return try encodeJSON(report)
        case .text:
            var lines = ["compat-check: \(report.displayName) [\(report.appID)]"]
            for rendererReport in report.rendererReports {
                lines.append("renderer: \(rendererReport.rendererMode)")
                if rendererReport.issues.isEmpty {
                    lines.append("  no issues")
                    continue
                }
                for issue in rendererReport.issues {
                    let metadata = issue.metadata
                        .sorted(by: { $0.key < $1.key })
                        .map { "\($0.key)=\($0.value)" }
                        .joined(separator: " ")
                    lines.append("  [\(issue.severity.rawValue)] \(issue.code): \(issue.message)\(metadata.isEmpty ? "" : " (\(metadata))")")
                }
            }
            return lines.joined(separator: "\n")
        }
    }

    private static func encodeJSON<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    private static func formatRect(_ rect: EmulatorInspectionRect) -> String {
        "x=\(Int(rect.x)) y=\(Int(rect.y)) w=\(Int(rect.width)) h=\(Int(rect.height))"
    }
}
