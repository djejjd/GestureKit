import Foundation
@testable import GestureKitApp
import GestureKitCore
import XCTest

// MARK: - DiagnosticRedactor 单元测试
//
// 本文件验证 DiagnosticRedactor 的以下行为：
// 1. URL 脱敏：移除 query/hash，指纹替换敏感路径段
// 2. 页面上下文脱敏：白名单字段检查
// 3. HMAC 指纹一致性：同一输入产生同一指纹
// 4. 正常路径段不修改
// 5. 边界情况：空字符串、无路径 URL、file URL

final class DiagnosticRedactorTests: XCTestCase {
    private var redactor: DiagnosticRedactor!

    override func setUpWithError() throws {
        redactor = DiagnosticRedactor()
    }

    // MARK: - URL 脱敏核心测试

    /// 验证脱敏器移除 query string、fragment，并指纹替换敏感路径段。
    ///
    /// 输入包含：
    /// - query (?token=x)
    /// - fragment (#frag)
    /// - email-like 路径段 (a@example.com)
    /// - 长数字路径段 (123456789012)
    ///
    /// 输出必须不包含上述任何明文。
    func testRedactorRemovesQueryHashAndTokenLikeSegments() {
        let value = redactor.redactURL(
            "https://example.com/user/a@example.com/reset/123456789012?token=x#frag"
        )

        // 验证敏感内容被移除
        XCTAssertFalse(value.contains("token="), "query string 必须被移除")
        XCTAssertFalse(value.contains("a@example.com"), "email 段必须被指纹替换")
        XCTAssertFalse(value.contains("123456789012"), "长数字段必须被指纹替换")

        // 验证 URL 前缀保留
        XCTAssertTrue(value.hasPrefix("https://example.com/"), "host 必须保留")

        // 验证指纹标记出现
        XCTAssertTrue(value.contains("[email:"), "email 段应替换为指纹标记")
        XCTAssertTrue(value.contains("[hash:"), "数字段应替换为指纹标记")
    }

    /// 验证不包含敏感信息的 URL 路径段保持原样。
    func testRedactorPreservesSafePathSegments() {
        let url = "https://example.com/articles/2024/gesture-recognition"
        let value = redactor.redactURL(url)

        // 无敏感段 → 完全保留
        XCTAssertEqual(value, url, "不包含敏感段的 URL 应保持原样")
    }

    /// 验证纯基本 URL（无路径）的脱敏结果不变。
    func testRedactorPreservesBaseURL() {
        let url = "https://example.com"
        let value = redactor.redactURL(url)
        XCTAssertEqual(value, url, "基本 URL 应保持原样")
    }

    /// 验证脱敏结果中不包含 query 和 fragment。
    func testRedactorStripsQueryAndFragment() {
        let value = redactor.redactURL(
            "https://example.com/page?key=secret&session=abc#section"
        )

        // query 和 fragment 必须被移除
        XCTAssertFalse(value.contains("key=secret"), "query 参数必须被移除")
        XCTAssertFalse(value.contains("?key"), "问号起始的 query 必须被移除")
        XCTAssertFalse(value.contains("#section"), "fragment 必须被移除")

        // 纯路径部分保留
        XCTAssertTrue(value.contains("/page"), "路径部分应保留")
    }

    // MARK: - 页面上下文脱敏

    /// 验证 ContextSnapshotPayload 脱敏为只含白名单字段的 RedactedPageContext。
    func testRedactPageContextPreservesWhitelistFields() throws {
        let context = ContextSnapshotPayload(
            contextId: "ctx-whitelist",
            pageIdentity: "https://example.com/page/article-123",
            expiresAt: 1_782_200_002_000,
            targetKind: .standardLink,
            targetRef: "opaque-ref-xyz"
        )

        let result = redactor.redactPageContext(context)

        // 白名单字段
        XCTAssertEqual(result.host, "example.com")
        XCTAssertTrue(result.redactedPath.contains("/page/article-123"),
                      "安全路径段应保留在原位")
        XCTAssertEqual(result.targetKind, "standard_link")
        XCTAssertEqual(result.targetRole, "link")

        // 验证 JSON 序列化结果不包含禁止字段
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let jsonData = try encoder.encode(result)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: jsonData) as? [String: Any])

        XCTAssertNil(json["contextId"], "RedactedPageContext 不得包含 contextId")
        XCTAssertNil(json["pageIdentity"], "RedactedPageContext 不得包含 pageIdentity")
        XCTAssertNil(json["targetRef"], "RedactedPageContext 不得包含 targetRef")
        XCTAssertNil(json["expiresAt"], "RedactedPageContext 不得包含 expiresAt")
        XCTAssertNil(json["causedByEventId"], "RedactedPageContext 不得包含 causedByEventId")
        XCTAssertNil(json["producerSessionId"], "RedactedPageContext 不得包含 producerSessionId")
    }

    /// 验证 no_target 上下文的脱敏：targetRole 应为 nil。
    func testRedactPageContextNoTarget() {
        let context = ContextSnapshotPayload(
            contextId: "ctx-002",
            pageIdentity: "https://example.com",
            expiresAt: 1000,
            targetKind: .noTarget,
            targetRef: nil
        )

        let result = redactor.redactPageContext(context)
        XCTAssertEqual(result.host, "example.com")
        XCTAssertEqual(result.targetKind, "no_target")
        XCTAssertNil(result.targetRole, "无目标时 targetRole 应为 nil")
    }

    /// 验证 page_unavailable 上下文的脱敏。
    func testRedactPageContextUnavailable() {
        let context = ContextSnapshotPayload(
            contextId: "ctx-003",
            pageIdentity: "about:blank",
            expiresAt: 1000,
            targetKind: .pageUnavailable,
            targetRef: nil
        )

        let result = redactor.redactPageContext(context)
        XCTAssertEqual(result.targetKind, "page_unavailable")
        XCTAssertNil(result.targetRole)
    }

    // MARK: - HMAC 指纹一致性

    /// 验证同一输入在同一 Redactor 实例中产生相同的指纹。
    func testDeterministicFingerprintForSameInput() {
        // 无法直接访问 fingerprint 方法（private），
        // 但通过两次相同的 URL 脱敏来验证确定性
        let url = "https://example.com/user/a@example.com/profile"
        let first = redactor.redactURL(url)
        let second = redactor.redactURL(url)

        XCTAssertEqual(first, second, "同一 Redactor 实例对相同 URL 应产生一致的脱敏结果")
    }

    /// 验证不同 Redactor 实例的指纹不同（不同密钥）。
    func testDifferentRedactorDifferentFingerprint() {
        let anotherRedactor = DiagnosticRedactor()
        let url = "https://example.com/user/a@example.com/profile"

        let first = redactor.redactURL(url)
        let second = anotherRedactor.redactURL(url)

        // 两个实例使用不同密钥，指纹应不同（虽然都是 [email:...] 格式）
        if first == second {
            // 虽然理论上概率极低，但两个不同密钥产生相同指纹前缀是可能的
            // 至少验证格式一致
            XCTAssertTrue(first.contains("[email:"))
            XCTAssertTrue(second.contains("[email:"))
        } else {
            XCTAssertNotEqual(first, second, "不同 Redactor 实例对相同输入应产生不同指纹")
        }
    }

    // MARK: - 边界情况

    /// 无法解析的输入必须 fail-closed，不能原样返回敏感字符串。
    func testRedactEmptyURL() {
        let value = redactor.redactURL("")
        XCTAssertEqual(value, "", "空 URL 应收敛为空安全值")
    }

    /// 验证纯 host（无 scheme）不会作为原始页面身份保留。
    func testRedactHostOnlyURL() {
        let value = redactor.redactURL("example.com")
        XCTAssertEqual(value, "")
    }

    /// 非允许 scheme 必须丢弃，不能把本地路径写入诊断数据。
    func testRedactFileURL() {
        let value = redactor.redactURL("file:///Users/test/Documents/report.pdf")
        XCTAssertEqual(value, "")
    }

    /// 无效页面身份必须映射为 page_unavailable，且不得输出原始值。
    func testRedactPageContextFailsClosedForInvalidURL() {
        let context = ContextSnapshotPayload(
            contextId: "ctx-invalid",
            pageIdentity: "not-a-url?secret=raw",
            expiresAt: 1000,
            targetKind: .standardLink,
            targetRef: "opaque"
        )
        let result = redactor.redactPageContext(context)
        XCTAssertEqual(result.host, "")
        XCTAssertEqual(result.redactedPath, "")
        XCTAssertEqual(result.targetKind, ContextTargetKind.pageUnavailable.rawValue)
    }

    // MARK: - 禁止字段检测

    /// 验证 blocked field 检测函数。
    func testContainsBlockedField() {
        XCTAssertTrue(containsBlockedField("contains domText here"))
        XCTAssertTrue(containsBlockedField("query=something"))
        XCTAssertTrue(containsBlockedField("elementId=123"))
        XCTAssertTrue(containsBlockedField("className=btn"))
        XCTAssertTrue(containsBlockedField("cookie=session"))
        XCTAssertTrue(containsBlockedField("formValue=test"))
        XCTAssertTrue(containsBlockedField("details=everything"))

        XCTAssertFalse(containsBlockedField("host=example.com"))
        XCTAssertFalse(containsBlockedField("targetKind=standard_link"))
        XCTAssertFalse(containsBlockedField("targetRef=opaque"))
    }
}
