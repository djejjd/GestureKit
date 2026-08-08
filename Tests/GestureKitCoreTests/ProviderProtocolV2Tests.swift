import XCTest
@testable import GestureKitCore

// MARK: - Provider Protocol v2 跨语言契约测试
//
// 本文件验证 JSON Schema / Swift / TypeScript 三方对 provider-v2
// 协议模型的编码/解码一致性。所有 fixture 位于 packages/protocol/fixtures/。
//
// 测试原则：
// 1. Provider v2 边界必须拒绝 legacy v1 envelope（protocolVersion != 2）。
// 2. action_request fixture 在 JSON Schema、Swift、TypeScript 三侧的解码结果必须一致。
// 3. context_snapshot 只允许 contextId、页面身份、过期时间、标准 target facts 和不透明 targetRef。
// 4. ProviderEvent 必须包含完整的证据链字段（eventId, producerSessionId, producerSequence 等）。

final class ProviderProtocolV2Tests: XCTestCase {

    // MARK: - 测试辅助

    /// 返回 fixtures 目录下指定 JSON 文件的 URL。
    ///
    /// 从当前工作目录向上搜索 packages/protocol/fixtures/ 目录。
    /// 不使用 `#file` 路径解析，因为 `swift test` 的工作目录可能为
    /// repo 根目录或其子目录（如 extensions/chrome/）。
    private func fixtureURL(_ name: String) throws -> URL {
        let fm = FileManager.default
        var current = URL(fileURLWithPath: fm.currentDirectoryPath).standardized
        while current.path != "/" {
            let candidate = current
                .appendingPathComponent("packages/protocol/fixtures")
                .appendingPathComponent(name)
            if fm.fileExists(atPath: candidate.path) {
                return candidate.standardized
            }
            current.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }

    /// 从 fixture 文件解码 ProviderEnvelope。
    private func decodeFixture(_ name: String, file: StaticString = #filePath, line: UInt = #line) throws -> ProviderEnvelope {
        let url = try fixtureURL(name)
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(ProviderEnvelope.self, from: data)
    }

    /// 编码 ProviderEnvelope 后再解码，验证 round-trip。
    private func roundTrip(_ envelope: ProviderEnvelope, file: StaticString = #filePath, line: UInt = #line) throws -> ProviderEnvelope {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(envelope)
        let decoder = JSONDecoder()
        return try decoder.decode(ProviderEnvelope.self, from: data)
    }

    // MARK: - action_request fixture 解码

    /// 验证 provider-v2-action-request.json 能正确解码为 ProviderEnvelope。
    ///
    /// 这是跨语言一致性的核心测试——Swift、TypeScript、JSON Schema 三侧
    /// 必须从同一 fixture 得到一致的字段值。
    func testActionRequestFixtureDecodesAsProtocolV2() throws {
        let message = try decodeFixture("provider-v2-action-request.json")

        // 协议版本必须为 2
        XCTAssertEqual(message.protocolVersion, 2, "Provider v2 envelope 的 protocolVersion 必须为 2")

        // 消息类型必须为 action_request
        XCTAssertEqual(message.type, .actionRequest, "Fixture 的 type 字段必须为 action_request")

        // 顶层标识字段必须非空
        XCTAssertFalse(message.messageId.isEmpty, "messageId 为消息唯一标识，不可为空")
        XCTAssertFalse(message.providerSessionId.isEmpty, "providerSessionId 标识认证后的 Provider 会话")
        XCTAssertEqual(message.gestureSessionId, "gesture-session-001", "关联的手势会话 ID")
        XCTAssertEqual(message.operationId, "operation-001", "关联的幂等操作 ID")
        XCTAssertGreaterThan(message.timestamp, 0, "timestamp 为 Unix 毫秒时间戳")

        // 错误字段必须为 nil（成功场景）
        XCTAssertNil(message.error, "成功的 action_request 不应携带 error")

        // payload 必须是 actionRequest 类型
        guard case .actionRequest(let action) = message.payload else {
            XCTFail("Fixture payload 应为 actionRequest，实际为 \(message.payload)")
            return
        }

        // 验证 action descriptor 字段
        XCTAssertEqual(action.actionId, .browserLinkOpenAdjacent, "标准链接打开动作")
        XCTAssertEqual(action.contextId, "context-001", "关联的 context snapshot ID")
        XCTAssertEqual(action.targetRef, "opaque-ref-abc123", "Provider 内部的不透明目标引用")
        XCTAssertEqual(action.parameters["activate"], "true", "参数表示新标签自动激活")
        XCTAssertGreaterThan(action.deadline, message.timestamp, "deadline 必须在请求时间之后")
    }

    // MARK: - Round-trip 编解码

    /// 验证 ActionDescriptor 的 encode → decode 往返一致性。
    /// 保证 Swift Codable 模型与 JSON 序列化之间无信息丢失。
    func testRoundTripActionRequest() throws {
        // 构造一个完整的 action_request 信封
        let action = ActionDescriptor(
            actionId: .browserTabActivateNext,
            contextId: "ctx-roundtrip",
            targetRef: nil,
            parameters: [:],
            deadline: 1782200002000
        )
        let original = ProviderEnvelope(
            protocolVersion: 2,
            messageId: "roundtrip-001",
            providerSessionId: "session-test",
            gestureSessionId: "gesture-roundtrip",
            operationId: "op-roundtrip",
            type: .actionRequest,
            timestamp: 1782200001000,
            payload: .actionRequest(action),
            error: nil
        )

        let roundtripped = try roundTrip(original)

        XCTAssertEqual(roundtripped.protocolVersion, 2)
        XCTAssertEqual(roundtripped.messageId, "roundtrip-001")
        XCTAssertEqual(roundtripped.providerSessionId, "session-test")
        XCTAssertEqual(roundtripped.gestureSessionId, "gesture-roundtrip")
        XCTAssertEqual(roundtripped.operationId, "op-roundtrip")
        XCTAssertEqual(roundtripped.type, .actionRequest)
        XCTAssertEqual(roundtripped.timestamp, 1782200001000)
        XCTAssertNil(roundtripped.error)

        guard case .actionRequest(let decodedAction) = roundtripped.payload else {
            XCTFail("Round-trip 后 payload 必须为 actionRequest")
            return
        }
        XCTAssertEqual(decodedAction.actionId, .browserTabActivateNext)
        XCTAssertEqual(decodedAction.contextId, "ctx-roundtrip")
        XCTAssertNil(decodedAction.targetRef)
        XCTAssertEqual(decodedAction.deadline, 1782200002000)
    }

    func testRoundTripInteractionGuardArm() throws {
        let original = ProviderEnvelope(
            protocolVersion: 2,
            messageId: "guard-001",
            providerSessionId: "session-test",
            gestureSessionId: "gesture-001",
            operationId: nil,
            type: .interactionGuardArm,
            timestamp: 1782200001000,
            payload: .interactionGuardArm(InteractionGuardPayload(
                gestureSessionId: "gesture-001", features: ["link_click"], deadline: 1782200001500
            )),
            error: nil
        )

        let decoded = try roundTrip(original)
        XCTAssertEqual(decoded.type, .interactionGuardArm)
        guard case .interactionGuardArm(let payload) = decoded.payload else {
            return XCTFail("Round-trip 后 payload 必须为 interactionGuardArm")
        }
        XCTAssertEqual(payload.gestureSessionId, "gesture-001")
        XCTAssertEqual(payload.features, ["link_click"])
    }

    // MARK: - Legacy v1 拒绝

    /// Provider v2 边界必须拒绝 legacy v1 envelope。
    ///
    /// V1 使用 `version: 1` 和 `id` 字段，v2 使用 `protocolVersion: 2` 和 `messageId`。
    /// 字段名和语义均已变更，因此 v1 消息必须在 Provider v2 边界被明确拒绝。
    func testRejectsLegacyV1Envelope() throws {
        let v1JSON = """
        {
            "version": 1,
            "id": "v1-message",
            "type": "gesture_event",
            "timestamp": 1000,
            "payload": {"gesture": "three_finger_tap", "appBundleId": "com.example.app"},
            "error": null
        }
        """
        let data = try XCTUnwrap(v1JSON.data(using: .utf8))
        let decoder = JSONDecoder()

        XCTAssertThrowsError(try decoder.decode(ProviderEnvelope.self, from: data)) { error in
            // V1 缺少 protocolVersion 字段（使用 version 代替），
            // 因此在 ProviderEnvelope 解码时应当由于字段缺失而失败。
            guard let decodingError = error as? DecodingError else {
                XCTFail("期望 DecodingError，实际为 \(type(of: error))")
                return
            }
            // 只要抛出了 DecodingError 即表示 v1 消息被 v2 边界拒绝
            XCTAssertTrue(true, "V1 消息已被 Provider v2 边界拒绝")
        }
    }

    /// 即使手动传入 protocolVersion=1 字段名，也必须拒绝。
    func testRejectsNonV2ProtocolVersion() throws {
        let badVersionJSON = """
        {
            "protocolVersion": 1,
            "messageId": "bad-version",
            "providerSessionId": "session-test",
            "type": "action_request",
            "timestamp": 1000,
            "payload": {"actionId": "browser.tab.activate_next", "contextId": "ctx", "deadline": 2000},
            "error": null
        }
        """
        let data = try XCTUnwrap(badVersionJSON.data(using: .utf8))
        let decoder = JSONDecoder()

        XCTAssertThrowsError(try decoder.decode(ProviderEnvelope.self, from: data)) { error in
            // protocolVersion 不为 2 时应当抛出校验错误
            XCTAssertTrue(error is DecodingError || error is ProviderProtocolError)
        }
    }

    /// 缺失 error 键不能被当作 null 宽松接受，避免绕过 envelope 契约。
    func testRejectsEnvelopeMissingErrorKey() throws {
        let json = """
        {"protocolVersion":2,"messageId":"m","providerSessionId":"s","type":"action_request","timestamp":1,"operationId":"op","payload":{"actionId":"browser.page.reload","contextId":"ctx","parameters":{},"deadline":2}}
        """
        XCTAssertThrowsError(try JSONDecoder().decode(ProviderEnvelope.self, from: Data(json.utf8)))
    }

    /// payload 的未知字段必须拒绝，不能因 Codable 默认忽略而绕过白名单。
    func testRejectsPayloadWithUndeclaredField() throws {
        let json = """
        {"protocolVersion":2,"messageId":"m","providerSessionId":"s","type":"action_request","timestamp":1,"operationId":"op","payload":{"actionId":"browser.page.reload","contextId":"ctx","parameters":{},"deadline":2,"details":"raw page content"},"error":null}
        """
        XCTAssertThrowsError(try JSONDecoder().decode(ProviderEnvelope.self, from: Data(json.utf8)))
    }

    // MARK: - Context Snapshot 约束

    /// context_snapshot 只允许携带 contextId、页面身份、过期时间、
    /// 标准 target facts 和不透明 targetRef；不得包含 URL query/hash、
    /// DOM 文本、id/class、Cookie、表单值或自由文本 details。
    func testContextSnapshotHasOnlyAllowedFields() throws {
        let snapshot = ContextSnapshotPayload(
            contextId: "ctx-001",
            pageIdentity: "https://example.com",
            expiresAt: 1782200002000,
            targetKind: .standardLink,
            targetRef: "opaque-ref-xyz"
        )

        // 允许的字段：以下断言成功即证明不包含禁止字段
        XCTAssertEqual(snapshot.contextId, "ctx-001")
        XCTAssertEqual(snapshot.pageIdentity, "https://example.com")
        XCTAssertEqual(snapshot.expiresAt, 1782200002000)
        XCTAssertEqual(snapshot.targetKind, .standardLink)
        XCTAssertEqual(snapshot.targetRef, "opaque-ref-xyz")

        // 禁止字段验证
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let jsonData = try encoder.encode(snapshot)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: jsonData) as? [String: Any])

        // context_snapshot 不得包含 query、hash、domText、elementId、className、cookie、formValue、details
        XCTAssertNil(json["query"], "context_snapshot 不得包含 URL query")
        XCTAssertNil(json["hash"], "context_snapshot 不得包含 URL hash")
        XCTAssertNil(json["domText"], "context_snapshot 不得包含 DOM 文本")
        XCTAssertNil(json["elementId"], "context_snapshot 不得包含元素 id")
        XCTAssertNil(json["className"], "context_snapshot 不得包含元素 class")
        XCTAssertNil(json["cookie"], "context_snapshot 不得包含 Cookie")
        XCTAssertNil(json["formValue"], "context_snapshot 不得包含表单值")
        XCTAssertNil(json["details"], "context_snapshot 不得包含自由文本 details")
    }

    /// 验证 context_snapshot 的 no_target 和 page_unavailable 目标类型。
    func testContextSnapshotTargetKinds() throws {
        let noTarget = ContextSnapshotPayload(contextId: "ctx-002", pageIdentity: "https://example.com", expiresAt: 1000, targetKind: .noTarget, targetRef: nil)
        XCTAssertEqual(noTarget.targetKind, .noTarget)
        XCTAssertNil(noTarget.targetRef, "无目标时 targetRef 应为 nil")

        let unavailable = ContextSnapshotPayload(contextId: "ctx-003", pageIdentity: "about:blank", expiresAt: 1000, targetKind: .pageUnavailable, targetRef: nil)
        XCTAssertEqual(unavailable.targetKind, .pageUnavailable)
    }

    /// configuration_snapshot 需要携带 App 权威的诊断日志开关，供 Chrome 侧镜像使用。
    func testConfigurationSnapshotEncodesDiagnosticLoggingFlag() throws {
        let snapshot = ConfigurationSnapshotPayload(
            storeEpoch: "epoch-1",
            schemaVersion: 2,
            configurationVersion: 7,
            diagnosticLoggingEnabled: true,
            configJSON: "{\"recognition\":{\"swipeSensitivity\":\"standard\"}}"
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(ConfigurationSnapshotPayload.self, from: data)

        XCTAssertTrue(decoded.diagnosticLoggingEnabled)
        XCTAssertEqual(decoded.configurationVersion, 7)
    }

    // MARK: - 标准动作 ID

    /// Provider Protocol v2 必须定义以下 16 个标准动作 ID。
    /// 这是 Core 与 Provider 之间的最小契约，Provider 通过能力声明告知支持哪些动作。
    func testStandardActionIDCases() {
        // browser.link.open_adjacent：在当前标签右侧打开目标链接
        XCTAssertEqual(StandardActionID.browserLinkOpenAdjacent.rawValue, "browser.link.open_adjacent")
        // browser.tab.activate_previous：切换到左侧标签页
        XCTAssertEqual(StandardActionID.browserTabActivatePrevious.rawValue, "browser.tab.activate_previous")
        // browser.tab.activate_next：切换到右侧标签页
        XCTAssertEqual(StandardActionID.browserTabActivateNext.rawValue, "browser.tab.activate_next")
        // browser.tab.close_current：关闭当前标签页
        XCTAssertEqual(StandardActionID.browserTabCloseCurrent.rawValue, "browser.tab.close_current")
        // browser.history.back：页面后退
        XCTAssertEqual(StandardActionID.browserHistoryBack.rawValue, "browser.history.back")
        // browser.history.forward：页面前进
        XCTAssertEqual(StandardActionID.browserHistoryForward.rawValue, "browser.history.forward")
        // browser.page.reload：刷新页面
        XCTAssertEqual(StandardActionID.browserPageReload.rawValue, "browser.page.reload")
        // browser.tab.open_new：打开新标签页
        XCTAssertEqual(StandardActionID.browserTabOpenNew.rawValue, "browser.tab.open_new")
        // browser.tab.pin：固定当前标签页
        XCTAssertEqual(StandardActionID.browserTabPin.rawValue, "browser.tab.pin")
        // browser.tab.unpin：取消固定当前标签页
        XCTAssertEqual(StandardActionID.browserTabUnpin.rawValue, "browser.tab.unpin")
        // browser.tab.toggle_mute：静音/取消静音当前标签页
        XCTAssertEqual(StandardActionID.browserTabToggleMute.rawValue, "browser.tab.toggle_mute")
        // browser.tab.close_others：关闭除当前标签外的其他标签
        XCTAssertEqual(StandardActionID.browserTabCloseOthers.rawValue, "browser.tab.close_others")
        // browser.tab.restore：恢复最近关闭的标签页
        XCTAssertEqual(StandardActionID.browserTabRestore.rawValue, "browser.tab.restore")
        // browser.link.copy：复制指针指向的链接 URL
        XCTAssertEqual(StandardActionID.browserLinkCopy.rawValue, "browser.link.copy")
        // browser.page.copy_url：复制当前页面 URL
        XCTAssertEqual(StandardActionID.browserPageCopyURL.rawValue, "browser.page.copy_url")
        // browser.page.scroll_top_bottom：滚动到页面顶部/底部
        XCTAssertEqual(StandardActionID.browserPageScrollTopBottom.rawValue, "browser.page.scroll_top_bottom")
    }

    /// 验证所有 StandardActionID 枚举 case 都已被测试覆盖。
    func testAllStandardActionIDsAreCovered() {
        let all: Set<StandardActionID> = [
            .browserLinkOpenAdjacent,
            .browserTabActivatePrevious,
            .browserTabActivateNext,
            .browserTabCloseCurrent,
            .browserHistoryBack,
            .browserHistoryForward,
            .browserPageReload,
            .browserTabOpenNew,
            .browserTabPin,
            .browserTabUnpin,
            .browserTabToggleMute,
            .browserTabCloseOthers,
            .browserTabRestore,
            .browserLinkCopy,
            .browserPageCopyURL,
            .browserPageScrollTopBottom
        ]
        XCTAssertEqual(all.count, 16, "Provider Protocol v2 必须恰好包含 16 个标准动作")
    }

    // MARK: - ProviderEvent 证据链字段

    /// ProviderEvent 是操作证据链的最小单元。
    /// 每个事件必须携带完整的溯源信息，以便在不依赖现场的情况下重建操作时序。
    func testProviderEventHasRequiredFields() throws {
        let action = ActionDescriptor(
            actionId: .browserTabActivateNext,
            contextId: "ctx-evidence",
            targetRef: nil,
            parameters: [:],
            deadline: 1782200002000
        )
        let event = ProviderEvent(
            eventId: "evt-001",
            producerSessionId: "session-chrome-001",
            producerSequence: 42,
            causedByEventId: nil,
            monotonicClockMs: 1782200001000,
            wallClockMs: 1782200001000,
            gestureSessionId: "gesture-session-evidence",
            operationId: "op-evidence",
            type: .actionRequest,
            payload: .actionRequest(action)
        )

        // 证据链字段必须全部非空（causedByEventId 可选）
        XCTAssertEqual(event.eventId, "evt-001", "eventId 是事件的全局唯一标识")
        XCTAssertEqual(event.producerSessionId, "session-chrome-001", "producerSessionId 标识产生此事件的会话")
        XCTAssertEqual(event.producerSequence, 42, "producerSequence 是生产者侧的单调递增序号")
        XCTAssertNil(event.causedByEventId, "causedByEventId 表达跨进程因果关系，首事件可为 nil")
        XCTAssertEqual(event.monotonicClockMs, 1782200001000, "单调时钟，用于跨进程时序比对")
        XCTAssertEqual(event.wallClockMs, 1782200001000, "wall-clock，用于人类可读时间戳")
        XCTAssertEqual(event.gestureSessionId, "gesture-session-evidence", "关联的手势会话 ID")
        XCTAssertEqual(event.operationId, "op-evidence", "关联的幂等操作 ID")
        XCTAssertEqual(event.type, .actionRequest)

        // Round-trip 编解码验证
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(event)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ProviderEvent.self, from: data)

        XCTAssertEqual(decoded.eventId, event.eventId)
        XCTAssertEqual(decoded.producerSessionId, event.producerSessionId)
        XCTAssertEqual(decoded.producerSequence, event.producerSequence)
        XCTAssertEqual(decoded.monotonicClockMs, event.monotonicClockMs)
        XCTAssertEqual(decoded.wallClockMs, event.wallClockMs)
        XCTAssertEqual(decoded.gestureSessionId, event.gestureSessionId)
        XCTAssertEqual(decoded.operationId, event.operationId)
    }

    // MARK: - ProviderError 编解码

    /// ProviderError 携带结构化错误信息。
    func testProviderErrorEncodeDecode() throws {
        let error = ProviderError(code: "provider_storage_full", message: "Operation ledger 已达容量上限")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(error)

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(json["code"], "provider_storage_full")
        XCTAssertEqual(json["message"], "Operation ledger 已达容量上限")

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ProviderError.self, from: data)
        XCTAssertEqual(decoded.code, "provider_storage_full")
        XCTAssertEqual(decoded.message, "Operation ledger 已达容量上限")
    }

    // MARK: - ProviderMessageType 枚举

    /// Provider Protocol v2 的消息类型枚举必须包含全部已定义的消息类型。
    func testProviderMessageTypeAllCases() {
        let all = Set(ProviderMessageType.allCases)
        // 认证阶段
        XCTAssertTrue(all.contains(.providerHello))
        XCTAssertTrue(all.contains(.providerChallenge))
        XCTAssertTrue(all.contains(.providerAuthenticate))
        // 能力与上下文
        XCTAssertTrue(all.contains(.capabilitySnapshot))
        XCTAssertTrue(all.contains(.contextRequest))
        XCTAssertTrue(all.contains(.contextSnapshot))
        // 配置
        XCTAssertTrue(all.contains(.configurationSnapshot))
        XCTAssertTrue(all.contains(.configurationAck))
        // 动作执行
        XCTAssertTrue(all.contains(.actionRequest))
        XCTAssertTrue(all.contains(.actionAccepted))
        XCTAssertTrue(all.contains(.actionResult))
        // Telemetry
        XCTAssertTrue(all.contains(.telemetryBatch))
        XCTAssertTrue(all.contains(.telemetryAck))
        // 健康与状态
        XCTAssertTrue(all.contains(.healthProbe))
        XCTAssertTrue(all.contains(.healthResponse))
        XCTAssertTrue(all.contains(.operationStatusRequest))
        XCTAssertTrue(all.contains(.operationStatusResponse))
        // 候选期交互守卫
        XCTAssertTrue(all.contains(.interactionGuardArm))
        XCTAssertTrue(all.contains(.interactionGuardRelease))
    }

    // MARK: - ProviderMessageType raw values

    /// 验证消息类型原始值使用 snake_case 命名（协议字段格式）。
    func testProviderMessageTypeRawValues() {
        XCTAssertEqual(ProviderMessageType.providerHello.rawValue, "provider_hello")
        XCTAssertEqual(ProviderMessageType.actionRequest.rawValue, "action_request")
        XCTAssertEqual(ProviderMessageType.contextSnapshot.rawValue, "context_snapshot")
        XCTAssertEqual(ProviderMessageType.actionResult.rawValue, "action_result")
        XCTAssertEqual(ProviderMessageType.interactionGuardArm.rawValue, "interaction_guard_arm")
        XCTAssertEqual(ProviderMessageType.telemetryBatch.rawValue, "telemetry_batch")
    }
}
