import Foundation

public struct EmulatorRecordedDiagnostic: Equatable, Sendable {
    public enum Kind: String, Codable, Equatable, Sendable {
        case mark
        case warning
    }

    public let kind: Kind
    public let label: String
    public let metadata: [String: String]
    public let timestampMilliseconds: UInt64

    public init(
        kind: Kind,
        label: String,
        metadata: [String: String],
        timestampMilliseconds: UInt64
    ) {
        self.kind = kind
        self.label = label
        self.metadata = metadata
        self.timestampMilliseconds = timestampMilliseconds
    }
}

public protocol EmulatorDiagnosticsService: Sendable {
    func mark(_ name: String, metadata: [String: String])
    func recordWarning(_ message: String, metadata: [String: String])
}

public final class NoopDiagnosticsService: EmulatorDiagnosticsService, @unchecked Sendable {
    public init() {}

    public func mark(_ name: String, metadata: [String: String]) {}
    public func recordWarning(_ message: String, metadata: [String: String]) {}
}

public final class BufferedDiagnosticsService: EmulatorDiagnosticsService, @unchecked Sendable {
    private let lock = NSLock()
    private let timeProvider: @Sendable () -> UInt64
    private var entries: [EmulatorRecordedDiagnostic] = []

    public init(timeProvider: @escaping @Sendable () -> UInt64 = BufferedDiagnosticsService.defaultTimeProvider) {
        self.timeProvider = timeProvider
    }

    public func mark(_ name: String, metadata: [String: String] = [:]) {
        append(kind: .mark, label: name, metadata: metadata)
    }

    public func recordWarning(_ message: String, metadata: [String: String] = [:]) {
        append(kind: .warning, label: message, metadata: metadata)
    }

    public func snapshot() -> [EmulatorRecordedDiagnostic] {
        lock.withLock {
            entries
        }
    }

    public func reset() {
        lock.withLock {
            entries.removeAll()
        }
    }

    private func append(kind: EmulatorRecordedDiagnostic.Kind, label: String, metadata: [String: String]) {
        let entry = EmulatorRecordedDiagnostic(
            kind: kind,
            label: label,
            metadata: metadata,
            timestampMilliseconds: timeProvider()
        )
        lock.withLock {
            entries.append(entry)
        }
    }

    public static func defaultTimeProvider() -> UInt64 {
        UInt64(ProcessInfo.processInfo.systemUptime * 1000.0)
    }
}
