import Foundation

/**
 A dynamic search rule configured on a Meilisearch instance.

 Dynamic search rules are experimental: the `dynamicSearchRules` experimental feature must be enabled
 on the instance. The format of `actions` requires Meilisearch v1.54.0 or later.
 */
public struct DynamicSearchRule: Codable, Equatable {
  public let uid: String
  public let description: String?
  public let precedence: Int?
  public let active: Bool
  public let conditions: DynamicSearchRuleConditions
  public let actions: DynamicSearchRuleActions

  public init(
    uid: String,
    description: String? = nil,
    precedence: Int? = nil,
    active: Bool,
    conditions: DynamicSearchRuleConditions = DynamicSearchRuleConditions(),
    actions: DynamicSearchRuleActions = DynamicSearchRuleActions()
  ) {
    self.uid = uid
    self.description = description
    self.precedence = precedence
    self.active = active
    self.conditions = conditions
    self.actions = actions
  }
}

public struct DynamicSearchRuleConditions: Codable, Equatable {
  public let time: DynamicSearchRuleTimeCondition?
  public let query: DynamicSearchRuleQueryCondition?

  public init(
    time: DynamicSearchRuleTimeCondition? = nil,
    query: DynamicSearchRuleQueryCondition? = nil
  ) {
    self.time = time
    self.query = query
  }
}

public struct DynamicSearchRuleTimeCondition: Codable, Equatable {
  public let start: String?
  public let end: String?

  public init(start: String? = nil, end: String? = nil) {
    self.start = start
    self.end = end
  }
}

public struct DynamicSearchRuleQueryCondition: Codable, Equatable {
  public let isEmpty: Bool?
  public let words: String?

  public init(isEmpty: Bool? = nil, words: String? = nil) {
    self.isEmpty = isEmpty
    self.words = words
  }
}

/**
 The actions of a dynamic search rule, grouped by kind.

 A kind without actions is left out of the JSON, as Meilisearch does: a rule without actions has `{}`.
 */
public struct DynamicSearchRuleActions: Codable, Equatable {
  /// Documents pinned at a fixed position in the search results.
  public let pin: [DynamicSearchRulePinAction]
  /// Documents whose relevancy score is multiplied by a weight.
  public let scale: [DynamicSearchRuleScaleAction]

  public init(
    pin: [DynamicSearchRulePinAction] = [],
    scale: [DynamicSearchRuleScaleAction] = []
  ) {
    self.pin = pin
    self.scale = scale
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    pin = try container.decodeIfPresent([DynamicSearchRulePinAction].self, forKey: .pin) ?? []
    scale = try container.decodeIfPresent([DynamicSearchRuleScaleAction].self, forKey: .scale) ?? []
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    if !pin.isEmpty {
      try container.encode(pin, forKey: .pin)
    }
    if !scale.isEmpty {
      try container.encode(scale, forKey: .scale)
    }
  }

  private enum CodingKeys: String, CodingKey {
    case pin
    case scale
  }
}

public struct DynamicSearchRulePinAction: Codable, Equatable {
  /// Index the action is limited to. When `nil`, the action applies to searches on any index.
  public let indexUid: String?
  /// Primary key value of the document to pin.
  public let id: String
  /// Position at which the document is pinned.
  public let position: Int

  public init(indexUid: String? = nil, id: String, position: Int) {
    self.indexUid = indexUid
    self.id = id
    self.position = position
  }
}

/**
 Multiplies the relevancy score of the selected documents by `weight`.

 Meilisearch requires a non-empty `ids` or `filter`. When both are set, a document must match both.
 */
public struct DynamicSearchRuleScaleAction: Codable, Equatable {
  /// Index the action is limited to. When `nil`, the action applies to searches on any index.
  public let indexUid: String?
  /// Primary key values of the documents to select.
  public let ids: [String]?
  /// Filter selecting the documents.
  public let filter: DynamicSearchRuleFilter?
  /// Above 1 boosts the selected documents, below 1 demotes them and 0 hides them.
  public let weight: Double

  public init(
    indexUid: String? = nil,
    ids: [String]? = nil,
    filter: DynamicSearchRuleFilter? = nil,
    weight: Double
  ) {
    self.indexUid = indexUid
    self.ids = ids
    self.filter = filter
    self.weight = weight
  }
}

/**
 The filter of a scale action, in either form Meilisearch accepts.
 */
public enum DynamicSearchRuleFilter: Codable, Equatable {
  /// A single filter expression, such as `genres = horror AND year > 2000`.
  case expression(String)
  /// Groups of filter expressions: a document must match at least one expression of every group.
  case groups([[String]])

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let expression = try? container.decode(String.self) {
      self = .expression(expression)
    } else {
      self = .groups(try container.decode([Group].self).map { $0.expressions })
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .expression(let expression):
      try container.encode(expression)
    case .groups(let groups):
      try container.encode(groups)
    }
  }

  /// Meilisearch also accepts a bare expression in place of a group holding that one expression.
  private struct Group: Decodable {
    let expressions: [String]

    init(from decoder: Decoder) throws {
      let container = try decoder.singleValueContainer()
      if let expression = try? container.decode(String.self) {
        expressions = [expression]
      } else {
        expressions = try container.decode([String].self)
      }
    }
  }
}
