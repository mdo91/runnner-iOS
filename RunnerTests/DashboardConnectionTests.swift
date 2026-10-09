import XCTest

@MainActor private final class StubDashboardService: DashboardLinkServicing {
  var dashboardURL: URL? { URL(string: "https://example.com/dashboard") }
  var reviews: [(DashboardLinkCode, String)] = []
  var approvals: [(DashboardLinkCode, String)] = []
  var browser = DashboardBrowser(
    agent: "Test browser", expiresAt: Date(timeIntervalSince1970: 2000))
  var reviewError: Error?
  var approvalError: Error?
  var pendingReview: CheckedContinuation<DashboardBrowser, Error>?
  var pendingApproval: CheckedContinuation<Void, Error>?
  var reviewStarted: XCTestExpectation?
  var approvalStarted: XCTestExpectation?

  func review(code: DashboardLinkCode, userID: String) async throws -> DashboardBrowser {
    reviews.append((code, userID))
    if let reviewStarted {
      return try await withCheckedThrowingContinuation {
        pendingReview = $0
        reviewStarted.fulfill()
      }
    }
    if let reviewError { throw reviewError }
    return browser
  }

  func approve(code: DashboardLinkCode, userID: String) async throws {
    approvals.append((code, userID))
    if let approvalStarted {
      return try await withCheckedThrowingContinuation {
        pendingApproval = $0
        approvalStarted.fulfill()
      }
    }
    if let approvalError { throw approvalError }
  }
}

@MainActor final class DashboardConnectionTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1000)
  private let validCode = "ABCDE12345"

  private func model(_ service: StubDashboardService) -> DashboardConnectionModel {
    let model = DashboardConnectionModel(service: service, now: { self.now })
    model.selectAccount("user-A")
    model.code = validCode
    return model
  }

  func testCodeAcceptsFormattingButRejectsInvalidCharactersAndPathComponents() {
    XCTAssertEqual(DashboardLinkCode(" abcde-12345\n")?.value, validCode)
    for invalid in [
      "", "ABCDE1234", "ABCDE123456", "ZZABCDE12345", "ABCDE/12345", "ABCDE?12345", "ＡBCDE12345",
    ] {
      XCTAssertNil(DashboardLinkCode(invalid), invalid)
    }
  }

  func testBrowserDecodesBothISODateFormatsAndRejectsMalformedExpiry() throws {
    for expiry in ["2026-10-09T10:00:00Z", "2026-10-09T10:00:00.123Z"] {
      let data = Data("{\"agent\":\"Safari\",\"expiresAt\":\"\(expiry)\"}".utf8)
      let browser = try JSONDecoder().decode(DashboardBrowser.self, from: data)
      XCTAssertEqual(browser.agent, "Safari")
      XCTAssertGreaterThan(browser.expiresAt, now)
    }
    for raw in ["\"not-a-date\"", "123", "null"] {
      let data = Data("{\"agent\":\"Safari\",\"expiresAt\":\(raw)}".utf8)
      XCTAssertThrowsError(try JSONDecoder().decode(DashboardBrowser.self, from: data))
    }
  }

  func testApprovalRequiresExplicitReviewAndUsesReviewedCodeAndAccount() async {
    let service = StubDashboardService()
    let model = model(service)
    await model.approve()
    XCTAssertTrue(service.approvals.isEmpty)
    await model.review()
    XCTAssertEqual(model.browser, service.browser)
    XCTAssertTrue(service.approvals.isEmpty)
    await model.approve()
    XCTAssertEqual(service.approvals.count, 1)
    XCTAssertEqual(service.approvals.first?.0.value, validCode)
    XCTAssertEqual(service.approvals.first?.1, "user-A")
    XCTAssertEqual(model.state, .approved)
  }

  func testInvalidOrSignedOutInputNeverRequestsReview() async {
    let service = StubDashboardService()
    let model = model(service)
    model.code = "short"
    await model.review()
    model.code = validCode
    model.selectAccount(nil)
    await model.review()
    XCTAssertFalse(model.canReview)
    XCTAssertTrue(service.reviews.isEmpty)
  }

  func testExpiredReviewIsRejectedAndExpiryIsRecheckedBeforeApproval() async {
    let service = StubDashboardService()
    var clock = now
    let model = DashboardConnectionModel(service: service, now: { clock })
    model.selectAccount("user-A")
    model.code = validCode
    service.browser = DashboardBrowser(agent: "Safari", expiresAt: now)
    await model.review()
    XCTAssertNil(model.browser)
    XCTAssertTrue(model.message?.contains("expired") == true)
    service.browser = DashboardBrowser(agent: "Safari", expiresAt: now.addingTimeInterval(10))
    await model.review()
    clock = now.addingTimeInterval(10)
    await model.approve()
    XCTAssertNil(model.browser)
    XCTAssertTrue(service.approvals.isEmpty)
  }

  func testOldReviewCannotReappearAfterCodeChangesEvenWhenChangedBack() async {
    let service = StubDashboardService()
    let model = model(service)
    let started = expectation(description: "review started")
    service.reviewStarted = started
    let request = Task { await model.review() }
    await fulfillment(of: [started], timeout: 2)
    model.code = "0123456789"
    model.code = validCode
    service.pendingReview?.resume(returning: service.browser)
    await request.value
    XCTAssertEqual(model.state, .idle)
    XCTAssertNil(model.browser)
    XCTAssertNil(model.message)
  }

  func testOldFailureDoesNotReplaceNewInputState() async {
    let service = StubDashboardService()
    let model = model(service)
    let started = expectation(description: "review started")
    service.reviewStarted = started
    let request = Task { await model.review() }
    await fulfillment(of: [started], timeout: 2)
    model.code = "0123456789"
    service.pendingReview?.resume(throwing: URLError(.notConnectedToInternet))
    await request.value
    XCTAssertNil(model.message)
    XCTAssertTrue(model.canReview)
  }

  func testAccountChangesAndDismissalInvalidateReview() async {
    let service = StubDashboardService()
    let model = model(service)
    await model.review()
    model.selectAccount("user-B")
    await model.approve()
    XCTAssertNil(model.browser)
    XCTAssertTrue(service.approvals.isEmpty)
    await model.review()
    XCTAssertEqual(service.reviews.last?.1, "user-B")
    model.reset()
    await model.approve()
    XCTAssertTrue(service.approvals.isEmpty)
  }

  func testDuplicateApprovalIsSuppressedAndAccountChangeIgnoresCompletion() async {
    let service = StubDashboardService()
    let model = model(service)
    await model.review()
    let started = expectation(description: "approval started")
    service.approvalStarted = started
    let request = Task { await model.approve() }
    await fulfillment(of: [started], timeout: 2)
    XCTAssertTrue(model.isWorking)
    await model.approve()
    XCTAssertEqual(service.approvals.count, 1)
    model.selectAccount("user-B")
    service.pendingApproval?.resume()
    await request.value
    XCTAssertEqual(model.state, .idle)
  }

  func testNetworkFailuresCanBeRetriedWithoutImplicitApproval() async {
    let service = StubDashboardService()
    let model = model(service)
    service.reviewError = URLError(.notConnectedToInternet)
    await model.review()
    XCTAssertNotNil(model.message)
    XCTAssertTrue(model.canReview)
    service.reviewError = nil
    await model.review()
    XCTAssertNil(model.message)
    service.approvalError = URLError(.timedOut)
    await model.approve()
    XCTAssertNotNil(model.browser)
    XCTAssertFalse(model.isWorking)
    XCTAssertNotNil(model.message)
    service.approvalError = nil
    await model.approve()
    XCTAssertEqual(model.state, .approved)
  }
}
