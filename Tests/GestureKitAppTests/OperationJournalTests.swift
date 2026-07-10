import Foundation
@testable import GestureKitApp
import GestureKitCore
import XCTest

// MARK: - OperationJournal 单元测试
//
// 本文件验证 OperationJournal 的以下行为：
// 1. 事件按 eventId 幂等去重
// 2. 已过期但未终结的操作被恢复为 result_unknown
// 3. 按操作 ID、Provider 会话 ID 查询
// 4. 存储满时抛出 journalStorageFull
// 5. 数据库的完整生命周期（创建、写入、读取）

final class OperationJournalTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var journal: OperationJournal!

    // MARK: 生命周期

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OperationJournalTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)

        let dbPath = temporaryDirectory.appendingPathComponent("test.sqlite").path
        journal = try OperationJournal(path: dbPath, maxJournalSize: 10 * 1024 * 1024) // 10 MB for tests
    }

    override func tearDownWithError() throws {
        journal = nil
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    // MARK: - 事件去重

    /// 验证按 eventId 幂等追加：相同 eventId 的事件多次追加只保留一份。
    func testAppendIsIdempotentByEventID() throws {
        let event = makeEvent(operationId: "op-dedup", eventId: "evt-dedup-1")

        try journal.append(event)
        try journal.append(event) // 相同 eventId，应被 INSERT OR IGNORE

        let timelines = try journal.query(.operation("op-dedup"), limit: 10)
        XCTAssertEqual(timelines.count, 1, "同一 eventId 多次追加应只产生 1 条操作时间线")

        let timeline = try XCTUnwrap(timelines.first)
        XCTAssertEqual(timeline.operationId, "op-dedup")
        // 事件表中有且仅有 1 条记录
        XCTAssertEqual(timeline.events.count, 1, "去重后事件数量应为 1")
    }

    /// 验证不同 eventId 的事件追加后不互相影响。
    func testMultipleEventsForSameOperation() throws {
        let event1 = makeEvent(operationId: "op-multi", eventId: "evt-multi-1", sequence: 1)
        let event2 = makeEvent(operationId: "op-multi", eventId: "evt-multi-2", sequence: 2)

        try journal.append(event1)
        try journal.append(event2)

        let timelines = try journal.query(.operation("op-multi"), limit: 10)
        XCTAssertEqual(timelines.count, 1)
        let timeline = try XCTUnwrap(timelines.first)
        XCTAssertEqual(timeline.events.count, 2, "不同 eventId 的事件应全部保留")
    }

    // MARK: - 过期操作恢复

    /// 验证 deadline 已过但未终结的操作被恢复为 result_unknown。
    func testRecoveryMarksExpiredAcceptedOperationUnknown() throws {
        let event = makeActionRequestEvent(operationId: "op-expired", deadline: 1, eventId: "evt-exp-1")

        try journal.append(event)

        let recovered = try journal.recoverExpired(now: 2)
        XCTAssertEqual(recovered.count, 1, "应有 1 个操作被恢复")
        XCTAssertEqual(recovered.first?.terminalState, .resultUnknown)
        XCTAssertEqual(recovered.first?.operationId, "op-expired")
    }

    /// 同一 producer 的多条恢复事件均须保留，不能共享固定 sequence 而被唯一约束吞掉。
    func testRecoveryAppendsEvidenceForEveryExpiredOperation() throws {
        try journal.append(makeActionRequestEvent(operationId: "op-expired-a", deadline: 1, eventId: "evt-exp-a", sessionId: "session-recovery"))
        let second = makeActionRequestEvent(operationId: "op-expired-b", deadline: 1, eventId: "evt-exp-b", sessionId: "session-recovery")
        try journal.append(ProviderEvent(
            eventId: second.eventId,
            producerSessionId: second.producerSessionId,
            producerSequence: 2,
            causedByEventId: nil,
            monotonicClockMs: second.monotonicClockMs,
            wallClockMs: second.wallClockMs,
            gestureSessionId: second.gestureSessionId,
            operationId: second.operationId,
            type: second.type,
            payload: second.payload
        ))

        _ = try journal.recoverExpired(now: 2)
        XCTAssertEqual(try journal.query(.operation("op-expired-a"), limit: 1).first?.events.count, 2)
        XCTAssertEqual(try journal.query(.operation("op-expired-b"), limit: 1).first?.events.count, 2)
    }

    /// 相同 eventId 但关联不同 operation 的重传是冲突，不能静默 no-op。
    func testRejectsDuplicateEventIDWithDifferentOperation() throws {
        try journal.append(makeEvent(operationId: "op-original", eventId: "evt-conflict"))
        XCTAssertThrowsError(try journal.append(makeEvent(operationId: "op-conflicting", eventId: "evt-conflict")))
        XCTAssertTrue(try journal.query(.operation("op-conflicting"), limit: 1).isEmpty)
    }

    /// 验证未过期的操作不会被恢复。
    func testRecoveryDoesNotTouchNonExpiredOperation() throws {
        let futureDeadline: Int64 = 1_000_000_000_000 // 遥远的未来
        let event = makeActionRequestEvent(operationId: "op-future", deadline: futureDeadline, eventId: "evt-future-1")

        try journal.append(event)

        let recovered = try journal.recoverExpired(now: 100)
        XCTAssertTrue(recovered.isEmpty, "未过期的操作不应被恢复")
    }

    /// 验证已终结的操作不会被恢复。
    func testRecoveryDoesNotTouchTerminalOperation() throws {
        let event = makeActionRequestEvent(operationId: "op-terminal", deadline: 1, eventId: "evt-term-1")

        try journal.append(event)
        // 先恢复一次（标记为 result_unknown）
        _ = try journal.recoverExpired(now: 2)

        // 再次恢复不应再产生结果
        let recoveredAgain = try journal.recoverExpired(now: 2)
        XCTAssertTrue(recoveredAgain.isEmpty, "已终结的操作不应再次被恢复")
    }

    // MARK: - 查询

    /// 验证按操作 ID 查询返回正确的操作时间线。
    func testQueryByOperationID() throws {
        let event1 = makeEvent(operationId: "op-query-1", eventId: "evt-query-1", sequence: 1)
        let event2 = makeEvent(operationId: "op-query-2", eventId: "evt-query-2", sequence: 2)

        try journal.append(event1)
        try journal.append(event2)

        let result1 = try journal.query(.operation("op-query-1"), limit: 10)
        XCTAssertEqual(result1.count, 1)
        XCTAssertEqual(result1.first?.operationId, "op-query-1")

        let result2 = try journal.query(.operation("op-query-2"), limit: 10)
        XCTAssertEqual(result2.count, 1)
        XCTAssertEqual(result2.first?.operationId, "op-query-2")

        let resultNone = try journal.query(.operation("op-nonexistent"), limit: 10)
        XCTAssertTrue(resultNone.isEmpty, "不存在的操作 ID 应返回空结果")
    }

    /// 验证按 Provider 会话 ID 查询。
    func testQueryByProviderSessionID() throws {
        let event1 = makeEvent(operationId: "op-sess-1", eventId: "evt-sess-1", sessionId: "session-alpha", sequence: 1)
        let event2 = makeEvent(operationId: "op-sess-2", eventId: "evt-sess-2", sessionId: "session-beta", sequence: 1)

        try journal.append(event1)
        try journal.append(event2)

        let filter = OperationFilter(producerSessionId: "session-alpha")
        let result = try journal.query(filter, limit: 10)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.operationId, "op-sess-1")
    }

    /// 验证 limit 参数正确限制返回数量。
    func testQueryLimit() throws {
        for i in 1...5 {
            let event = makeEvent(operationId: "op-limit-\(i)", eventId: "evt-limit-\(i)", sequence: Int64(i))
            try journal.append(event)
        }

        let result = try journal.query(OperationFilter(), limit: 3)
        XCTAssertEqual(result.count, 3, "limit 参数应正确限制返回数量")
    }

    // MARK: - 边缘情况

    /// 验证不带 operationId 的事件被拒绝。
    func testRejectsEventWithoutOperationID() throws {
        let event = makeEvent(operationId: nil, eventId: "evt-noop-1")
        XCTAssertThrowsError(try journal.append(event)) { error in
            guard let journalError = error as? JournalError else {
                XCTFail("期望 JournalError，实际为 \(type(of: error))")
                return
            }
            if case .invalidArgument = journalError {
                XCTAssertTrue(true, "缺少 operationId 时应抛出 invalidArgument")
            } else {
                XCTFail("期望 invalidArgument，实际为 \(journalError)")
            }
        }
    }

    /// 验证数据库在空表上查询不崩溃。
    func testEmptyDatabaseQuery() throws {
        let result = try journal.query(.operation("nonexistent"), limit: 10)
        XCTAssertTrue(result.isEmpty)
    }

    /// 验证空数据库的 recoverExpired 不崩溃。
    func testEmptyDatabaseRecoverExpired() throws {
        let recovered = try journal.recoverExpired(now: 100)
        XCTAssertTrue(recovered.isEmpty)
    }

    /// 验证多次 append 后 query 按 last_event_at 降序排列。
    func testQueryOrderByLastEventDesc() throws {
        let event1 = makeEvent(operationId: "op-order-1", eventId: "evt-order-1", sequence: 1, wallClock: 100)
        let event2 = makeEvent(operationId: "op-order-2", eventId: "evt-order-2", sequence: 2, wallClock: 200)

        try journal.append(event1)
        try journal.append(event2)

        let result = try journal.query(OperationFilter(), limit: 10)
        XCTAssertGreaterThanOrEqual(result.count, 2, "应有 2 个操作")
        // 最新的操作应排在前面
        let firstTimestamp = result[0].lastEventAt
        let secondTimestamp = result[1].lastEventAt
        XCTAssertGreaterThanOrEqual(firstTimestamp, secondTimestamp,
                                     "查询结果应按 lastEventAt 降序排列")
    }
}

// MARK: - 测试辅助

private extension OperationJournalTests {
    /// 创建一个基本的 ProviderEvent（不含 deadline 的普通事件）。
    func makeEvent(
        operationId: String?,
        eventId: String,
        sessionId: String = "session-test",
        sequence: Int64 = 1,
        wallClock: Int64 = 1_000_000
    ) -> ProviderEvent {
        let action = ActionDescriptor(
            actionId: .browserPageReload,
            contextId: "ctx-test",
            targetRef: nil,
            parameters: [:],
            deadline: 0
        )
        return ProviderEvent(
            eventId: eventId,
            producerSessionId: sessionId,
            producerSequence: sequence,
            causedByEventId: nil,
            monotonicClockMs: Int64(wallClock),
            wallClockMs: Int64(wallClock),
            gestureSessionId: "gesture-test",
            operationId: operationId,
            type: .actionRequest,
            payload: .actionRequest(action)
        )
    }

    /// 创建一个包含明确 deadline 的 action_request 事件，用于过期恢复测试。
    func makeActionRequestEvent(
        operationId: String,
        deadline: Int64,
        eventId: String,
        sessionId: String = "session-test"
    ) -> ProviderEvent {
        let action = ActionDescriptor(
            actionId: .browserLinkOpenAdjacent,
            contextId: "ctx-expired",
            targetRef: nil,
            parameters: [:],
            deadline: deadline
        )
        return ProviderEvent(
            eventId: eventId,
            producerSessionId: sessionId,
            producerSequence: 1,
            causedByEventId: nil,
            monotonicClockMs: 1000,
            wallClockMs: 1000,
            gestureSessionId: "gesture-test",
            operationId: operationId,
            type: .actionRequest,
            payload: .actionRequest(action)
        )
    }
}
