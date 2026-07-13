import Foundation
import CSQLite
import GestureKitCore

// ============================================================
// OperationJournal — SQLite 持久化操作账本
// ============================================================
//
// 本文件实现 Provider Protocol v2 的操作持久化方案，基于 SQLite
// WAL 模式提供 ACID 语义和并发读取。所有 SQLite 访问通过一个串行
// 队列同步，确保线程安全。
//
// Schema 版本 v1 包含 5 张表：
// - sessions：手势会话生命周期
// - operations：操作/动作执行记录
// - events：ProviderEvent 不可变事件流
// - provider_sessions：Provider 注册/会话记录
// - configuration_snapshots：配置快照记录
//
// 容量管理：App Journal 总额度 45 MB（主库 + WAL + SHM），超过时
// 先压缩已完成操作，若关键事件仍无法写入则返回 journal_storage_full。

// MARK: - 类型定义

/// 操作的终端状态枚举。
public enum OperationTerminalState: String, Codable, Sendable, Equatable {
    /// 操作成功完成
    case succeeded
    /// 操作执行失败
    case failed
    /// 操作结果不确定（超时或 provider 断开）
    case resultUnknown = "result_unknown"
    /// 操作被中断（provider 会话断开）
    case operationInterrupted = "operation_interrupted"
}

/// 恢复操作时的输出结构，用于重连时对账。
public struct RecoveredOperation: Codable, Sendable, Equatable {
    /// 操作唯一标识
    public let operationId: String
    /// 产生此操作的 Producer 会话 ID
    public let producerSessionId: String
    /// 恢复后的终端状态
    public let terminalState: OperationTerminalState
    /// 最后事件的时间戳
    public let lastEventAt: Int64

    public init(operationId: String, producerSessionId: String, terminalState: OperationTerminalState, lastEventAt: Int64) {
        self.operationId = operationId
        self.producerSessionId = producerSessionId
        self.terminalState = terminalState
        self.lastEventAt = lastEventAt
    }
}

/// 操作查询过滤器。
public struct OperationFilter: Sendable, Equatable {
    /// 按 Producer 会话 ID 筛选
    public var producerSessionId: String?
    /// 按手势会话 ID 筛选
    public var gestureSessionId: String?
    /// 按操作 ID 筛选
    public var operationId: String?
    /// 按终端状态列表筛选
    public var terminalStates: [OperationTerminalState]?

    public init(
        producerSessionId: String? = nil,
        gestureSessionId: String? = nil,
        operationId: String? = nil,
        terminalStates: [OperationTerminalState]? = nil
    ) {
        self.producerSessionId = producerSessionId
        self.gestureSessionId = gestureSessionId
        self.operationId = operationId
        self.terminalStates = terminalStates
    }

    /// 创建一个按操作 ID 查询的过滤器。
    public static func operation(_ id: String) -> OperationFilter {
        OperationFilter(operationId: id)
    }
}

/// 操作的完整时间线，包含所有关联事件和终端状态。
public struct OperationTimeline: Codable, Sendable, Equatable {
    /// 操作唯一标识
    public let operationId: String
    /// 此操作的所有事件
    public let events: [ProviderEvent]
    /// 终端状态（nil 表示操作仍在进行中）
    public let terminalState: OperationTerminalState?
    /// 操作开始时间
    public let startedAt: Int64
    /// 操作最后事件时间
    public let lastEventAt: Int64

    public init(
        operationId: String,
        events: [ProviderEvent],
        terminalState: OperationTerminalState?,
        startedAt: Int64,
        lastEventAt: Int64
    ) {
        self.operationId = operationId
        self.events = events
        self.terminalState = terminalState
        self.startedAt = startedAt
        self.lastEventAt = lastEventAt
    }
}

// MARK: - SQLite 错误

/// OperationJournal 和数据库操作相关的错误类型。
public enum JournalError: Error, Equatable {
    /// Journal 存储已达容量上限
    case journalStorageFull
    /// SQLite 操作错误
    case sqliteError(String)
    /// 数据库架构版本不兼容
    case schemaMismatch(expected: Int, got: Int)
    /// 无效的操作参数
    case invalidArgument(String)
    /// 去重冲突：相同 eventId 或 (producerSessionId, producerSequence) 但内容不同
    case duplicateConflict(String)
}

extension JournalError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .journalStorageFull:
            return "OperationJournal 存储已满，暂停动作派发"
        case .sqliteError(let detail):
            return "SQLite 错误: \(detail)"
        case .schemaMismatch(let expected, let got):
            return "架构版本不匹配: 期望 \(expected)，实际 \(got)"
        case .invalidArgument(let detail):
            return "无效参数: \(detail)"
        case .duplicateConflict(let detail):
            return "去重冲突: \(detail)"
        }
    }
}

// MARK: - 协议定义

/// OperationJournal 对外暴露的操作持久化接口。
public protocol OperationJournaling: Sendable {
    /// 追加一个 ProviderEvent 到操作账本。
    /// - Parameter event: 待追加的事件
    /// - Throws: JournalError 如果存储已满或其他数据库错误
    func append(_ event: ProviderEvent) throws

    /// 恢复已过期但尚未终结的操作。
    /// - Parameter now: 当前 Unix 毫秒时间戳
    /// - Returns: 被恢复的操作列表
    /// - Throws: JournalError 数据库操作错误
    func recoverExpired(now: Int64) throws -> [RecoveredOperation]

    /// 按筛选条件查询操作时间线。
    /// - Parameters:
    ///   - filter: 查询过滤器
    ///   - limit: 最大返回数
    /// - Returns: 匹配的操作时间线列表
    /// - Throws: JournalError 数据库操作错误
    func query(_ filter: OperationFilter, limit: Int) throws -> [OperationTimeline]

    /// 导出操作证据包到指定 URL。
    /// - Parameters:
    ///   - operationId: 操作 ID
    ///   - url: 导出目标目录 URL
    /// - Throws: JournalError 或文件写入错误
    func exportEvidence(operationId: String, to url: URL) throws
}

// MARK: - SQLite 常量与辅助

/// 当前数据库 schema 版本号。
private let CURRENT_SCHEMA_VERSION: Int32 = 1

/// App Journal 默认最大容量（45 MB）。
public let DEFAULT_APP_JOURNAL_SIZE: Int64 = 45 * 1024 * 1024

/// 容量检查触发压缩的阈值比例（80%）。
private let COMPACTION_THRESHOLD: Double = 0.8

/// 检查 SQLite 操作结果，若出错则抛出 JournalError。
private func checkSQLite(_ code: Int32, context: String) throws {
    guard code == SQLITE_OK else {
        throw JournalError.sqliteError("\(context): \(String(cString: sqlite3_errstr(code)))")
    }
}

// MARK: - OperationJournal 实现

/// 基于 SQLite WAL 的操作账本实现。
///
/// 所有数据库操作通过内部串行队列同步，因此本类型符合 Sendable 契约。
/// 查询 `Sendable` 约束由 `@unchecked Sendable` 显式标记（OpaquePointer
/// 本身不是 Sendable 但通过串行队列保证安全）。
public final class OperationJournal: OperationJournaling, @unchecked Sendable {
    // MARK: 私有属性

    /// SQLite 数据库句柄
    private let db: OpaquePointer
    /// 串行队列，确保所有数据库操作有序执行
    private let queue: DispatchQueue
    /// Journal 路径
    private let journalPath: String
    /// 最大容量（字节）
    private let maxJournalSize: Int64
    /// JSON 编解码器
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    // MARK: 初始化

    /// 打开或创建 OperationJournal 数据库。
    ///
    /// - Parameters:
    ///   - path: SQLite 数据库文件路径
    ///   - maxJournalSize: Journal 最大容量，默认 45 MB
    /// - Throws: JournalError 如果数据库打开或初始化失败
    public init(path: String, maxJournalSize: Int64 = DEFAULT_APP_JOURNAL_SIZE) throws {
        self.journalPath = path
        self.maxJournalSize = maxJournalSize
        self.queue = DispatchQueue(label: "com.gesturekit.operation-journal.\(UUID().uuidString)")
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.sortedKeys]
        self.decoder = JSONDecoder()

        // 打开 SQLite 数据库
        var handle: OpaquePointer?
        let rc = sqlite3_open(path, &handle)
        guard rc == SQLITE_OK, let db = handle else {
            throw JournalError.sqliteError("无法打开数据库: \(String(cString: sqlite3_errstr(rc)))")
        }
        self.db = db

        do {
            // 启用 WAL 模式
            try self.execPragma("PRAGMA journal_mode=WAL")
            // 启用外键约束
            try self.execPragma("PRAGMA foreign_keys=ON")

            // 检查 schema 版本
            try self.migrateSchema()
        } catch {
            sqlite3_close(db)
            throw error
        }
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: - OperationJournaling 协议实现

    public func append(_ event: ProviderEvent) throws {
        try queue.sync {
            try self.appendInternal(event)
        }
    }

    public func recoverExpired(now: Int64) throws -> [RecoveredOperation] {
        try queue.sync {
            try self.recoverExpiredInternal(now: now)
        }
    }

    public func query(_ filter: OperationFilter, limit: Int) throws -> [OperationTimeline] {
        try queue.sync {
            try self.queryInternal(filter, limit: limit)
        }
    }

    public func exportEvidence(operationId: String, to url: URL) throws {
        // exportEvidence 内部调用 query，已在 query 层面同步
        try queue.sync {
            try self.exportEvidenceInternal(operationId: operationId, to: url)
        }
    }

    // MARK: - 内部实现

    /// 执行 PRAGMA 语句。
    private func execPragma(_ sql: String) throws {
        try checkSQLite(sqlite3_exec(db, sql, nil, nil, nil), context: "PRAGMA: \(sql)")
    }

    /// 读取 PRAGMA user_version，支持逐版原子升级，拒绝未来版本。
    private func migrateSchema() throws {
        // 检查 SQLite 运行时版本
        let libVersion = sqlite3_libversion_number()
        guard libVersion >= 3020000 else {
            throw JournalError.sqliteError("SQLite 版本过低，需要 3.20+，实际: \(String(cString: sqlite3_libversion()))")
        }

        // 读取当前 schema 版本
        var verStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &verStmt, nil) == SQLITE_OK else {
            throw JournalError.sqliteError("无法读取 user_version")
        }
        defer { sqlite3_finalize(verStmt) }
        var currentUserVersion: Int32 = 0
        if sqlite3_step(verStmt) == SQLITE_ROW {
            currentUserVersion = sqlite3_column_int(verStmt, 0)
        }

        // 拒绝未来版本
        if currentUserVersion > CURRENT_SCHEMA_VERSION {
            throw JournalError.schemaMismatch(
                expected: Int(CURRENT_SCHEMA_VERSION),
                got: Int(currentUserVersion)
            )
        }

        // === 逐版原子升级 ===

        // Version 0 → 1：创建初始表结构
        if currentUserVersion < 1 {
            try checkSQLite(sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, nil), context: "BEGIN migration v1")
            var migrationOK = false
            defer {
                if !migrationOK {
                    sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                }
            }

            let createTablesSQL = """
            CREATE TABLE IF NOT EXISTS sessions (
                session_id TEXT PRIMARY KEY,
                provider_session_id TEXT NOT NULL,
                gesture_session_id TEXT,
                created_at INTEGER NOT NULL,
                ended_at INTEGER
            );

            CREATE TABLE IF NOT EXISTS operations (
                operation_id TEXT PRIMARY KEY,
                producer_session_id TEXT NOT NULL,
                gesture_session_id TEXT,
                terminal_state TEXT,
                deadline INTEGER,
                created_at INTEGER NOT NULL,
                last_event_at INTEGER NOT NULL
            );

            CREATE TABLE IF NOT EXISTS events (
                event_id TEXT UNIQUE NOT NULL,
                operation_id TEXT NOT NULL,
                producer_session_id TEXT NOT NULL,
                producer_sequence INTEGER NOT NULL,
                caused_by_event_id TEXT,
                monotonic_clock_ms INTEGER NOT NULL,
                wall_clock_ms INTEGER NOT NULL,
                gesture_session_id TEXT,
                type TEXT NOT NULL,
                payload_json TEXT NOT NULL,
                recorded_at INTEGER NOT NULL,
                UNIQUE(producer_session_id, producer_sequence)
            );

            CREATE TABLE IF NOT EXISTS provider_sessions (
                provider_session_id TEXT PRIMARY KEY,
                provider_install_id TEXT NOT NULL,
                connected_at INTEGER NOT NULL,
                disconnected_at INTEGER,
                capabilities_json TEXT
            );

            CREATE TABLE IF NOT EXISTS configuration_snapshots (
                snapshot_id TEXT PRIMARY KEY,
                provider_session_id TEXT NOT NULL,
                epoch TEXT NOT NULL,
                schema_version INTEGER NOT NULL,
                config_json TEXT NOT NULL,
                captured_at INTEGER NOT NULL
            );

            CREATE INDEX IF NOT EXISTS idx_events_operation_id ON events(operation_id);
            CREATE INDEX IF NOT EXISTS idx_events_recorded_at ON events(recorded_at);
            CREATE INDEX IF NOT EXISTS idx_operations_terminal_state ON operations(terminal_state);
            CREATE INDEX IF NOT EXISTS idx_operations_deadline ON operations(deadline);
            CREATE INDEX IF NOT EXISTS idx_operations_producer_session ON operations(producer_session_id);
            """

            let statements = createTablesSQL.components(separatedBy: ";")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            for stmt in statements {
                try checkSQLite(sqlite3_exec(db, stmt + ";", nil, nil, nil), context: "CREATE TABLE/INDEX")
            }

            // 提交并标记版本
            try checkSQLite(sqlite3_exec(db, "PRAGMA user_version = 1", nil, nil, nil), context: "SET user_version=1")
            try checkSQLite(sqlite3_exec(db, "COMMIT", nil, nil, nil), context: "COMMIT migration v1")
            migrationOK = true
            currentUserVersion = 1
        }

        // 未来的版本升级在此处添加：if currentUserVersion < 2 { ... }
    }

    /// 内部追加事件（在串行队列上调用）。
    private func appendInternal(_ event: ProviderEvent) throws {
        guard let operationId = event.operationId else {
            throw JournalError.invalidArgument("ProviderEvent 缺少 operationId")
        }

        // 检查容量，接近上限时先压缩
        let currentSize = currentJournalSize()
        if currentSize > Int64(Double(maxJournalSize) * COMPACTION_THRESHOLD) {
            try compactInternal()
        }
        // 再次检查是否仍有空间
        guard currentJournalSize() < maxJournalSize else {
            throw JournalError.journalStorageFull
        }

        // 序列化 payload
        let payloadData = try encodePayloadForStorage(event.payload)
        let payloadJSON = String(data: payloadData, encoding: .utf8) ?? "{}"
        let recordedAt = Int64(Date().timeIntervalSince1970 * 1000)

        // 提取 deadline（如果 payload 是 actionRequest）
        let deadline: Int64?
        if case .actionRequest(let action) = event.payload {
            deadline = action.deadline
        } else {
            deadline = nil
        }

        // 从 ActionResultPayload.outcome 读取终端状态。
        // Journal 只能依据 outcome 字段或自身超时恢复规则写终态，
        // 不得仅凭 action_result 消息类型推断成功。
        let terminalStateValue: String?
        if case .actionResult(let result) = event.payload {
            switch result.outcome {
            case .succeeded:
                terminalStateValue = OperationTerminalState.succeeded.rawValue
            case .failed:
                terminalStateValue = OperationTerminalState.failed.rawValue
            case .resultUnknown:
                terminalStateValue = OperationTerminalState.resultUnknown.rawValue
            }
        } else {
            terminalStateValue = nil
        }

        // === 去重冲突检测（fix #2） ===
        // 检查 eventId 或 (producerSessionId, producerSequence) 是否已存在且内容不同。
        // 同内容重复为 no-op，冲突内容则拒绝。
        let existingCheckSQL = """
        SELECT event_id, operation_id, producer_session_id, producer_sequence,
               caused_by_event_id, monotonic_clock_ms, wall_clock_ms, gesture_session_id,
               type, payload_json
        FROM events
        WHERE event_id = ?1 OR (producer_session_id = ?2 AND producer_sequence = ?3)
        LIMIT 1
        """
        var checkStmt: OpaquePointer?
        let checkRC = sqlite3_prepare_v2(db, existingCheckSQL, -1, &checkStmt, nil)
        if checkRC == SQLITE_OK {
            defer { sqlite3_finalize(checkStmt) }
            try bindSQLite(stmt: checkStmt, index: 1, value: event.eventId)
            try bindSQLite(stmt: checkStmt, index: 2, value: event.producerSessionId)
            try bindSQLite(stmt: checkStmt, index: 3, value: event.producerSequence)
            if sqlite3_step(checkStmt) == SQLITE_ROW {
                let existingEventId = String(cString: sqlite3_column_text(checkStmt, 0))
                let existingOperationId = String(cString: sqlite3_column_text(checkStmt, 1))
                let existingProducerSessionId = String(cString: sqlite3_column_text(checkStmt, 2))
                let existingSequence = sqlite3_column_int64(checkStmt, 3)
                let existingCause = sqlite3_column_type(checkStmt, 4) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(checkStmt, 4))
                let existingMonotonicClock = sqlite3_column_int64(checkStmt, 5)
                let existingWallClock = sqlite3_column_int64(checkStmt, 6)
                let existingGestureSessionId = sqlite3_column_type(checkStmt, 7) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(checkStmt, 7))
                let existingType = String(cString: sqlite3_column_text(checkStmt, 8))
                let existingPayload = String(cString: sqlite3_column_text(checkStmt, 9))
                // 同内容：严格 no-op，不做任何操作
                if existingEventId == event.eventId,
                   existingOperationId == operationId,
                   existingProducerSessionId == event.producerSessionId,
                   existingSequence == event.producerSequence,
                   existingCause == event.causedByEventId,
                   existingMonotonicClock == event.monotonicClockMs,
                   existingWallClock == event.wallClockMs,
                   existingGestureSessionId == event.gestureSessionId,
                   existingPayload == payloadJSON,
                   existingType == event.type.rawValue {
                    return
                }
                // 不同内容：冲突拒绝
                throw JournalError.duplicateConflict("eventId=\(event.eventId) 或 sequence=\(event.producerSessionId):\(event.producerSequence) 已存在但内容冲突")
            }
        }

        // 使用事务保证原子性
        try checkSQLite(sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, nil), context: "BEGIN")

        var execOK = false
        defer {
            if !execOK {
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            }
        }

        // 1. 写入 events 表（INSERT OR IGNORE 实现事件去重）
        let insertEventSQL = """
        INSERT OR IGNORE INTO events
            (event_id, operation_id, producer_session_id, producer_sequence,
             caused_by_event_id, monotonic_clock_ms, wall_clock_ms, gesture_session_id, type,
             payload_json, recorded_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertEventSQL, -1, &stmt, nil) == SQLITE_OK else {
            let errMsg = String(cString: sqlite3_errmsg(db))
            throw JournalError.sqliteError("prepare events insert: \(errMsg)")
        }
        defer { sqlite3_finalize(stmt) }

        let bindings: [(Int32, Any)] = [
            (1, event.eventId),
            (2, operationId),
            (3, event.producerSessionId),
            (4, event.producerSequence),
            (5, event.causedByEventId as Any? ?? NSNull()),
            (6, event.monotonicClockMs),
            (7, event.wallClockMs),
            (8, event.gestureSessionId as Any? ?? NSNull()),
            (9, event.type.rawValue),
            (10, payloadJSON),
            (11, recordedAt),
        ]

        for (idx, value) in bindings {
            try bindSQLite(stmt: stmt, index: idx, value: value)
        }

        let stepRC = sqlite3_step(stmt)
        guard stepRC == SQLITE_DONE || stepRC == SQLITE_ROW else {
            let errMsg = String(cString: sqlite3_errmsg(db))
            throw JournalError.sqliteError("events insert: \(errMsg)")
        }

        // 2. 写入或更新 operations 表
        let upsertOperationSQL = """
        INSERT INTO operations
            (operation_id, producer_session_id, gesture_session_id, terminal_state, deadline,
             created_at, last_event_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(operation_id) DO UPDATE SET
            last_event_at = excluded.last_event_at,
            deadline = CASE WHEN operations.deadline IS NULL THEN excluded.deadline ELSE operations.deadline END,
            gesture_session_id = CASE WHEN operations.gesture_session_id IS NULL THEN excluded.gesture_session_id ELSE operations.gesture_session_id END,
            terminal_state = COALESCE(operations.terminal_state, excluded.terminal_state)
        """
        var opStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, upsertOperationSQL, -1, &opStmt, nil) == SQLITE_OK else {
            let errMsg = String(cString: sqlite3_errmsg(db))
            throw JournalError.sqliteError("prepare operations upsert: \(errMsg)")
        }
        defer { sqlite3_finalize(opStmt) }

        let opBindings: [(Int32, Any)] = [
            (1, operationId),
            (2, event.producerSessionId),
            (3, event.gestureSessionId as Any? ?? NSNull()),
            (4, terminalStateValue as Any? ?? NSNull()),
            (5, deadline as Any? ?? NSNull()),
            (6, event.wallClockMs),
            (7, event.wallClockMs),
        ]

        for (idx, value) in opBindings {
            try bindSQLite(stmt: opStmt, index: idx, value: value)
        }

        let opStepRC = sqlite3_step(opStmt)
        guard opStepRC == SQLITE_DONE else {
            let errMsg = String(cString: sqlite3_errmsg(db))
            throw JournalError.sqliteError("operations upsert: \(errMsg)")
        }

        // 提交事务
        try checkSQLite(sqlite3_exec(db, "COMMIT", nil, nil, nil), context: "COMMIT")
        execOK = true
    }

    /// 按具体 Codable payload 编码，避免 [String: Any] 桥接把 0/1 误写为 Bool。
    private func encodePayloadForStorage(_ payload: ProviderPayload) throws -> Data {
        switch payload {
        case .providerHello(let value): return try encoder.encode(value)
        case .providerChallenge(let value): return try encoder.encode(value)
        case .providerAuthenticate(let value): return try encoder.encode(value)
        case .capabilitySnapshot(let value): return try encoder.encode(value)
        case .contextRequest(let value): return try encoder.encode(value)
        case .contextSnapshot(let value): return try encoder.encode(value)
        case .configurationSnapshot(let value): return try encoder.encode(value)
        case .configurationAck(let value): return try encoder.encode(value)
        case .actionRequest(let value): return try encoder.encode(value)
        case .actionAccepted(let value): return try encoder.encode(value)
        case .actionResult(let value): return try encoder.encode(value)
        case .telemetryBatch(let value): return try encoder.encode(value)
        case .telemetryAck(let value): return try encoder.encode(value)
        case .healthProbe(let value): return try encoder.encode(value)
        case .healthResponse(let value): return try encoder.encode(value)
        case .operationStatusRequest(let value): return try encoder.encode(value)
        case .operationStatusResponse(let value): return try encoder.encode(value)
        case .controlCenterOpenRequest(let value): return try encoder.encode(value)
        case .controlCenterOpenResponse(let value): return try encoder.encode(value)
        }
    }

    /// 内部恢复过期操作。
    private func recoverExpiredInternal(now: Int64) throws -> [RecoveredOperation] {
        // 查找 deadline < now 且 terminal_state IS NULL 的操作
        let selectExpiredSQL = """
        SELECT operation_id, producer_session_id, deadline
        FROM operations
        WHERE deadline IS NOT NULL AND deadline < ? AND terminal_state IS NULL
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, selectExpiredSQL, -1, &stmt, nil) == SQLITE_OK else {
            let errMsg = String(cString: sqlite3_errmsg(db))
            throw JournalError.sqliteError("prepare select expired: \(errMsg)")
        }
        defer { sqlite3_finalize(stmt) }

        try bindSQLite(stmt: stmt, index: 1, value: now)

        var expiredOps: [(opId: String, producerSessionId: String)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let opId = String(cString: sqlite3_column_text(stmt, 0))
            let sessionId = String(cString: sqlite3_column_text(stmt, 1))
            expiredOps.append((opId, sessionId))
        }

        guard !expiredOps.isEmpty else { return [] }

        // 终态更新与合成恢复事件必须同一事务提交，不能出现“已终态但无证据”。
        try checkSQLite(sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, nil), context: "BEGIN expired recovery")
        var recoveryCommitted = false
        defer {
            if !recoveryCommitted {
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            }
        }

        // 标记为 result_unknown
        let updateSQL = """
        UPDATE operations
        SET terminal_state = 'result_unknown', last_event_at = ?
        WHERE deadline IS NOT NULL AND deadline < ? AND terminal_state IS NULL
        """
        var updateStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, updateSQL, -1, &updateStmt, nil) == SQLITE_OK else {
            let errMsg = String(cString: sqlite3_errmsg(db))
            throw JournalError.sqliteError("prepare update expired: \(errMsg)")
        }
        defer { sqlite3_finalize(updateStmt) }

        try bindSQLite(stmt: updateStmt, index: 1, value: now)
        try bindSQLite(stmt: updateStmt, index: 2, value: now)

        guard sqlite3_step(updateStmt) == SQLITE_DONE else {
            let errMsg = String(cString: sqlite3_errmsg(db))
            throw JournalError.sqliteError("update expired: \(errMsg)")
        }

        // === 追加带结构化原因的终态事件（fix #4） ===
        // 为每个恢复的操作写入一条 ProviderEvent，携带 ActionResultPayload
        //（outcome=result_unknown, reason=deadline_exceeded），
        // 保证导出的证据链能解释终态来源。
        for op in expiredOps {
            let recoveryEventId = "recovery-\(op.opId)-\(now)"
            let recoveryPayload = ProviderActionResultPayload(
                operationId: op.opId,
                outcome: .resultUnknown,
                reason: .deadlineExceeded,
                completedAt: now
            )
            let payloadData = try encoder.encode(recoveryPayload)
            let payloadJSON = String(data: payloadData, encoding: .utf8) ?? "{}"

            let insertRecoverySQL = """
            INSERT OR IGNORE INTO events
                (event_id, operation_id, producer_session_id, producer_sequence,
                 caused_by_event_id, monotonic_clock_ms, wall_clock_ms, gesture_session_id, type,
                 payload_json, recorded_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
            var recoveryStmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, insertRecoverySQL, -1, &recoveryStmt, nil) == SQLITE_OK else {
                throw JournalError.sqliteError("prepare recovery event: \(String(cString: sqlite3_errmsg(db)))")
            }
            defer { sqlite3_finalize(recoveryStmt) }
            // 合成事件由 App 生产者产生，按 operation 隔离 session，避免与 Provider 原始 sequence 冲突。
            let recoveryProducerSessionId = "app-recovery:\(op.opId)"
            let recoveryBindings: [(Int32, Any)] = [
                (1, recoveryEventId), (2, op.opId), (3, recoveryProducerSessionId), (4, Int64(1)),
                (5, NSNull()), (6, now), (7, now), (8, NSNull()),
                (9, ProviderMessageType.actionResult.rawValue), (10, payloadJSON), (11, now),
            ]
            for (index, value) in recoveryBindings {
                try bindSQLite(stmt: recoveryStmt, index: index, value: value)
            }
            guard sqlite3_step(recoveryStmt) == SQLITE_DONE else {
                throw JournalError.sqliteError("insert recovery event: \(String(cString: sqlite3_errmsg(db)))")
            }
        }

        try checkSQLite(sqlite3_exec(db, "COMMIT", nil, nil, nil), context: "COMMIT expired recovery")
        recoveryCommitted = true

        return expiredOps.map { op in
            RecoveredOperation(
                operationId: op.opId,
                producerSessionId: op.producerSessionId,
                terminalState: .resultUnknown,
                lastEventAt: now
            )
        }
    }

    /// 内部查询操作时间线。
    private func queryInternal(_ filter: OperationFilter, limit: Int) throws -> [OperationTimeline] {
        // 先查询匹配的 operation_id 列表
        var conditions: [String] = []
        var bindValues: [Any] = []

        if let opId = filter.operationId {
            conditions.append("o.operation_id = ?\(bindValues.count + 1)")
            bindValues.append(opId)
        }
        if let sessionId = filter.producerSessionId {
            conditions.append("o.producer_session_id = ?\(bindValues.count + 1)")
            bindValues.append(sessionId)
        }
        if let gestureId = filter.gestureSessionId {
            conditions.append("o.gesture_session_id = ?\(bindValues.count + 1)")
            bindValues.append(gestureId)
        }
        if let states = filter.terminalStates {
            let placeholders = states.map { _ in "?" }.joined(separator: ", ")
            conditions.append("o.terminal_state IN (\(placeholders))")
            bindValues.append(contentsOf: states.map { $0.rawValue })
        }

        let whereClause = conditions.isEmpty ? "" : "WHERE \(conditions.joined(separator: " AND "))"

        let queryOpsSQL = """
        SELECT o.operation_id, o.terminal_state, o.created_at, o.last_event_at
        FROM operations o
        \(whereClause)
        ORDER BY o.last_event_at DESC
        LIMIT ?
        """
        bindValues.append(limit)

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, queryOpsSQL, -1, &stmt, nil) == SQLITE_OK else {
            let errMsg = String(cString: sqlite3_errmsg(db))
            throw JournalError.sqliteError("prepare query operations: \(errMsg)")
        }
        defer { sqlite3_finalize(stmt) }

        for (i, value) in bindValues.enumerated() {
            try bindSQLite(stmt: stmt, index: Int32(i + 1), value: value)
        }

        var timelines: [OperationTimeline] = []

        while sqlite3_step(stmt) == SQLITE_ROW {
            let opId = String(cString: sqlite3_column_text(stmt, 0))
            let terminalStateStr = sqlite3_column_type(stmt, 1) != SQLITE_NULL
                ? String(cString: sqlite3_column_text(stmt, 1)) : nil
            let createdAt = sqlite3_column_int64(stmt, 2)
            let lastEventAt = sqlite3_column_int64(stmt, 3)

            let terminalState = terminalStateStr.flatMap { OperationTerminalState(rawValue: $0) }

            // 查询该操作的所有事件
            let events = try queryEventsForOperation(opId)
            timelines.append(OperationTimeline(
                operationId: opId,
                events: events,
                terminalState: terminalState,
                startedAt: createdAt,
                lastEventAt: lastEventAt
            ))
        }

        return timelines
    }

    /// 查询指定操作的所有事件。
    private func queryEventsForOperation(_ operationId: String) throws -> [ProviderEvent] {
        let queryEventsSQL = """
        SELECT event_id, producer_session_id, producer_sequence,
               caused_by_event_id, monotonic_clock_ms, wall_clock_ms, gesture_session_id,
               type, payload_json, recorded_at
        FROM events
        WHERE operation_id = ?
        ORDER BY producer_sequence ASC
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, queryEventsSQL, -1, &stmt, nil) == SQLITE_OK else {
            let errMsg = String(cString: sqlite3_errmsg(db))
            throw JournalError.sqliteError("prepare events query: \(errMsg)")
        }
        defer { sqlite3_finalize(stmt) }

        try bindSQLite(stmt: stmt, index: 1, value: operationId)

        var events: [ProviderEvent] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let eventId = String(cString: sqlite3_column_text(stmt, 0))
            let producerSessionId = String(cString: sqlite3_column_text(stmt, 1))
            let producerSequence = sqlite3_column_int64(stmt, 2)
            let causedByEventId = sqlite3_column_type(stmt, 3) != SQLITE_NULL
                ? String(cString: sqlite3_column_text(stmt, 3)) : nil
            let monotonicClockMs = sqlite3_column_int64(stmt, 4)
            let wallClockMs = sqlite3_column_int64(stmt, 5)
            let gestureSessionId = sqlite3_column_type(stmt, 6) != SQLITE_NULL
                ? String(cString: sqlite3_column_text(stmt, 6)) : nil
            let typeRaw = String(cString: sqlite3_column_text(stmt, 7))
            let payloadJSON = String(cString: sqlite3_column_text(stmt, 8))

            guard let messageType = ProviderMessageType(rawValue: typeRaw) else {
                throw JournalError.sqliteError("events 表包含未知消息类型: \(typeRaw)")
            }

            // 按 type + payloadJSON 分发解码 payload
            // 不使用 ProviderPayload 的直接 Codable，因为 payload 不含 type 上下文
            let payloadDataValue = Data(payloadJSON.utf8)
            let payload = try ProviderEnvelope.dispatchPayload(type: messageType, payloadData: payloadDataValue)

            let event = ProviderEvent(
                eventId: eventId,
                producerSessionId: producerSessionId,
                producerSequence: producerSequence,
                causedByEventId: causedByEventId,
                monotonicClockMs: monotonicClockMs,
                wallClockMs: wallClockMs,
                gestureSessionId: gestureSessionId,
                operationId: operationId,
                type: messageType,
                payload: payload
            )
            events.append(event)
        }

        return events
    }

    /// 内部导出证据包 — 委托给 EvidenceBundleExporter 实现。
    private func exportEvidenceInternal(operationId: String, to url: URL) throws {
        let timelines = try queryInternal(.operation(operationId), limit: 1)
        guard let timeline = timelines.first else {
            throw JournalError.invalidArgument("操作 \(operationId) 不存在")
        }
        let exporter = EvidenceBundleExporter()
        try exporter.export(timeline: timeline, to: url)
    }

    /// 压缩已完成操作以释放空间。
    private func compactInternal() throws {
        // 删除 terminal_state 不为 NULL 的已完成操作的事件
        try checkSQLite(sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, nil), context: "BEGIN compact")

        var execOK = false
        defer {
            if !execOK {
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            }
        }

        // 删除已完成操作的事件记录
        let deleteEventsSQL = """
        DELETE FROM events WHERE operation_id IN (
            SELECT operation_id FROM operations WHERE terminal_state IS NOT NULL
        )
        """
        try checkSQLite(sqlite3_exec(db, deleteEventsSQL, nil, nil, nil), context: "DELETE completed events")

        // 删除已完成操作记录
        let deleteOpsSQL = """
        DELETE FROM operations WHERE terminal_state IS NOT NULL
        """
        try checkSQLite(sqlite3_exec(db, deleteOpsSQL, nil, nil, nil), context: "DELETE completed ops")

        try checkSQLite(sqlite3_exec(db, "COMMIT", nil, nil, nil), context: "COMMIT compact")
        execOK = true

        // WAL checkpoint 以回收空间
        try checkSQLite(sqlite3_exec(db, "PRAGMA wal_checkpoint(TRUNCATE)", nil, nil, nil), context: "WAL checkpoint")
    }

    /// 计算当前 Journal 总大小（主库 + WAL + SHM）。
    private func currentJournalSize() -> Int64 {
        let fm = FileManager.default
        let paths = [
            journalPath,
            journalPath + "-wal",
            journalPath + "-shm",
        ]
        return paths.reduce(0) { total, path in
            if fm.fileExists(atPath: path),
               let attrs = try? fm.attributesOfItem(atPath: path),
               let size = attrs[.size] as? Int64 {
                return total + size
            }
            return total
        }
    }
}

// MARK: - SQLite 绑定辅助

/// 绑定不同类型的值到 SQLite 预编译语句。
private func bindSQLite(stmt: OpaquePointer?, index: Int32, value: Any) throws {
    let rc: Int32
    if value is NSNull || value is Void? {
        rc = sqlite3_bind_null(stmt, index)
    } else if let v = value as? String {
        rc = sqlite3_bind_text(stmt, index, v, -1, SQLITE_TRANSIENT)
    } else if let v = value as? Int64 {
        rc = sqlite3_bind_int64(stmt, index, v)
    } else if let v = value as? Int32 {
        rc = sqlite3_bind_int(stmt, index, v)
    } else if let v = value as? Int {
        rc = sqlite3_bind_int64(stmt, index, Int64(v))
    } else if let v = value as? Double {
        rc = sqlite3_bind_double(stmt, index, v)
    } else {
        throw JournalError.sqliteError("不支持的类型: \(type(of: value))")
    }
    guard rc == SQLITE_OK else {
        throw JournalError.sqliteError("绑定参数 \(index): \(String(cString: sqlite3_errstr(rc)))")
    }
}

// MARK: - POSIX 错误辅助

private func checkPOSIX(_ code: Int32, context: String) throws {
    guard code == 0 else {
        throw JournalError.sqliteError("POSIX 错误 [\(context)]: errno=\(errno)")
    }
}

// MARK: - SQLITE_TRANSIENT C 回调

/// SQLITE_TRANSIENT 是 SQLite C API 中用于指示字符串拷贝的标记。
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
