@testable import MeiliSearch
import Foundation
#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif
import XCTest

class DynamicSearchRulesTests: XCTestCase {
  private let ruleUid = "swift-sdk-issue-528-lifecycle"
  private var client: MeiliSearch!
  private var session: URLSession!

  private let initialActions = DynamicSearchRuleActions(
    pin: [
      DynamicSearchRulePinAction(indexUid: "products", id: "123", position: 1),
      DynamicSearchRulePinAction(id: "456", position: 0)
    ],
    scale: [DynamicSearchRuleScaleAction(ids: ["7", "8"], weight: 2.5)]
  )

  override func setUpWithError() throws {
    try super.setUpWithError()
    session = URLSession(configuration: .ephemeral)
    client = try MeiliSearch(
      host: currentHost(),
      apiKey: "masterKey",
      session: session
    )

    try enableDynamicSearchRules()
    try deleteLifecycleRule()
  }

  override func tearDownWithError() throws {
    try deleteLifecycleRule()
    client = nil
    session.invalidateAndCancel()
    session = nil
    try super.tearDownWithError()
  }

  func testDynamicSearchRulesLifecycle() async throws {
    let initialParams = DynamicSearchRuleParams(
      description: "Issue 528 lifecycle rule",
      precedence: 10,
      active: true,
      conditions: DynamicSearchRuleConditions(
        query: DynamicSearchRuleQueryCondition(words: "summer sale")
      ),
      actions: initialActions
    )

    let createTask = try await client.updateOrCreateDynamicSearchRule(
      uid: ruleUid,
      ruleParams: initialParams
    )
    XCTAssertEqual(createTask.type, .dynamicSearchRuleUpdate)
    let created = try await client.waitForTask(task: createTask)
    XCTAssertEqual(created.status, .succeeded)
    XCTAssertEqual(created.type, .dynamicSearchRuleUpdate)

    let fetched = try await client.getDynamicSearchRule(uid: ruleUid)
    XCTAssertEqual(fetched.uid, ruleUid)
    XCTAssertEqual(fetched.description, initialParams.description)
    XCTAssertEqual(fetched.precedence, initialParams.precedence)
    XCTAssertTrue(fetched.active)
    XCTAssertEqual(fetched.conditions, initialParams.conditions)
    XCTAssertEqual(fetched.actions, initialActions)

    let listed = try await client.listDynamicSearchRules(
      params: DynamicSearchRulesQuery(
        offset: 0,
        limit: 1,
        filter: DynamicSearchRulesFilter(query: "lifecycle", active: true)
      )
    )
    XCTAssertEqual(listed.offset, 0)
    XCTAssertEqual(listed.limit, 1)
    XCTAssertEqual(listed.total, 1)
    XCTAssertEqual(listed.results.first?.uid, ruleUid)
    XCTAssertEqual(listed.results.first?.actions, initialActions)

    let updateTask = try await client.updateOrCreateDynamicSearchRule(
      uid: ruleUid,
      ruleParams: DynamicSearchRuleParams(
        description: "Updated issue 528 lifecycle rule",
        active: false
      )
    )
    XCTAssertEqual(updateTask.type, .dynamicSearchRuleUpdate)
    let updated = try await client.waitForTask(task: updateTask)
    XCTAssertEqual(updated.status, .succeeded)

    let updatedRule = try await client.getDynamicSearchRule(uid: ruleUid)
    XCTAssertEqual(updatedRule.description, "Updated issue 528 lifecycle rule")
    XCTAssertFalse(updatedRule.active)
    XCTAssertEqual(updatedRule.conditions, initialParams.conditions)
    XCTAssertEqual(updatedRule.actions, initialActions)

    // Sent actions replace the stored ones as a whole, here with each form of scale filter.
    let filterActions = DynamicSearchRuleActions(
      scale: [
        DynamicSearchRuleScaleAction(indexUid: "products", filter: .expression("stock = 0"), weight: 0),
        DynamicSearchRuleScaleAction(
          ids: ["7"],
          filter: .groups([["genre = horror", "genre = comedy"], ["year > 2000"]]),
          weight: 0.5
        )
      ]
    )
    let replaceTask = try await client.updateOrCreateDynamicSearchRule(
      uid: ruleUid,
      ruleParams: DynamicSearchRuleParams(actions: filterActions)
    )
    let replaced = try await client.waitForTask(task: replaceTask)
    XCTAssertEqual(replaced.status, .succeeded)
    let replacedRule = try await client.getDynamicSearchRule(uid: ruleUid)
    XCTAssertEqual(replacedRule.actions, filterActions)
    XCTAssertEqual(replacedRule.description, "Updated issue 528 lifecycle rule")

    let removeTask = try await client.updateOrCreateDynamicSearchRule(
      uid: ruleUid,
      ruleParams: DynamicSearchRuleParams(actions: DynamicSearchRuleActions())
    )
    let removed = try await client.waitForTask(task: removeTask)
    XCTAssertEqual(removed.status, .succeeded)
    let ruleWithoutActions = try await client.getDynamicSearchRule(uid: ruleUid)
    XCTAssertEqual(ruleWithoutActions.actions, DynamicSearchRuleActions())

    let inactiveRules = try await client.listDynamicSearchRules(
      params: DynamicSearchRulesQuery(filter: DynamicSearchRulesFilter(query: "lifecycle", active: false))
    )
    XCTAssertEqual(inactiveRules.results.map { $0.uid }, [ruleUid])
    XCTAssertEqual(inactiveRules.results.first?.actions, DynamicSearchRuleActions())

    let deleteTask = try await client.deleteDynamicSearchRule(uid: ruleUid)
    XCTAssertEqual(deleteTask.type, .dynamicSearchRuleUpdate)
    let deleted = try await client.waitForTask(task: deleteTask)
    XCTAssertEqual(deleted.status, .succeeded)

    let ruleTasks = try await client.getTasks(
      params: TasksQuery(
        types: [.dynamicSearchRuleUpdate],
        uids: [createTask, updateTask, replaceTask, removeTask, deleteTask].map { $0.taskUid }
      )
    )
    XCTAssertEqual(ruleTasks.results.count, 5)
    XCTAssertTrue(ruleTasks.results.allSatisfy { $0.status == .succeeded && $0.type == .dynamicSearchRuleUpdate })

    do {
      _ = try await client.getDynamicSearchRule(uid: ruleUid)
      XCTFail("Expected the deleted rule to be unavailable")
    } catch let error as MeiliSearch.Error {
      switch error {
      case .meiliSearchApiError(_, let response, _, _):
        XCTAssertEqual(response?.code, "dynamic_search_rule_not_found")
      default:
        XCTFail("Unexpected Meilisearch error: \(error)")
      }
    }
  }

  func testDynamicSearchRulesLifecycleWithCompletionHandlers() throws {
    let createTask: TaskInfo = try waitForResult("Create a dynamic search rule") { completion in
      self.client.updateOrCreateDynamicSearchRule(
        uid: self.ruleUid,
        ruleParams: DynamicSearchRuleParams(description: "Issue 528 lifecycle rule", actions: self.initialActions),
        completion
      )
    }
    XCTAssertEqual(createTask.type, .dynamicSearchRuleUpdate)
    let created: MTask = try waitForResult("Wait for the dynamic search rule") { completion in
      self.client.waitForTask(task: createTask, completion)
    }
    XCTAssertEqual(created.status, .succeeded)

    let fetched: DynamicSearchRule = try waitForResult("Get a dynamic search rule") { completion in
      self.client.getDynamicSearchRule(uid: self.ruleUid, completion)
    }
    XCTAssertEqual(fetched.uid, ruleUid)
    XCTAssertTrue(fetched.active)
    XCTAssertEqual(fetched.conditions, DynamicSearchRuleConditions())
    XCTAssertEqual(fetched.actions, initialActions)

    let listed: DynamicSearchRulesResults = try waitForResult("List dynamic search rules") { completion in
      self.client.listDynamicSearchRules(
        params: DynamicSearchRulesQuery(filter: DynamicSearchRulesFilter(query: "lifecycle")),
        completion
      )
    }
    XCTAssertEqual(listed.results.map { $0.uid }, [ruleUid])
    XCTAssertEqual(listed.results.first?.actions, initialActions)

    let deleteTask: TaskInfo = try waitForResult("Delete a dynamic search rule") { completion in
      self.client.deleteDynamicSearchRule(uid: self.ruleUid, completion)
    }
    XCTAssertEqual(deleteTask.type, .dynamicSearchRuleUpdate)
    let deleted: MTask = try waitForResult("Wait for the deletion") { completion in
      self.client.waitForTask(task: deleteTask, completion)
    }
    XCTAssertEqual(deleted.status, .succeeded)

    let remaining: DynamicSearchRulesResults = try waitForResult("List dynamic search rules") { completion in
      self.client.listDynamicSearchRules(
        params: DynamicSearchRulesQuery(filter: DynamicSearchRulesFilter(query: "lifecycle")),
        completion
      )
    }
    XCTAssertEqual(remaining.total, 0)
    XCTAssertTrue(remaining.results.isEmpty)
  }

  private func waitForResult<Value>(
    _ description: String,
    _ operation: (@escaping (Result<Value, Swift.Error>) -> Void) -> Void
  ) throws -> Value {
    let expectation = XCTestExpectation(description: description)
    var received: Result<Value, Swift.Error>?

    operation { result in
      received = result
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: TESTS_TIME_OUT)
    return try XCTUnwrap(received, "\(description) did not complete").get()
  }

  private func enableDynamicSearchRules() throws {
    let url = try XCTUnwrap(URL(string: "\(currentHost())/experimental-features"))
    var request = URLRequest(url: url)
    request.httpMethod = "PATCH"
    request.setValue("Bearer masterKey", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = Data("{\"dynamicSearchRules\":true}".utf8)

    let expectation = XCTestExpectation(description: "Enable dynamic search rules")
    var requestError: Swift.Error?
    session.dataTask(with: request) { data, response, error in
      defer { expectation.fulfill() }
      if let error = error {
        requestError = error
        return
      }
      guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
        requestError = MeiliSearch.Error.invalidJSON
        return
      }
      guard
        let data = data,
        let features = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        features["dynamicSearchRules"] as? Bool == true
      else {
        requestError = MeiliSearch.Error.invalidJSON
        return
      }
    }.resume()

    wait(for: [expectation], timeout: TESTS_TIME_OUT)
    if let requestError = requestError {
      throw requestError
    }
  }

  private func deleteLifecycleRule() throws {
    let expectation = XCTestExpectation(description: "Clean up dynamic search rule")
    var cleanupError: Swift.Error?

    client.deleteDynamicSearchRule(uid: ruleUid) { result in
      switch result {
      case .success(let task):
        self.client.waitForTask(task: task) { result in
          if case .failure(let error) = result {
            cleanupError = error
          }
          expectation.fulfill()
        }
      case .failure(let error):
        cleanupError = error
        expectation.fulfill()
      }
    }

    wait(for: [expectation], timeout: TESTS_TIME_OUT)
    if let cleanupError = cleanupError {
      throw cleanupError
    }
  }
}
