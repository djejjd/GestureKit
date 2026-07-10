import Foundation
import GestureKitCore

// ============================================================
// EvidenceBundleExporter — 诊断证据包导出
// ============================================================
//
// 本文件实现证据包的独立导出功能。证据包包含：
// - manifest.json：元数据清单，含 schema/redaction 版本、
//   ID 因果关系、配置 hash、能力版本、时间基准、终态和缺失范围
// - events.json：操作原始事件列表
//
// 所有导出文件权限设为 0600（仅当前用户可读写）。
//
// 预算约束：导出副本不计入受管理诊断总预算。

// MARK: - EvidenceManifest

/// 证据包清单结构。
public struct EvidenceManifest: Codable, Sendable, Equatable {
    /// 编码键枚举，排除有默认值的 exporterVersion
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, redactionVersion, redactionApplied, exportedAt, operationId
        case terminalState, startedAt, lastEventAt, eventCount
        case eventIds, producerSessions, producerSequences, missingRanges
    }
    /// Schema 版本号
    public let schemaVersion: String
    /// 脱敏规则版本号
    public let redactionVersion: String
    /// 导出时是否对事件 payload 进行了额外脱敏
    public let redactionApplied: Bool
    /// 导出时刻的 Unix 毫秒时间戳
    public let exportedAt: Int64
    /// 被导出的操作 ID
    public let operationId: String
    /// 操作的终端状态
    public let terminalState: String?
    /// 操作开始时间
    public let startedAt: Int64
    /// 操作最后事件时间
    public let lastEventAt: Int64
    /// 事件数量
    public let eventCount: Int
    /// 事件 ID 列表（反映因果关系）
    public let eventIds: [String]
    /// 涉及的 producer 会话 ID 集合
    public let producerSessions: [String]
    /// 生产者侧序号列表（用于检测缺口）
    public let producerSequences: [Int64]
    /// 生产者序号中的缺失段（若有）
    public let missingRanges: [SequenceRange]?
    /// 导出程序版本
    public let exporterVersion: String = "1.0.0"

    public init(
        schemaVersion: String,
        redactionVersion: String,
        redactionApplied: Bool = false,
        exportedAt: Int64,
        operationId: String,
        terminalState: String?,
        startedAt: Int64,
        lastEventAt: Int64,
        eventCount: Int,
        eventIds: [String],
        producerSessions: [String],
        producerSequences: [Int64],
        missingRanges: [SequenceRange]?
    ) {
        self.schemaVersion = schemaVersion
        self.redactionVersion = redactionVersion
        self.redactionApplied = redactionApplied
        self.exportedAt = exportedAt
        self.operationId = operationId
        self.terminalState = terminalState
        self.startedAt = startedAt
        self.lastEventAt = lastEventAt
        self.eventCount = eventCount
        self.eventIds = eventIds
        self.producerSessions = producerSessions
        self.producerSequences = producerSequences
        self.missingRanges = missingRanges
    }
}

/// 序号范围，用于描述事件序列中的缺口。
public struct SequenceRange: Codable, Sendable, Equatable, Hashable {
    /// 该缺口所属的生产者会话；不同会话的 sequence 不可混算。
    public let producerSessionId: String
    /// 缺失段的起始序号
    public let from: Int64
    /// 缺失段的结束序号
    public let to: Int64

    public init(producerSessionId: String, from: Int64, to: Int64) {
        self.producerSessionId = producerSessionId
        self.from = from
        self.to = to
    }
}

// MARK: - Exporter 错误

/// 证据包导出过程中的错误类型。
public enum EvidenceExportError: Error, Equatable {
    /// 操作不存在
    case operationNotFound(String)
    /// 无法创建导出目录
    case directoryCreationFailed(String)
    /// 文件写入失败
    case fileWriteFailed(String)

    /// 操作日志查询接口不可用
    case journalNotAvailable
}

extension EvidenceExportError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .operationNotFound(let id):
            return "证据包导出失败：操作 \(id) 不存在"
        case .directoryCreationFailed(let detail):
            return "证据包导出目录创建失败: \(detail)"
        case .fileWriteFailed(let detail):
            return "证据包文件写入失败: \(detail)"
        case .journalNotAvailable:
            return "证据包导出失败：操作日志不可用"
        }
    }
}

// MARK: - EvidenceBundleExporter

/// 证据包导出器，用于将操作时间线导出为文件包。
///
/// 使用示例：
/// ```swift
/// let exporter = EvidenceBundleExporter()
/// try exporter.export(operationId: "op-001",
///                     from: journal,
///                     to: exportURL)
/// // 在 exportURL 下生成 manifest.json 和 events.json
/// ```
public struct EvidenceBundleExporter: Sendable {
    /// Schema 版本号
    public let schemaVersion: String
    /// 脱敏规则版本号
    public let redactionVersion: String

    /// 创建一个证据包导出器。
    /// - Parameters:
    ///   - schemaVersion: 数据 schema 版本，默认 "1.0"
    ///   - redactionVersion: 脱敏规则版本，默认 "1.0"
    public init(schemaVersion: String = "1.0", redactionVersion: String = "1.0") {
        self.schemaVersion = schemaVersion
        self.redactionVersion = redactionVersion
    }

    /// 将操作时间线导出为证据包文件。
    ///
    /// - Parameters:
    ///   - timeline: 操作时间线（由 OperationJournal.query 返回）
    ///   - url: 导出目标的目录 URL
    ///   - redactor: 导出前使用的脱敏器；未提供时创建独立实例，导出不能跳过脱敏。
    /// - Throws: EvidenceExportError
    public func export(timeline: OperationTimeline, to url: URL, redactor: DiagnosticRedactor? = nil) throws {
        // 创建或修正导出目录权限为 0700
        try createExportDirectory(url)

        // 计算缺失范围
        let missingRanges = computeMissingRanges(events: timeline.events)

        // 导出始终做第三次脱敏，避免入库前的边界失误扩大为可携带的证据泄漏。
        let effectiveRedactor = redactor ?? DiagnosticRedactor()
        let redactionApplied = true
        let events = timeline.events.map { redactEvent($0, using: effectiveRedactor) }

        // 构建并写入 manifest
        let manifest = buildManifest(from: timeline, missingRanges: missingRanges, redactionApplied: redactionApplied)
        try writeJSON(manifest, to: url.appendingPathComponent("manifest.json"))

        // 写入已结构化脱敏的事件数据，不对 JSON 文本做脆弱的正则替换。
        let eventEncoder = JSONEncoder()
        eventEncoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let rawEventsData = try eventEncoder.encode(events)
        let eventsURL = url.appendingPathComponent("events.json")
        try rawEventsData.write(to: eventsURL, options: .atomic)
        try setFilePermissions(eventsURL)

        // 写入叙述性摘要
        try writeSummary(timeline, to: url)
    }

    // MARK: - 内部方法

    /// 创建导出目录并强制设为 0700。如果目录已存在，则修正其权限。
    private func createExportDirectory(_ url: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            // 已存在目录：修正权限为 0700
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        } else {
            do {
                try fm.createDirectory(
                    at: url,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
            } catch {
                throw EvidenceExportError.directoryCreationFailed(error.localizedDescription)
            }
        }
    }

    /// 构建证据包 manifest。
    private func buildManifest(from timeline: OperationTimeline, missingRanges: [SequenceRange]?, redactionApplied: Bool = false) -> EvidenceManifest {
        let uniqueSessions = Array(Set(timeline.events.map(\.producerSessionId)))
        let sequences = timeline.events.map(\.producerSequence)

        return EvidenceManifest(
            schemaVersion: schemaVersion,
            redactionVersion: redactionVersion,
            redactionApplied: redactionApplied,
            exportedAt: Int64(Date().timeIntervalSince1970 * 1000),
            operationId: timeline.operationId,
            terminalState: timeline.terminalState?.rawValue,
            startedAt: timeline.startedAt,
            lastEventAt: timeline.lastEventAt,
            eventCount: timeline.events.count,
            eventIds: timeline.events.map(\.eventId),
            producerSessions: uniqueSessions,
            producerSequences: sequences,
            missingRanges: missingRanges
        )
    }

    /// 将 Codable 值写为格式化 JSON 文件，权限 0600。
    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
        try setFilePermissions(url)
    }

    /// 写入叙述性摘要（纯文本，便于快速查阅）。
    private func writeSummary(_ timeline: OperationTimeline, to url: URL) throws {
        let state = timeline.terminalState?.rawValue ?? "in_progress"
        let summary = """
        GestureKit 操作证据包
        =====================
        操作 ID:     \(timeline.operationId)
        终态:        \(state)
        开始时间:    \(formatTimestamp(timeline.startedAt))
        最后事件:    \(formatTimestamp(timeline.lastEventAt))
        事件数:      \(timeline.events.count)
        导出时间:    \(formatTimestamp(Int64(Date().timeIntervalSince1970 * 1000)))

        事件序列:
        \(timeline.events.enumerated().map { (i, event) in
            "  \(i + 1). [\(event.type.rawValue)] \(event.eventId) @ seq=\(event.producerSequence)"
        }.joined(separator: "\n"))

        本包包含原始诊断数据，仅限授权人员查阅。
        """
        let summaryURL = url.appendingPathComponent("README.txt")
        try summary.write(to: summaryURL, atomically: true, encoding: .utf8)
        try setFilePermissions(summaryURL)
    }

    /// 设置文件权限为 0600。
    private func setFilePermissions(_ url: URL) throws {
        let fd = url.path
        guard chmod(fd, 0o600) == 0 else {
            throw EvidenceExportError.fileWriteFailed("chmod 0600: \(url.path)")
        }
    }

    /// 计算序列中的缺失段。
    /// 例如：序列 [1, 2, 5, 6, 10] → [{from: 3, to: 4}, {from: 7, to: 9}]
    private func computeMissingRanges(events: [ProviderEvent]) -> [SequenceRange]? {
        let grouped = Dictionary(grouping: events, by: \.producerSessionId)
        var ranges: [SequenceRange] = []

        for (sessionId, sessionEvents) in grouped {
            let sorted = sessionEvents.map(\.producerSequence).sorted()
            for i in 0..<(max(sorted.count - 1, 0)) {
                let current = sorted[i]
                let next = sorted[i + 1]
                if next - current > 1 {
                    ranges.append(SequenceRange(producerSessionId: sessionId, from: current + 1, to: next - 1))
                }
            }
        }

        return ranges.isEmpty ? nil : ranges
    }

    /// 仅在具备页面或目标引用的结构化 payload 上执行脱敏，避免 JSON 字符串替换遗漏或破坏格式。
    private func redactEvent(_ event: ProviderEvent, using redactor: DiagnosticRedactor) -> ProviderEvent {
        let payload: ProviderPayload
        switch event.payload {
        case .contextSnapshot(let context):
            payload = .contextSnapshot(ContextSnapshotPayload(
                contextId: context.contextId,
                pageIdentity: redactor.redactURL(context.pageIdentity),
                expiresAt: context.expiresAt,
                targetKind: context.targetKind,
                targetRef: nil
            ))
        case .actionRequest(let action):
            payload = .actionRequest(ActionDescriptor(
                actionId: action.actionId,
                contextId: action.contextId,
                targetRef: nil,
                parameters: action.parameters,
                deadline: action.deadline
            ))
        default:
            payload = event.payload
        }
        return ProviderEvent(
            eventId: event.eventId,
            producerSessionId: event.producerSessionId,
            producerSequence: event.producerSequence,
            causedByEventId: event.causedByEventId,
            monotonicClockMs: event.monotonicClockMs,
            wallClockMs: event.wallClockMs,
            gestureSessionId: event.gestureSessionId,
            operationId: event.operationId,
            type: event.type,
            payload: payload
        )
    }

    /// 格式化 Unix 毫秒时间戳为可读字符串。
    private func formatTimestamp(_ ms: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
