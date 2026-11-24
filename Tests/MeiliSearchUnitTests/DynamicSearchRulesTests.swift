@testable import MeiliSearch
import Foundation
import XCTest

class DynamicSearchRulesTests: XCTestCase {
  private var client: MeiliSearch!
  private let session = MockURLSession()

  override func setUpWithError() throws {
    try super.setUpWithError()
    client = try MeiliSearch(
      host: "http://localhost:7700",
      apiKey: "masterKey",
      session: session
    )
  }

  func testListDynamicSearchRulesUsesPostBodyAndDecodesResults() async throws {
    let json = """
      {
        "results": [
          {
            "uid": "black-friday",
            "description": "Black Friday rules",
            "precedence": 10,
            "active": true,
            "conditions": {
              "query": { "words": "black friday" },
              "time": {
                "start": "2026-11-27T00:00:00Z",
                "end": "2026-11-28T00:00:00Z"
              }
            },
            "actions": {
              "pin": [{ "indexUid": "products", "id": "123", "position": 1 }],
              "scale": [{ "ids": ["1"], "weight": 2.0 }]
            }
          },
          {
            "uid": "no-actions",
            "lastUpdatedAt": "2026-11-24T13:43:59.293073542Z",
            "active": false,
            "conditions": {},
            "actions": {}
          }
        ],
        "offset": 10,
        "limit": 2,
        "total": 2
      }
      """
    session.pushData(json)

    let params = DynamicSearchRulesQuery(
      offset: 10,
      limit: 2,
      filter: DynamicSearchRulesFilter(query: "black", active: true)
    )
    let result = try await client.listDynamicSearchRules(params: params)

    XCTAssertEqual(result.offset, 10)
    XCTAssertEqual(result.limit, 2)
    XCTAssertEqual(result.total, 2)
    XCTAssertEqual(result.results.first?.uid, "black-friday")
    XCTAssertEqual(result.results.first?.conditions.query?.words, "black friday")
    XCTAssertEqual(
      result.results.first?.actions,
      DynamicSearchRuleActions(
        pin: [DynamicSearchRulePinAction(indexUid: "products", id: "123", position: 1)],
        scale: [DynamicSearchRuleScaleAction(ids: ["1"], weight: 2)]
      )
    )
    XCTAssertEqual(result.results.last?.uid, "no-actions")
    XCTAssertEqual(result.results.last?.actions, DynamicSearchRuleActions())
    XCTAssertEqual(session.nextDataTask.request?.httpMethod, "POST")
    XCTAssertEqual(session.nextDataTask.request?.url?.path, "/dynamic-search-rules")

    let body = try XCTUnwrap(session.nextDataTask.request?.httpBody)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    XCTAssertEqual(object["offset"] as? Int, 10)
    XCTAssertEqual(object["limit"] as? Int, 2)
    let filter = try XCTUnwrap(object["filter"] as? [String: Any])
    XCTAssertEqual(filter["query"] as? String, "black")
    XCTAssertEqual(filter["active"] as? Bool, true)
  }

  func testGetDynamicSearchRuleUsesGetAndDecodesRule() {
    let json = """
      {
        "uid": "black-friday",
        "description": null,
        "precedence": null,
        "active": true,
        "conditions": { "query": { "isEmpty": true } },
        "actions": { "pin": [{ "id": "123", "position": 0 }] }
      }
      """
    session.pushData(json)
    let expectation = XCTestExpectation(description: "Get a dynamic search rule")

    client.getDynamicSearchRule(uid: "black-friday") { result in
      switch result {
      case .success(let rule):
        XCTAssertEqual(rule.uid, "black-friday")
        XCTAssertTrue(rule.conditions.query?.isEmpty == true)
        XCTAssertNil(rule.actions.pin.first?.indexUid)
        XCTAssertEqual(rule.actions.pin.first?.id, "123")
        XCTAssertEqual(rule.actions.pin.first?.position, 0)
        XCTAssertTrue(rule.actions.scale.isEmpty)
      case .failure(let error):
        XCTFail("Unexpected error: \(error)")
      }
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: TESTS_TIME_OUT)
    XCTAssertEqual(session.nextDataTask.request?.httpMethod, "GET")
    XCTAssertEqual(session.nextDataTask.request?.url?.path, "/dynamic-search-rules/black-friday")
  }

  func testUpdateOrCreateDynamicSearchRuleUsesPatchBodyAndDecodesTask() async throws {
    let taskJSON = """
      {
        "taskUid": 147,
        "indexUid": ".meili_dsr",
        "status": "enqueued",
        "type": "dsrUpdate",
        "enqueuedAt": "2026-07-22T07:09:29.364Z"
      }
      """
    session.pushData(taskJSON, code: 202)

    let ruleParams = DynamicSearchRuleParams(
      description: "Black Friday rules",
      precedence: 10,
      active: true,
      conditions: DynamicSearchRuleConditions(
        time: DynamicSearchRuleTimeCondition(
          start: "2026-11-27T00:00:00Z",
          end: "2026-11-28T00:00:00Z"
        ),
        query: DynamicSearchRuleQueryCondition(isEmpty: true)
      ),
      actions: DynamicSearchRuleActions(
        pin: [DynamicSearchRulePinAction(indexUid: "products", id: "123", position: 1)],
        scale: [
          DynamicSearchRuleScaleAction(ids: ["4", "5"], weight: 2.5),
          DynamicSearchRuleScaleAction(indexUid: "products", filter: .expression("stock = 0"), weight: 0)
        ]
      )
    )

    let task = try await client.updateOrCreateDynamicSearchRule(
      uid: "black-friday",
      ruleParams: ruleParams
    )

    XCTAssertEqual(task.taskUid, 147)
    XCTAssertEqual(task.type, .dynamicSearchRuleUpdate)
    XCTAssertEqual(session.nextDataTask.request?.httpMethod, "PATCH")
    XCTAssertEqual(session.nextDataTask.request?.url?.path, "/dynamic-search-rules/black-friday")

    let body = try XCTUnwrap(session.nextDataTask.request?.httpBody)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    XCTAssertEqual(object["precedence"] as? Int, 10)
    XCTAssertNil(object["priority"])
    let conditions = try XCTUnwrap(object["conditions"] as? [String: Any])
    XCTAssertNotNil(conditions["query"] as? [String: Any])
    XCTAssertNotNil(conditions["time"] as? [String: Any])
    try assertJSON(
      object["actions"],
      equals: """
        {
          "pin": [{ "indexUid": "products", "id": "123", "position": 1 }],
          "scale": [
            { "ids": ["4", "5"], "weight": 2.5 },
            { "indexUid": "products", "filter": "stock = 0", "weight": 0 }
          ]
        }
        """
    )
  }

  func testDeleteDynamicSearchRuleUsesDeleteAndDecodesTask() {
    let taskJSON = """
      {
        "taskUid": 148,
        "indexUid": ".meili_dsr",
        "status": "enqueued",
        "type": "dsrUpdate",
        "enqueuedAt": "2026-07-22T07:09:47.033Z"
      }
      """
    session.pushData(taskJSON, code: 202)
    let expectation = XCTestExpectation(description: "Delete a dynamic search rule")

    client.deleteDynamicSearchRule(uid: "black-friday") { result in
      switch result {
      case .success(let task):
        XCTAssertEqual(task.taskUid, 148)
        XCTAssertEqual(task.type, .dynamicSearchRuleUpdate)
      case .failure(let error):
        XCTFail("Unexpected error: \(error)")
      }
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: TESTS_TIME_OUT)
    XCTAssertEqual(session.nextDataTask.request?.httpMethod, "DELETE")
    XCTAssertEqual(session.nextDataTask.request?.url?.path, "/dynamic-search-rules/black-friday")
  }

  func testListDynamicSearchRulesWithoutParamsSendsEmptyObject() async throws {
    session.pushData("""
      { "results": [], "offset": 0, "limit": 20, "total": 0 }
      """)

    _ = try await client.listDynamicSearchRules()

    let body = try XCTUnwrap(session.nextDataTask.request?.httpBody)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    XCTAssertTrue(object.isEmpty)
  }

  func testUpdateOrCreateDynamicSearchRuleOmitsUnsetFields() async throws {
    session.pushData("""
      {
        "taskUid": 149,
        "indexUid": ".meili_dsr",
        "status": "enqueued",
        "type": "dsrUpdate",
        "enqueuedAt": "2026-07-22T07:10:00.000Z"
      }
      """, code: 202)

    _ = try await client.updateOrCreateDynamicSearchRule(
      uid: "black-friday",
      ruleParams: DynamicSearchRuleParams(description: "Updated description")
    )

    let body = try XCTUnwrap(session.nextDataTask.request?.httpBody)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    XCTAssertEqual(object.count, 1)
    XCTAssertEqual(object["description"] as? String, "Updated description")
  }

  func testGetDynamicSearchRulePropagatesAPIError() async throws {
    session.pushData("""
      {
        "message": "Dynamic search rule `missing` not found.",
        "code": "dynamic_search_rule_not_found",
        "type": "invalid_request",
        "link": "https://docs.meilisearch.com/errors#dynamic_search_rule_not_found"
      }
      """, code: 404)

    do {
      _ = try await client.getDynamicSearchRule(uid: "missing")
      XCTFail("Expected the API error to be thrown")
    } catch let error as MeiliSearch.Error {
      switch error {
      case .meiliSearchApiError(_, let response, _, _):
        XCTAssertEqual(response?.code, "dynamic_search_rule_not_found")
      default:
        XCTFail("Unexpected Meilisearch error: \(error)")
      }
    }
  }

  func testListDynamicSearchRulesWithCompletionDecodesResults() {
    session.pushData("""
      {
        "results": [
          {
            "uid": "boost-horror",
            "lastUpdatedAt": "2026-11-24T13:43:59.037928179Z",
            "active": true,
            "conditions": {},
            "actions": { "scale": [{ "ids": ["1"], "filter": "genre = horror", "weight": 3.0 }] }
          }
        ],
        "offset": 0,
        "limit": 20,
        "total": 1
      }
      """)
    let expectation = XCTestExpectation(description: "List dynamic search rules")

    client.listDynamicSearchRules { result in
      switch result {
      case .success(let rules):
        XCTAssertEqual(rules.total, 1)
        XCTAssertEqual(
          rules.results.first?.actions.scale,
          [DynamicSearchRuleScaleAction(ids: ["1"], filter: .expression("genre = horror"), weight: 3)]
        )
        XCTAssertEqual(rules.results.first?.actions.pin, [])
      case .failure(let error):
        XCTFail("Unexpected error: \(error)")
      }
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: TESTS_TIME_OUT)
    XCTAssertEqual(session.nextDataTask.request?.httpMethod, "POST")
    XCTAssertEqual(session.nextDataTask.request?.url?.path, "/dynamic-search-rules")
  }

  func testGetDynamicSearchRuleDecodesRuleWithoutActions() async throws {
    session.pushData("""
      {
        "uid": "no-actions",
        "description": "no actions",
        "lastUpdatedAt": "2026-11-24T13:43:59.293073542Z",
        "active": true,
        "conditions": {},
        "actions": {}
      }
      """)

    let rule = try await client.getDynamicSearchRule(uid: "no-actions")

    XCTAssertEqual(rule.uid, "no-actions")
    XCTAssertEqual(rule.conditions, DynamicSearchRuleConditions())
    XCTAssertEqual(rule.actions, DynamicSearchRuleActions())
    XCTAssertEqual(session.nextDataTask.request?.httpMethod, "GET")
    XCTAssertEqual(session.nextDataTask.request?.url?.path, "/dynamic-search-rules/no-actions")
  }

  func testGetDynamicSearchRuleRejectsActionsListOfOlderServers() async throws {
    session.pushData("""
      {
        "uid": "black-friday",
        "active": true,
        "conditions": {},
        "actions": [{ "selector": { "id": "123" }, "action": { "type": "pin", "position": 0 } }]
      }
      """)

    do {
      _ = try await client.getDynamicSearchRule(uid: "black-friday")
      XCTFail("Expected the actions list of Meilisearch v1.53 to be rejected")
    } catch let DecodingError.typeMismatch(_, context) {
      XCTAssertEqual(context.codingPath.map { $0.stringValue }, ["actions"])
    }
  }

  func testUpdateOrCreateDynamicSearchRuleWithCompletionSendsScaleActions() throws {
    session.pushData("""
      {
        "taskUid": 150,
        "indexUid": ".meili_dsr",
        "status": "enqueued",
        "type": "dsrUpdate",
        "enqueuedAt": "2026-11-24T13:43:59.170712282Z"
      }
      """, code: 202)
    let expectation = XCTestExpectation(description: "Update a dynamic search rule")
    let filter = DynamicSearchRuleFilter.groups([["genre = horror", "genre = comedy"], ["year > 2000"]])

    client.updateOrCreateDynamicSearchRule(
      uid: "boost-horror",
      ruleParams: DynamicSearchRuleParams(
        actions: DynamicSearchRuleActions(scale: [DynamicSearchRuleScaleAction(filter: filter, weight: 0.5)])
      )
    ) { result in
      switch result {
      case .success(let task):
        XCTAssertEqual(task.taskUid, 150)
        XCTAssertEqual(task.type, .dynamicSearchRuleUpdate)
      case .failure(let error):
        XCTFail("Unexpected error: \(error)")
      }
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: TESTS_TIME_OUT)
    XCTAssertEqual(session.nextDataTask.request?.httpMethod, "PATCH")
    XCTAssertEqual(session.nextDataTask.request?.url?.path, "/dynamic-search-rules/boost-horror")

    let body = try XCTUnwrap(session.nextDataTask.request?.httpBody)
    try assertJSON(
      JSONSerialization.jsonObject(with: body),
      equals: """
        { "actions": { "scale": [{ "filter": [["genre = horror", "genre = comedy"], ["year > 2000"]], "weight": 0.5 }] } }
        """
    )
  }

  func testUpdateOrCreateDynamicSearchRuleSendsEmptyActionsToRemoveThem() async throws {
    session.pushData("""
      {
        "taskUid": 151,
        "indexUid": ".meili_dsr",
        "status": "enqueued",
        "type": "dsrUpdate",
        "enqueuedAt": "2026-11-24T13:43:58.740076987Z"
      }
      """, code: 202)

    _ = try await client.updateOrCreateDynamicSearchRule(
      uid: "black-friday",
      ruleParams: DynamicSearchRuleParams(actions: DynamicSearchRuleActions())
    )

    let body = try XCTUnwrap(session.nextDataTask.request?.httpBody)
    XCTAssertEqual(String(data: body, encoding: .utf8), #"{"actions":{}}"#)
  }

  func testDeleteDynamicSearchRuleAsyncUsesDeleteAndDecodesTask() async throws {
    session.pushData("""
      {
        "taskUid": 152,
        "indexUid": ".meili_dsr",
        "status": "enqueued",
        "type": "dsrUpdate",
        "enqueuedAt": "2026-11-24T13:43:59.293073542Z"
      }
      """, code: 202)

    let task = try await client.deleteDynamicSearchRule(uid: "black-friday")

    XCTAssertEqual(task.taskUid, 152)
    XCTAssertEqual(task.type, .dynamicSearchRuleUpdate)
    XCTAssertEqual(session.nextDataTask.request?.httpMethod, "DELETE")
    XCTAssertEqual(session.nextDataTask.request?.url?.path, "/dynamic-search-rules/black-friday")
  }

  func testDynamicSearchRuleActionsRoundTripServerValues() throws {
    // `actions` as returned by Meilisearch v1.58.0 for each form it accepts.
    let serverValues = [
      #"{}"#,
      #"{"pin":[{"indexUid":"products","id":"123","position":1}]}"#,
      #"{"pin":[{"id":"9","position":0}]}"#,
      #"{"scale":[{"ids":["1","2"],"weight":2.5}]}"#,
      #"{"scale":[{"indexUid":"products","filter":"genre = horror","weight":0.5}]}"#,
      #"{"scale":[{"filter":[["genre = horror","genre = comedy"],["year > 2000"]],"weight":0.0}]}"#,
      #"{"scale":[{"ids":["1"],"filter":"genre = horror","weight":3.0}]}"#,
      #"{"scale":[{"ids":["1"],"weight":-1.0}]}"#,
      #"{"pin":[{"indexUid":"products","id":"123","position":1}],"scale":[{"ids":["1"],"weight":2.0}]}"#
    ]

    for serverValue in serverValues {
      let decoded: DynamicSearchRuleActions = try decodeJSON(from: serverValue)
      let encoded = try Constants.customJSONEecoder.encode(decoded)

      try assertJSON(JSONSerialization.jsonObject(with: encoded), equals: serverValue)
    }
  }

  func testDynamicSearchRuleActionsDecodeEmptyNullAndUnknownValues() throws {
    let emptyLists: DynamicSearchRuleActions = try decodeJSON(from: #"{"pin":[],"scale":[]}"#)
    XCTAssertEqual(emptyLists, DynamicSearchRuleActions())

    let nullLists: DynamicSearchRuleActions = try decodeJSON(from: #"{"pin":null,"scale":null}"#)
    XCTAssertEqual(nullLists, DynamicSearchRuleActions())

    let unknownKind: DynamicSearchRuleActions = try decodeJSON(
      from: #"{"pin":[{"indexUid":null,"id":"9","position":0}],"futureKind":[{"id":"1"}]}"#
    )
    XCTAssertEqual(unknownKind, DynamicSearchRuleActions(pin: [DynamicSearchRulePinAction(id: "9", position: 0)]))

    let nullSelectors: DynamicSearchRuleScaleAction = try decodeJSON(
      from: #"{"indexUid":null,"ids":null,"filter":null,"weight":1}"#
    )
    XCTAssertEqual(nullSelectors, DynamicSearchRuleScaleAction(weight: 1))

    XCTAssertThrowsError(try decodeJSON(from: #"{"scale":[{"ids":["1"]}]}"#) as DynamicSearchRuleActions)
    XCTAssertThrowsError(try decodeJSON(from: #"{"pin":[{"id":"9"}]}"#) as DynamicSearchRuleActions)
  }

  func testDynamicSearchRuleFilterDecodesBothServerForms() throws {
    let expression: DynamicSearchRuleFilter = try decodeJSON(from: #""genre = horror""#)
    XCTAssertEqual(expression, .expression("genre = horror"))

    // Meilisearch returns the filter as it was sent, where a group may be a bare expression.
    let mixed: DynamicSearchRuleFilter = try decodeJSON(
      from: #"[["genre = horror","genre = comedy"],"year > 2000"]"#
    )
    XCTAssertEqual(mixed, .groups([["genre = horror", "genre = comedy"], ["year > 2000"]]))

    XCTAssertThrowsError(try decodeJSON(from: "42") as DynamicSearchRuleFilter)
    XCTAssertThrowsError(try decodeJSON(from: #"[[["genre = horror"]]]"#) as DynamicSearchRuleFilter)
  }

  private func assertJSON(
    _ value: Any?,
    equals json: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws {
    let expected = try JSONSerialization.jsonObject(with: Data(json.utf8), options: [.allowFragments])
    XCTAssertTrue(
      jsonValuesAreEqual(value, expected),
      "\(String(describing: value)) is not equal to \(json)",
      file: file,
      line: line
    )
  }

  private func jsonValuesAreEqual(_ lhs: Any?, _ rhs: Any?) -> Bool {
    switch (lhs, rhs) {
    case let (lhs as [String: Any], rhs as [String: Any]):
      return lhs.count == rhs.count && lhs.allSatisfy { key, value in
        rhs[key].map { jsonValuesAreEqual(value, $0) } ?? false
      }
    case let (lhs as [Any], rhs as [Any]):
      return lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { jsonValuesAreEqual($0, $1) }
    case let (lhs as String, rhs as String):
      return lhs == rhs
    case let (lhs as Double, rhs as Double):
      return lhs == rhs
    default:
      return false
    }
  }
}
