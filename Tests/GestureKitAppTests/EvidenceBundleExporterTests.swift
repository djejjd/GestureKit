import Foundation
@testable import GestureKitApp
import GestureKitCore
import XCTest

// MARK: - EvidenceBundleExporter 单元测试
//
// 本文件验证证据包导出的以下行为：
// 1. 敏感 fixture 的 query/hash/email/token/targetRef/自由文本不得出现在三类导出文件中
// 2. redactionApplied 标记正确
// 3. 目录权限 0700、文件权限 0600
// 4. 已存在目录权限修正
// 5. 缺失范围按 producerSessionId 独立计算

final class EvidenceBundleExporterTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var exporter: EvidenceBundleExporter!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("EvidenceBundleExporterTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        exporter = EvidenceBundleExporter(schemaVersion: "1.0", redactionVersion: "1.0")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    // MARK: - 敏感数据不出现在导出文件中

    /// 验证导出文件不包含 query、hash、email、token、targetRef 等敏感数据。
    /// 使用 DiagnosticRedactor 配合导出时，三类文件（manifest、events、README）均不得泄漏原始信息。
    func testSensitiveContentNotInExportedFiles() throws {
        // 构造包含敏感数据的 payload
        let sensitiveURL = "https://example.com/user/a@example.com/token/123456789012?secret=abc#section"
        let context = ContextSnapshotPayload(
            contextId: "ctx-sensitive",
            pageIdentity: sensitiveURL,
            expiresAt: 1_782_200_002_000,
            targetKind: .standardLink,
            targetRef: "sensitive-opaque-ref"
        )
        let event = ProviderEvent(
            eventId: "evt-sensitive-1",
            producerSessionId: "session-001",
            producerSequence: 1,
            causedByEventId: nil,
            monotonicClockMs: 1000,
            wallClockMs: 1000,
            gestureSessionId: "gesture-001",
            operationId: "op-sensitive-1",
            type: .contextSnapshot,
            payload: .contextSnapshot(context)
        )
        let timeline = OperationTimeline(
            operationId: "op-sensitive-1",
            events: [event],
            terminalState: nil,
            startedAt: 1000,
            lastEventAt: 1000
        )

        let redactor = DiagnosticRedactor()
        let exportURL = temporaryDirectory.appendingPathComponent("sensitive-export")
        try exporter.export(timeline: timeline, to: exportURL, redactor: redactor)

        // 读取所有导出文件
        let manifestData = try Data(contentsOf: exportURL.appendingPathComponent("manifest.json"))
        let eventsData = try Data(contentsOf: exportURL.appendingPathComponent("events.json"))
        let readmeData = try Data(contentsOf: exportURL.appendingPathComponent("README.txt"))

        let manifestStr = String(data: manifestData, encoding: .utf8) ?? ""
        let eventsStr = String(data: eventsData, encoding: .utf8) ?? ""
        let readmeStr = String(data: readmeData, encoding: .utf8) ?? ""

        // 禁止的敏感内容
        let forbidden = [
            "secret=abc",      // query
            "#section",         // hash
            "a@example.com",   // email
            "123456789012",    // token
            "sensitive-opaque-ref", // targetRef
        ]
        for item in forbidden {
            XCTAssertFalse(manifestStr.contains(item),
                           "manifest.json 不得包含敏感内容 \"\(item)\"")
            XCTAssertFalse(eventsStr.contains(item),
                           "events.json 不得包含敏感内容 \"\(item)\"")
            XCTAssertFalse(readmeStr.contains(item),
                           "README.txt 不得包含敏感内容 \"\(item)\"")
        }

        // manifest 中 redactionApplied 为 true
        XCTAssertTrue(manifestStr.contains("\"redactionApplied\":true") ||
                      manifestStr.contains("\"redactionApplied\" : true"),
                      "redactionApplied 应为 true（已脱敏）")
    }

    // MARK: - redactionApplied 标记

    /// 导出无论调用者是否提供 redactor 都必须执行最后一道脱敏。
    func testRedactionAppliedFlagWhenRedactorProvided() throws {
        let event = makeTrivialEvent("op-redaction-flag-1")
        let timeline = OperationTimeline(
            operationId: "op-redaction-flag-1",
            events: [event],
            terminalState: nil,
            startedAt: 1000,
            lastEventAt: 1000
        )

        // 不提供 redactor 时仍由 exporter 创建脱敏器
        let exportURL1 = temporaryDirectory.appendingPathComponent("no-redactor")
        try exporter.export(timeline: timeline, to: exportURL1)
        let manifest1 = try String(contentsOf: exportURL1.appendingPathComponent("manifest.json"), encoding: .utf8)
        XCTAssertTrue(manifest1.contains("\"redactionApplied\":true") ||
                      manifest1.contains("\"redactionApplied\" : true"))

        // 提供 redactor
        let exportURL2 = temporaryDirectory.appendingPathComponent("with-redactor")
        try exporter.export(timeline: timeline, to: exportURL2, redactor: DiagnosticRedactor())
        let manifest2 = try String(contentsOf: exportURL2.appendingPathComponent("manifest.json"), encoding: .utf8)
        XCTAssertTrue(manifest2.contains("\"redactionApplied\":true") ||
                      manifest2.contains("\"redactionApplied\" : true"))
    }

    // MARK: - 文件权限

    /// 验证导出目录权限为 0700。
    func testExportDirectoryPermissions() throws {
        let event = makeTrivialEvent("op-perm-1")
        let timeline = OperationTimeline(
            operationId: "op-perm-1",
            events: [event],
            terminalState: nil,
            startedAt: 1000,
            lastEventAt: 1000
        )
        let exportURL = temporaryDirectory.appendingPathComponent("perm-test")
        try exporter.export(timeline: timeline, to: exportURL)

        let attrs = try FileManager.default.attributesOfItem(atPath: exportURL.path)
        let perms = (attrs[.posixPermissions] as? Int) ?? 0
        // 0700 = 448
        XCTAssertEqual(perms & 0o777, 0o700,
                       "导出目录权限应为 0700，实际: \(String(perms, radix: 8))")
    }

    /// 验证导出文件权限为 0600。
    func testExportFilePermissions() throws {
        let event = makeTrivialEvent("op-fileperm-1")
        let timeline = OperationTimeline(
            operationId: "op-fileperm-1",
            events: [event],
            terminalState: nil,
            startedAt: 1000,
            lastEventAt: 1000
        )
        let exportURL = temporaryDirectory.appendingPathComponent("file-perm-test")
        try exporter.export(timeline: timeline, to: exportURL)

        let files = ["manifest.json", "events.json", "README.txt"]
        for file in files {
            let fileURL = exportURL.appendingPathComponent(file)
            let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            let perms = (attrs[.posixPermissions] as? Int) ?? 0
            XCTAssertEqual(perms & 0o777, 0o600,
                           "\(file) 权限应为 0600，实际: \(String(perms, radix: 8))")
        }
    }

    /// 验证已存在目录的权限被修正为 0700。
    func testExistingDirectoryPermissionsAreFixed() throws {
        let event = makeTrivialEvent("op-existing-1")
        let timeline = OperationTimeline(
            operationId: "op-existing-1",
            events: [event],
            terminalState: nil,
            startedAt: 1000,
            lastEventAt: 1000
        )

        // 先创建目录并设置不安全的权限
        let exportURL = temporaryDirectory.appendingPathComponent("existing-perm")
        try FileManager.default.createDirectory(at: exportURL, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o777])

        // 导出应修正为 0700
        try exporter.export(timeline: timeline, to: exportURL)

        let attrs = try FileManager.default.attributesOfItem(atPath: exportURL.path)
        let perms = (attrs[.posixPermissions] as? Int) ?? 0
        XCTAssertEqual(perms & 0o777, 0o700,
                       "已存在目录的权限应被修正为 0700，实际: \(String(perms, radix: 8))")
    }

    // MARK: - 缺失范围

    /// 验证 producerSequences 中的缺口被正确计算。
    func testMissingRangesInManifest() throws {
        // 构造两个不同 producer 的事件，各自有缺口
        let eventA1 = makeEventForProducer("op-gap", session: "producer-A", sequence: 1)
        let eventA3 = makeEventForProducer("op-gap", session: "producer-A", sequence: 3) // 缺 2
        let eventB5 = makeEventForProducer("op-gap", session: "producer-B", sequence: 5)
        let eventB8 = makeEventForProducer("op-gap", session: "producer-B", sequence: 8) // 缺 6,7

        let timeline = OperationTimeline(
            operationId: "op-gap",
            events: [eventA1, eventA3, eventB5, eventB8],
            terminalState: nil,
            startedAt: 1000,
            lastEventAt: 8000
        )

        let exportURL = temporaryDirectory.appendingPathComponent("gap-test")
        try exporter.export(timeline: timeline, to: exportURL)

        let manifestData = try Data(contentsOf: exportURL.appendingPathComponent("manifest.json"))
        let manifest = try JSONDecoder().decode(EvidenceManifest.self, from: manifestData)
        let ranges = try XCTUnwrap(manifest.missingRanges)
        XCTAssertEqual(ranges.count, 2, "不同 producer 的序号不得混算为额外缺口")
    }

    /// 验证只有 1 个或 0 个事件时不产生 missingRanges。
    func testNoMissingRangesForSingleEvent() throws {
        let event = makeTrivialEvent("op-single-1")
        let timeline = OperationTimeline(
            operationId: "op-single-1",
            events: [event],
            terminalState: nil,
            startedAt: 1000,
            lastEventAt: 1000
        )
        let exportURL = temporaryDirectory.appendingPathComponent("no-gap")
        try exporter.export(timeline: timeline, to: exportURL)

        let manifestData = try Data(contentsOf: exportURL.appendingPathComponent("manifest.json"))
        let manifestStr = String(data: manifestData, encoding: .utf8) ?? ""
        // 单事件导出时 missingRanges 不应出现（Swift 默认省略 nil 可选值）
        // 或显示为 null/空
        let hasMissingRangesAsNull = manifestStr.contains("\"missingRanges\":null") || manifestStr.contains("\"missingRanges\" : null")
        let hasNoMissingRanges = !manifestStr.contains("\"missingRanges\"") || hasMissingRangesAsNull
        XCTAssertTrue(hasNoMissingRanges,
                      "单事件导出时 missingRanges 应为 null 或不存在")
    }

    // MARK: - 辅助方法

    private func makeTrivialEvent(_ operationId: String) -> ProviderEvent {
        let action = ActionDescriptor(
            actionId: .browserPageReload,
            contextId: "ctx-test",
            targetRef: nil,
            parameters: [:],
            deadline: 2000
        )
        return ProviderEvent(
            eventId: "evt-\(operationId)",
            producerSessionId: "session-test",
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

    private func makeEventForProducer(_ operationId: String, session: String, sequence: Int64) -> ProviderEvent {
        let action = ActionDescriptor(
            actionId: .browserPageReload,
            contextId: "ctx-\(session)",
            targetRef: nil,
            parameters: [:],
            deadline: 9999
        )
        return ProviderEvent(
            eventId: "evt-\(session)-\(sequence)",
            producerSessionId: session,
            producerSequence: sequence,
            causedByEventId: nil,
            monotonicClockMs: Int64(sequence * 1000),
            wallClockMs: Int64(sequence * 1000),
            gestureSessionId: "gesture-test",
            operationId: operationId,
            type: .actionRequest,
            payload: .actionRequest(action)
        )
    }
}
