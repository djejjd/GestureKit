import Foundation

/// 候选期需要的交互保护能力，由 App 的启用绑定编译得出。
public enum InteractionGuardFeature: String, Codable, Sendable, Equatable, Hashable {
    case linkClick = "link_click"
}

/// 配置驱动的识别计划。Provider 不消费该类型，也不需要了解手势绑定。
public struct RecognitionPlan: Sendable, Equatable {
    public let definitions: [GestureDefinition]
    private let featuresByDefinitionID: [String: Set<InteractionGuardFeature>]

    public init(configuration: AppConfiguration) throws {
        let definitionIDs = Set(configuration.gestureDefinitions.map(\.id))
        guard definitionIDs.count == configuration.gestureDefinitions.count else {
            throw RecognitionPlanError.duplicateGestureDefinitionID
        }
        guard configuration.rules.allSatisfy({ definitionIDs.contains($0.gestureDefinitionId) }) else {
            throw RecognitionPlanError.unknownGestureDefinition
        }
        self.definitions = configuration.gestureDefinitions
        var features: [String: Set<InteractionGuardFeature>] = [:]
        for rule in configuration.rules where rule.enabled && rule.actionId == .browserLinkOpenAdjacent {
            features[rule.gestureDefinitionId, default: []].insert(.linkClick)
        }
        self.featuresByDefinitionID = features
    }

    public func features(for gestureDefinitionID: String) -> Set<InteractionGuardFeature> {
        featuresByDefinitionID[gestureDefinitionID] ?? []
    }

    /// 候选期还没有方向、区域和次数等终态事实，只能按已参与识别的手指数
    /// 汇总潜在特征。这样 Provider 始终不知道具体手势或绑定关系。
    public func candidateFeatures(fingerCount: Int) -> Set<InteractionGuardFeature> {
        definitions
            .filter { $0.fingers == fingerCount }
            .reduce(into: Set<InteractionGuardFeature>()) { result, definition in
                result.formUnion(features(for: definition.id))
            }
    }
}

public enum RecognitionPlanError: Error, Equatable {
    case duplicateGestureDefinitionID
    case unknownGestureDefinition
}
