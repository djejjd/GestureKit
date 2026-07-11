import Foundation

/// 控制中心固定导航顺序，对应已确认的 V2 信息架构。
enum ControlCenterPage: String, CaseIterable, Identifiable {
    case overview = "概览"
    case operations = "操作记录"
    case presets = "手势预设"
    case providers = "Provider"
    case privacy = "隐私与存储"
    case advanced = "高级设置"

    var id: String { rawValue }
}

/// 用户可见状态的严重性，用于颜色和排序，不能替代中文文案。
enum PresentationSeverity: Equatable {
    case informational
    case warning
    case critical
}

/// 操作或系统状态的统一中文表现，禁止直接传递协议字段到 UI。
struct OperationPresentation: Equatable {
    let title: String
    let detail: String
    let suggestion: String

    static let resultUnknown = OperationPresentation(
        title: "操作结果暂时无法确认",
        detail: "系统未在期限内收到明确结果",
        suggestion: "系统已保存完整诊断信息"
    )
}

/// 控制中心需要向用户解释的保护或降级状态。
enum ControlCenterNotice: Equatable {
    case preparing
    case providerDisconnected
    case configurationSynchronizing
    case pageUnsupported
    case guardUnavailable
    case resultUnknown
    case listeningUnavailable
    case storageInsufficient

    /// 将内部状态映射为稳定的中文说明。
    func presentation() -> OperationPresentation {
        switch self {
        case .preparing:
            return OperationPresentation(title: "正在准备 GestureKit", detail: "正在检查手势监听和 Chrome 连接", suggestion: "准备完成后会显示当前状态")
        case .providerDisconnected:
            return OperationPresentation(title: "Chrome 连接已中断", detail: "浏览器动作暂时不会执行", suggestion: "恢复连接后系统会自动对账")
        case .configurationSynchronizing:
            return OperationPresentation(title: "当前预设正在同步", detail: "同步完成前暂不执行动作", suggestion: "避免 Provider 使用旧配置")
        case .pageUnsupported:
            return OperationPresentation(title: "当前页面暂不支持手势", detail: "页面上下文暂时不可用", suggestion: "可以切换到普通网页后重试")
        case .guardUnavailable:
            return OperationPresentation(title: "为避免误触，本次操作未执行", detail: "当前页面无法安全执行此操作", suggestion: "系统已保留诊断信息")
        case .resultUnknown:
            return .resultUnknown
        case .listeningUnavailable:
            return OperationPresentation(title: "无法开始手势监听", detail: "系统环境尚未满足监听条件", suggestion: "请在高级设置中查看说明")
        case .storageInsufficient:
            return OperationPresentation(title: "诊断存储空间不足", detail: "关键证据无法安全保存", suggestion: "系统已暂停新的动作以保护证据完整性")
        }
    }
}

/// 概览和二级页面复用的状态卡片数据。
struct ControlCenterStatusCard: Equatable {
    let title: String
    let detail: String
    let severity: PresentationSeverity
}

/// 概览页面所需的四项稳定状态。
struct ControlCenterOverview: Equatable {
    let runtime: ControlCenterStatusCard
    let provider: ControlCenterStatusCard
    let latestOperation: ControlCenterStatusCard
    let attention: ControlCenterStatusCard?
}

/// 操作列表项只保存 UI 所需的脱敏摘要。
struct OperationListItem: Identifiable, Equatable {
    let id: String
    let title: String
    let presentation: OperationPresentation
    let eventCount: Int
    let lastEventAt: Date
}

/// 操作记录页面的列表、空状态和分页状态。
struct OperationPageState: Equatable {
    let items: [OperationListItem]
    let selectedOperationID: String?
    let message: String?
    let canLoadMore: Bool

    static let empty = OperationPageState(items: [], selectedOperationID: nil, message: "暂无操作记录", canLoadMore: false)

    /// 当前详情只使用列表中的脱敏摘要，不在视图层重新读取底层事件。
    var selectedItem: OperationListItem? {
        items.first { $0.id == selectedOperationID }
    }
}

/// Provider 页面显示的状态卡片集合。
struct ProviderPageState: Equatable {
    let cards: [ControlCenterStatusCard]
}

/// 隐私与存储页面显示的状态卡片集合。
struct PrivacyPageState: Equatable {
    let cards: [ControlCenterStatusCard]
}
