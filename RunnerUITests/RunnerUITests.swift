import XCTest

@MainActor final class RunnerUITests: XCTestCase {
  private var app: XCUIApplication!
  private let testID = UUID().uuidString
  override func setUpWithError() throws { continueAfterFailure = false }
  override func tearDownWithError() throws {
    if let app {
      let shot = XCTAttachment(screenshot: app.screenshot())
      shot.name = name
      shot.lifetime = testRun?.hasSucceeded == true ? .deleteOnSuccess : .keepAlways
      add(shot)
      app.terminate()
    }
    XCUIDevice.shared.orientation = .portrait
  }
  @discardableResult private func launch(
    _ scenario: String = "populated", appearance: String = "light", largeText: Bool = false
  ) -> XCUIApplication {
    app = XCUIApplication()
    app.launchArguments = [
      "--ui-scenario", scenario, "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
    ]
    app.launchEnvironment = [
      "RUNNER_TEST_ID": testID, "RUNNER_APPEARANCE": appearance,
      "RUNNER_LARGE_TEXT": largeText ? "1" : "0",
    ]
    app.launch()
    XCTAssertTrue(app.buttons["Activity"].firstMatch.waitForExistence(timeout: 15))
    return app
  }
  private func tab(_ name: String) {
    let button = app.buttons[name].firstMatch
    XCTAssertTrue(button.waitForExistence(timeout: 5))
    button.tap()
  }
  private func reveal(_ element: XCUIElement, limit: Int = 12) {
    for _ in 0..<limit {
      if element.exists && element.isHittable { return }
      app.swipeUp()
    }
    XCTAssertTrue(element.exists && element.isHittable, "Could not reveal \(element)")
  }
  private func openDashboard() {
    tab("Latest")
    app.buttons["navigation.settings"].tap()
    let connect = app.buttons["settings.dashboard"]
    reveal(connect)
    connect.tap()
    XCTAssertTrue(app.textFields["dashboard.code"].waitForExistence(timeout: 5))
  }
  func testNavigationAndActivityCheckpointRegression() {
    launch()
    for name in ["History", "Activity", "Trends", "Live", "Latest"] { tab(name) }
    for _ in 0..<3 {
      tab("Activity")
      XCTAssertEqual(app.staticTexts["activity.total"].label, "3 runs")
      tab("Latest")
    }
    app.buttons["navigation.settings"].tap()
    XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    app.buttons["settings.done"].tap()
    XCTAssertTrue(app.buttons["navigation.settings"].waitForExistence(timeout: 5))
  }
  func testEmptyActivityAndMetricRanges() {
    launch("empty")
    tab("Activity")
    XCTAssertEqual(app.staticTexts["activity.total"].label, "0 runs")
    XCTAssertTrue(app.staticTexts["No runs in this period. Imported runs will appear here."].exists)
    for range in ["3 Months", "6 Months", "Year", "Month"] { app.buttons[range].tap() }
    app.buttons["Kilometers"].tap()
    XCTAssertEqual(app.staticTexts["activity.total"].label, "0.00 km")
  }
  func testAppearanceLargeTextAndLandscape() {
    launch(appearance: "dark", largeText: true)
    tab("Activity")
    XCTAssertTrue(app.staticTexts["activity.total"].exists)
    XCUIDevice.shared.orientation = .landscapeLeft
    XCTAssertTrue(app.staticTexts["activity.total"].waitForExistence(timeout: 5))
    let rotated = NSPredicate { _, _ in self.app.frame.width > self.app.frame.height }
    expectation(for: rotated, evaluatedWith: app)
    waitForExpectations(timeout: 5)
    add(XCTAttachment(screenshot: app.screenshot()))
    XCUIDevice.shared.orientation = .portrait
  }
  func testDashboardReviewAndApproval() {
    launch()
    openDashboard()
    XCTAssertFalse(app.buttons["dashboard.review"].isEnabled)
    app.textFields["dashboard.code"].tap()
    app.textFields["dashboard.code"].typeText("ABCDEF1234\n")
    app.buttons["dashboard.review"].tap()
    let approve = app.buttons["dashboard.approve"]
    reveal(approve)
    XCTAssertTrue(app.staticTexts["Simulator Safari · Fixture browser"].exists)
    approve.tap()
    XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
  }
  func testDashboardExpiryAndReviewRetry() {
    launch("dashboard-expired")
    openDashboard()
    app.textFields["dashboard.code"].tap()
    app.textFields["dashboard.code"].typeText("ABCDEF1234\n")
    app.buttons["dashboard.review"].tap()
    XCTAssertTrue(app.staticTexts["dashboard.message"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["dashboard.message"].label.contains("expired"))
    app.terminate()
    launch("dashboard-review-failure")
    openDashboard()
    app.textFields["dashboard.code"].tap()
    app.textFields["dashboard.code"].typeText("ABCDEF1234\n")
    app.buttons["dashboard.review"].tap()
    XCTAssertTrue(app.staticTexts["dashboard.message"].waitForExistence(timeout: 5))
    app.buttons["dashboard.review"].tap()
    reveal(app.buttons["dashboard.approve"])
  }
  func testDashboardApprovalRetry() {
    launch("dashboard-approval-failure")
    openDashboard()
    app.textFields["dashboard.code"].tap()
    app.textFields["dashboard.code"].typeText("ABCDEF1234\n")
    app.buttons["dashboard.review"].tap()
    reveal(app.buttons["dashboard.approve"])
    app.buttons["dashboard.approve"].tap()
    XCTAssertTrue(app.staticTexts["dashboard.message"].waitForExistence(timeout: 5))
    app.buttons["dashboard.approve"].tap()
    XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
  }
  func testAccessibilityAudit() throws {
    launch("empty")
    tab("Activity")
    try app.performAccessibilityAudit(for: [.contrast, .textClipped, .sufficientElementDescription]) { issue in
      guard issue.auditType == .contrast, let element = issue.element else { return false }
      let bar = self.app.tabBars.firstMatch
      // The audit also inspects scroll content behind or below the glass tab bar.
      // Fully visible content above the bar must pass without exceptions.
      return bar.exists && bar.frame.minY > self.app.frame.midY && element.frame.maxY > bar.frame.minY
    }
  }
  func testReducedMotionAndTransparency() throws {
    let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
    func navigate(_ section: String, toggle: String) -> XCUIElement {
      settings.terminate()
      settings.launch()
      for _ in 0..<6 {
        if settings.descendants(matching: .any)["Accessibility"].firstMatch.exists { break }
        let back = settings.navigationBars.buttons.firstMatch
        if back.exists { back.tap() } else { break }
      }
      let accessibility = settings.descendants(matching: .any)["Accessibility"].firstMatch
      for _ in 0..<10 {
        if accessibility.exists && accessibility.isHittable { break }
        settings.swipeUp()
      }
      XCTAssertTrue(accessibility.exists)
      accessibility.tap()
      settings.descendants(matching: .any)[section].firstMatch.tap()
      let control = settings.switches[toggle].firstMatch
      XCTAssertTrue(control.waitForExistence(timeout: 5))
      return control
    }
    let motion = navigate("Motion", toggle: "Reduce Motion")
    let originalMotion = motion.value as? String ?? "0"
    defer {
      let control = navigate("Motion", toggle: "Reduce Motion")
      if control.value as? String != originalMotion { control.tap() }
      settings.terminate()
    }
    if originalMotion == "0" { motion.tap() }
    let transparency = navigate("Display & Text Size", toggle: "Reduce Transparency")
    let originalTransparency = transparency.value as? String ?? "0"
    defer {
      let control = navigate("Display & Text Size", toggle: "Reduce Transparency")
      if control.value as? String != originalTransparency { control.tap() }
    }
    if originalTransparency == "0" { transparency.tap() }
    launch()
    tab("Activity")
    XCTAssertEqual(app.staticTexts["activity.total"].label, "3 runs")
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "Reduced motion and transparency"
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }

}
