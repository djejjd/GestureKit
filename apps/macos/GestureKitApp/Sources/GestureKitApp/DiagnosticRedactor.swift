import Foundation
import CryptoKit
import GestureKitCore

// ============================================================
// DiagnosticRedactor — 结构化白名单脱敏
// ============================================================
//
// 本文件实现双重脱敏（Double Redaction）：
// 1. Provider 采集源脱敏：只采集 host、路径 segment、tag/role 和枚举 failure reason。
// 2. App 入库端脱敏：再次拒绝 message、details、query、hash、DOM id/class/text。
//
// 核心设计：
// - URL 脱敏：移除 query/hash，对敏感路径段做 HMAC 指纹替换
//   （如 email、长十六进制 token）
// - 上下文脱敏：将 ContextSnapshotPayload 映射为只含白名单字段的
//   RedactedPageContext
// - HMAC 指纹：使用应用级密钥对敏感段做 HMAC-SHA256，截取前 16 字节
//   编码为十六进制字符串。同一敏感值在不同位置产生相同指纹，
//   支持统计关联而不暴露原始内容。

// MARK: - 白名单输出

/// 脱敏后的页面上下文，仅包含白名单字段。
public struct RedactedPageContext: Codable, Equatable, Sendable {
    /// 页面 host（如 "example.com"）
    public let host: String
    /// 脱敏后的路径（敏感段替换为指纹或占位符）
    public let redactedPath: String
    /// 目标分类（standard_link / no_target / page_unavailable）
    public let targetKind: String
    /// 目标角色（如 "link", "button", nil）
    public let targetRole: String?

    public init(host: String, redactedPath: String, targetKind: String, targetRole: String?) {
        self.host = host
        self.redactedPath = redactedPath
        self.targetKind = targetKind
        self.targetRole = targetRole
    }
}

// MARK: - 脱敏器

/// URL 和页面上下文的双重脱敏器。
///
/// 使用示例：
/// ```swift
/// let redactor = DiagnosticRedactor()
/// let safeURL = redactor.redactURL("https://example.com/user/a@example.com/token/abc123?secret=x")
/// // → "https://example.com/user/[email:ab12]/token/[hash:cd34]"
/// ```
public struct DiagnosticRedactor: Sendable {
    /// HMAC 密钥（应用级别，进程内生成一次）
    private let hmacKey: SymmetricKey

    /// 正则表达式：匹配 email-like 段（含 @ 的路径组件）
    private static let emailPattern = try! NSRegularExpression(
        pattern: "^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$",
        options: []
    )

    /// 正则表达式：匹配长数字或十六进制 token（12+ 位数字或 8+ 位 hex）
    private static let hexTokenPattern = try! NSRegularExpression(
        pattern: "^(?:[0-9a-fA-F]{8,}|[0-9]{12,})$",
        options: []
    )

    /// 正则表达式：匹配 Base64-url token（32+ 字符，含 - 和 _）
    private static let base64TokenPattern = try! NSRegularExpression(
        pattern: "^[A-Za-z0-9_-]{32,}$",
        options: []
    )

    // MARK: - 初始化

    /// 创建一个脱敏器。
    /// - Parameter key: HMAC 指纹密钥。默认为随机密钥，进程内一致。
    public init(key: SymmetricKey = SymmetricKey(size: .bits256)) {
        self.hmacKey = key
    }

    // MARK: - URL 脱敏

    /// 对 URL 字符串进行脱敏。
    ///
    /// 脱敏规则：
    /// 1. 移除 query string 和 fragment
    /// 2. 对路径中的敏感段做 HMAC 指纹替换
    ///    - email-like 段 → `[email:<指纹前缀>]`
    ///    - 长十六进制/数字段 → `[hash:<指纹前缀>]`
    ///    - Base64 token-like 段 → `[token:<指纹前缀>]`
    /// 3. 保留 host 和路径结构
    ///
    /// - Parameter urlString: 原始 URL 字符串
    /// - Returns: 脱敏后的 URL 字符串
    public func redactURL(_ urlString: String) -> String {
        guard var components = URLComponents(string: urlString),
              let scheme = components.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              let host = components.host,
              !host.isEmpty else {
            // 诊断边界必须 fail-closed，绝不能把无法验证的原始输入带入存储或导出。
            return ""
        }

        // 清除 query 和 fragment
        components.query = nil
        components.fragment = nil

        // 脱敏路径段
        let pathSegments = components.path.split(separator: "/", omittingEmptySubsequences: true)
        let redactedSegments = pathSegments.map { String($0) }.map(redactPathSegment)

        // 手动构建结果字符串，避免 URLComponents.percentEncodedPath 对标记字符做编码
        let schemePrefix = scheme + "://"
        let port = components.port.map { ":\($0)" } ?? ""
        let path = redactedSegments.isEmpty ? "" : "/" + redactedSegments.joined(separator: "/")

        return "\(schemePrefix)\(host)\(port)\(path)"
    }

    /// 对路径段进行脱敏。
    /// - Parameter segment: 原始路径段
    /// - Returns: 脱敏后的路径段
    public func redactPathSegment(_ segment: String) -> String {
        let range = NSRange(location: 0, length: segment.utf16.count)

        // 检查是否匹配敏感模式
        if Self.emailPattern.firstMatch(in: segment, options: [], range: range) != nil {
            let fingerprint = fingerprint(segment)
            return "[email:\(fingerprint)]"
        }

        if Self.hexTokenPattern.firstMatch(in: segment, options: [], range: range) != nil {
            let fingerprint = fingerprint(segment)
            return "[hash:\(fingerprint)]"
        }

        if Self.base64TokenPattern.firstMatch(in: segment, options: [], range: range) != nil {
            let fingerprint = fingerprint(segment)
            return "[token:\(fingerprint)]"
        }

        return segment
    }

    // MARK: - 上下文脱敏

    /// 将 ContextSnapshotPayload 脱敏为 RedactedPageContext。
    ///
    /// 只保留 host、路径（已脱敏）、targetKind，并尝试从 URL 推断 targetRole。
    /// 丢弃：query、hash、DOM 文本、id/class、Cookie、表单值、details。
    ///
    /// - Parameter context: 原始上下文快照
    /// - Returns: 脱敏后的页面上下文
    public func redactPageContext(_ context: ContextSnapshotPayload) -> RedactedPageContext {
        let redactedPath = redactURL(context.pageIdentity)

        // 无法安全解析页面身份时，丢弃全部页面数据并转为结构化不可用状态。
        guard !redactedPath.isEmpty, let safeURL = URL(string: redactedPath), let host = safeURL.host else {
            return RedactedPageContext(
                host: "",
                redactedPath: "",
                targetKind: ContextTargetKind.pageUnavailable.rawValue,
                targetRole: nil
            )
        }

        // 仅保留第一个路径段作为 redactedPath 的简化版
        let pathOnly = extractRedactedPath(from: redactedPath)

        let targetRole: String?
        if context.targetKind == .standardLink {
            targetRole = "link"
        } else {
            targetRole = nil
        }

        return RedactedPageContext(
            host: host,
            redactedPath: pathOnly,
            targetKind: context.targetKind.rawValue,
            targetRole: targetRole
        )
    }

    // MARK: - 辅助方法

    /// 计算 HMAC-SHA256 指纹（截取前 16 字节 = 32 十六进制字符）。
    private func fingerprint(_ value: String) -> String {
        let data = Data(value.utf8)
        let hmac = HMAC<SHA256>.authenticationCode(for: data, using: hmacKey)
        // 取前 16 字节（32 个十六进制字符），平衡安全性与可读性
        return Data(hmac).prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    /// 从已脱敏的完整 URL 中提取路径部分。
    private func extractRedactedPath(from redactedURL: String) -> String {
        guard let url = URL(string: redactedURL) else {
            return redactedURL
        }
        return url.path
    }
}

// MARK: - 红黑名单辅助

/// 检查字符串是否包含白名单禁止的字段。
/// 用于 Provider 输入端的额外校验。
/// - Parameter text: 待检查的字符串
/// - Returns: 如果包含禁止字段则返回 true
public func containsBlockedField(_ text: String) -> Bool {
    let blockedTerms = [
        "query", "hash", "domText", "elementId", "className",
        "cookie", "formValue", "details",
    ]
    let lowercased = text.lowercased()
    return blockedTerms.contains { lowercased.contains($0.lowercased()) }
}
