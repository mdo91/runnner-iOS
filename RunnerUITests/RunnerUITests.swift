import XCTest

@MainActor final class RunnerUITests: XCTestCase {
  private var app: XCUIApplication!
  private let testID = UUID().uuidString
  override func setUpWithError() throws { continueAfterFailure = false }
  override func tearDownWithError() throws {
    if let app {
      let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
      shot.name = name
      shot.lifetime = .keepAlways
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
      let upwards = !element.exists || element.frame.midY >= app.frame.midY
      let edge = min(app.frame.width, app.frame.height) > 600 ? 0.98 : 0.92
      app.coordinate(
        withNormalizedOffset: CGVector(
          dx: edge, dy: upwards ? (app.keyboards.firstMatch.exists ? 0.55 : 0.8) : 0.3)
      ).press(
        forDuration: 0.05,
        thenDragTo: app.coordinate(
          withNormalizedOffset: CGVector(
            dx: edge, dy: upwards ? 0.3 : (app.keyboards.firstMatch.exists ? 0.55 : 0.8))))
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
    app.buttons["Distance"].tap()
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
    reveal(app.buttons["activity.customDates"])
    app.buttons["activity.customDates"].tap()
    XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
    app.buttons["Cancel"].tap()
    let landscape = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    landscape.name = "Dark large-text landscape"
    landscape.lifetime = .keepAlways
    add(landscape)
    XCUIDevice.shared.orientation = .portrait
    let restored = NSPredicate { _, _ in self.app.frame.height > self.app.frame.width }
    expectation(for: restored, evaluatedWith: app)
    waitForExpectations(timeout: 5)
    tab("Latest")
    tab("Activity")
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
  func testFixtureConsentAnalysisAndCloudDeleteStayIsolated() {
    launch()
    app.buttons["navigation.settings"].tap()
    let adult = app.switches["settings.adult"]
    reveal(adult)
    adult.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
    XCTAssertEqual(adult.value as? String, "1")
    let consent = app.switches["settings.aiConsent"]
    reveal(consent)
    XCTAssertTrue(consent.isEnabled)
    consent.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
    XCTAssertEqual(consent.value as? String, "1")
    reveal(app.buttons["settings.deleteCloudHistory"])
    app.buttons["settings.deleteCloudHistory"].tap()
    let confirm = app.buttons["settings.confirmDeleteCloudHistory"].firstMatch
    XCTAssertTrue(confirm.waitForExistence(timeout: 5))
    confirm.tap()
    XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    app.buttons["settings.done"].tap()
    reveal(app.buttons["run.analyze"])
    app.buttons["run.analyze"].tap()
    tab("Activity")
    XCTAssertEqual(app.staticTexts["activity.total"].label, "3 runs")
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
    try app.performAccessibilityAudit(for: [.contrast, .textClipped, .sufficientElementDescription])
    { issue in
      guard issue.auditType == .contrast, let element = issue.element else { return false }
      let bar = self.app.tabBars.firstMatch
      // The audit also inspects scroll content behind or below the glass tab bar.
      // Fully visible content above the bar must pass without exceptions.
      return bar.exists && bar.frame.minY > self.app.frame.midY
        && element.frame.maxY > bar.frame.minY
    }
  }
  func testVolumeRangesMetricsAndBucketDrilldown() {
    launch()
    tab("Activity")
    for (range, total) in [
      ("3 Months", "7 runs"), ("6 Months", "8 runs"), ("Year", "9 runs"), ("Month", "3 runs"),
    ] {
      app.buttons[range].tap()
      XCTAssertEqual(app.staticTexts["activity.total"].label, total)
    }
    app.buttons["Distance"].tap()
    XCTAssertEqual(app.staticTexts["activity.total"].label, "15.00 km")
    app.buttons["Moving Time"].tap()
    XCTAssertEqual(app.staticTexts["activity.total"].label, "1:16:30")
    app.buttons["Elevation Gain"].tap()
    XCTAssertFalse(app.staticTexts["activity.total"].label.contains("—"))
    app.buttons["Runs"].tap()
    reveal(app.buttons["activity.chartData"])
    app.buttons["activity.chartData"].tap()
    reveal(app.buttons["activity.bucket.8"])
    app.buttons["activity.bucket.8"].tap()
    XCTAssertTrue(app.staticTexts["activity.selection"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["activity.selection"].label.contains("1 runs"))
    app.buttons["activity.viewRuns"].tap()
    XCTAssertTrue(app.staticTexts["explorer.count"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.staticTexts["explorer.count"].label, "1 runs")
    app.buttons["explorer.done"].tap()
    reveal(app.buttons["activity.customDates"])
    app.buttons["activity.customDates"].tap()
    app.buttons["activity.applyDates"].tap()
    XCTAssertEqual(app.staticTexts["activity.total"].label, "3 runs")
  }
  func testCalendarAndHistoryFilters() {
    launch("indoor")
    tab("Activity")
    reveal(app.buttons["calendar.day.8"])
    app.buttons["calendar.day.8"].tap()
    XCTAssertTrue(app.staticTexts["explorer.count"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.staticTexts["explorer.count"].label, "1 runs")
    app.buttons["explorer.done"].tap()
    app.buttons["calendar.previous"].tap()
    XCTAssertTrue(app.staticTexts["calendar.month"].label.contains("September"))
    app.buttons["calendar.next"].tap()
    XCTAssertTrue(app.staticTexts["calendar.month"].label.contains("October"))
    tab("History")
    reveal(app.buttons["Indoor"])
    app.buttons["Indoor"].tap()
    XCTAssertEqual(app.staticTexts["history.count"].label, "1 runs")
    app.buttons["Outdoor"].tap()
    XCTAssertEqual(app.staticTexts["history.count"].label, "5 runs")
    app.buttons["history.reset"].tap()
    app.buttons["Pace"].tap()
    let latest = app.buttons["history.run.00000000-0000-0000-0000-000000000001"]
    reveal(latest)
    latest.tap()
    XCTAssertTrue(app.navigationBars["Run Details"].waitForExistence(timeout: 5))
  }
  func testLinkedSamplesSplitsAndMissingSensors() {
    launch("paused")
    reveal(app.buttons["run.samples"])
    app.buttons["run.samples"].tap()
    app.buttons["run.sample.0"].tap()
    XCTAssertTrue(app.staticTexts["run.selection"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["run.selection"].label.contains("5:00"))
    reveal(app.buttons["run.split.1"])
    app.buttons["run.split.1"].tap()
    XCTAssertTrue(app.staticTexts["run.splitSelection"].exists)
    app.terminate()
    launch("partial")
    reveal(app.buttons["run.metric"])
    app.buttons["run.metric"].tap()
    app.buttons["Power"].tap()
    XCTAssertTrue(app.staticTexts["run.unavailable"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["run.unavailable"].label.contains("power"))
  }
  func testGoalsCreateEditPersistAndDelete() {
    launch()
    tab("Activity")
    reveal(app.buttons["goal.add"])
    app.buttons["goal.add"].tap()
    let target = app.textFields["goal.target"]
    XCTAssertTrue(target.waitForExistence(timeout: 5))
    target.tap()
    target.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 6))
    XCTAssertFalse(app.buttons["goal.save"].isEnabled)
    target.typeText("10\n")
    XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
    reveal(app.buttons["goal.save"])
    app.buttons["goal.save"].tap()
    XCTAssertTrue(app.buttons["goal.save"].waitForNonExistence(timeout: 5))
    let edit = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'goal.edit.'"))
      .firstMatch
    XCTAssertTrue(edit.waitForExistence(timeout: 5))
    XCTAssertTrue(edit.label.contains("10.00 km"))
    app.terminate()
    launch()
    tab("Activity")
    let persisted = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'goal.edit.'"))
      .firstMatch
    reveal(persisted)
    XCTAssertTrue(persisted.label.contains("10.00 km"))
    persisted.tap()
    let editTarget = app.textFields["goal.target"]
    editTarget.tap()
    editTarget.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 6) + "15\n")
    XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
    reveal(app.buttons["goal.save"])
    app.buttons["goal.save"].tap()
    XCTAssertTrue(persisted.label.contains("15.00 km"))
    persisted.tap()
    app.buttons["goal.delete"].tap()
    XCTAssertFalse(
      app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'goal.edit.'")).firstMatch
        .exists)
  }
  func testZonesAndCompleteVersusIncompleteLoad() {
    launch()
    app.buttons["navigation.settings"].tap()
    reveal(app.buttons["settings.zones"])
    app.buttons["settings.zones"].tap()
    XCTAssertFalse(app.buttons["zones.save"].isEnabled)
    let maximum = app.textFields["zones.maximum"]
    maximum.tap()
    maximum.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4) + "190")
    app.buttons["zones.generate"].tap()
    app.buttons["zones.keyboardDone"].tap()
    reveal(app.buttons["zones.save"])
    app.buttons["zones.save"].tap()
    app.buttons["settings.done"].tap()
    tab("Trends")
    reveal(app.staticTexts["load.total.7"])
    XCTAssertFalse(app.staticTexts["load.total.7"].label.contains("unavailable"))
    XCTAssertTrue(app.otherElements["zones.total.3"].exists || app.staticTexts["Zone 3"].exists)
    app.terminate()
    launch("partial")
    tab("Trends")
    reveal(app.staticTexts["load.total.7"])
    XCTAssertTrue(app.staticTexts["load.total.7"].label.contains("unavailable"))
  }
  func testBestEffortExclusionAndRepeatedRouteNavigation() {
    launch("repeated-route")
    tab("Trends")
    reveal(app.staticTexts["bests.annual"])
    XCTAssertEqual(app.staticTexts["bests.annual"].label, "2026 best: 25:00")
    XCTAssertTrue(app.buttons["bests.year"].exists)
    reveal(app.buttons["bests.rank.1"])
    let original = app.buttons["bests.rank.1"].label
    app.buttons["bests.exclude.1"].tap()
    XCTAssertNotEqual(app.buttons["bests.rank.1"].label, original)
    app.buttons["bests.restore"].tap()
    XCTAssertEqual(app.buttons["bests.rank.1"].label, original)
    app.buttons["bests.rank.1"].tap()
    XCTAssertEqual(app.staticTexts["explorer.count"].label, "1 runs")
    app.buttons["explorer.done"].tap()
    tab("Latest")
    reveal(app.buttons["route.runs"])
    XCTAssertEqual(app.staticTexts["route.completions"].label, "9 completions")
    app.buttons["route.runs"].tap()
    XCTAssertTrue(app.staticTexts["explorer.count"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.staticTexts["explorer.count"].label, "9 runs")
  }
  func testAppOwnedScreenAccessibility() throws {
    launch("empty")
    for name in ["Latest", "History", "Trends", "Live"] {
      tab(name)
      try app.performAccessibilityAudit(for: [
        .contrast, .textClipped, .sufficientElementDescription,
      ]) { issue in
        guard issue.auditType == .contrast, let element = issue.element else { return false }
        let bar = self.app.tabBars.firstMatch
        return bar.exists && bar.frame.minY > self.app.frame.midY
          && element.frame.maxY > bar.frame.minY
      }
      let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
      image.name = name
      image.lifetime = .keepAlways
      add(image)
    }
    tab("Latest")
    app.buttons["navigation.settings"].tap()
    try app.performAccessibilityAudit(for: [.contrast, .textClipped, .sufficientElementDescription])
    { issue in
      return false
    }
  }
  func testRecordedChartsAndDistanceAxes() {
    launch()
    reveal(app.buttons["run.metric"])
    for metric in [
      "Pace", "Heart rate", "Elevation", "Power", "Stride length", "Ground contact",
      "Vertical oscillation",
    ] {
      app.buttons["run.metric"].tap()
      app.collectionViews.buttons[metric].firstMatch.tap()
      XCTAssertFalse(app.staticTexts["run.unavailable"].exists)
      app.buttons["Distance"].tap()
      reveal(app.buttons["run.samples"])
      app.buttons["run.samples"].tap()
      app.buttons["run.sample.0"].tap()
      XCTAssertTrue(app.staticTexts["run.selection"].exists)
      app.buttons["Elapsed time"].tap()
      reveal(app.buttons["run.metric"])
    }
  }
  func testHistorySourceAndDistanceFilters() {
    launch("mixed-source")
    tab("History")
    reveal(app.buttons["history.source"])
    app.buttons["history.source"].tap()
    app.buttons["Fixture Garmin"].tap()
    XCTAssertEqual(app.staticTexts["history.count"].label, "2 runs")
    let minimum = app.textFields["history.minimum"]
    minimum.tap()
    minimum.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 5) + "6")
    app.buttons["history.source"].tap()
    app.buttons["Fixture Garmin"].tap()
    XCTAssertEqual(app.staticTexts["history.count"].label, "0 runs")
    app.buttons["history.reset"].tap()
    XCTAssertEqual(app.staticTexts["history.count"].label, "6 runs")
    app.buttons["history.customDates"].tap()
    app.buttons["activity.applyDates"].tap()
    XCTAssertEqual(app.staticTexts["history.count"].label, "6 runs")
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
    let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    screenshot.name = "Reduced motion and transparency"
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }

}
