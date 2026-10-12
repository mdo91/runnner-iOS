import UIKit
import XCTest

@MainActor final class RunnerUITests: XCTestCase {
  private var app: XCUIApplication!
  private let testID = UUID().uuidString
  override func setUpWithError() throws { continueAfterFailure = false }
  override func tearDownWithError() throws {
    if let app {
      let screenshot = XCUIScreen.main.screenshot()
      let shot = XCTAttachment(screenshot: screenshot)
      shot.name = name
      shot.lifetime = .keepAlways
      add(shot)
      // Keep a direct copy when a toolchain cannot decode older-runtime attachments.
      try? screenshot.pngRepresentation.write(to: evidenceURL("png"))
      try? app.debugDescription.write(to: evidenceURL("txt"), atomically: true, encoding: .utf8)
      app.terminate()
    }
    XCUIDevice.shared.orientation = .portrait
  }
  private func evidenceURL(_ suffix: String) -> URL {
    let directory = URL(
      fileURLWithPath:
        ProcessInfo.processInfo.environment["RUNNER_EVIDENCE_DIR"]
        ?? "/tmp/runner-ui-results/direct-screenshots", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let filename = name.map { $0.isLetter || $0.isNumber ? $0 : "_" }
    return directory.appendingPathComponent("\(String(filename)).\(testID).\(suffix)")
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
      "RUNNER_LARGE_TEXT": largeText ? "1" : "0", "TZ": "America/Los_Angeles",
    ]
    app.launch()
    XCTAssertTrue(app.buttons["Activity"].firstMatch.waitForExistence(timeout: 15))
    let ready = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "exists == true AND value == %@", "Fixtures ready"),
      object: app.buttons["navigation.settings"])
    XCTAssertEqual(
      XCTWaiter.wait(for: [ready], timeout: 30), .completed,
      "Fixture analytics did not finish loading")
    return app
  }
  private func tab(_ name: String) {
    let button = app.buttons[name].firstMatch
    XCTAssertTrue(button.waitForExistence(timeout: 5))
    button.tap()
  }
  private func waitForLabel(_ element: XCUIElement, containing text: String) {
    let predicate = NSPredicate(format: "exists == true AND label CONTAINS %@", text)
    let ready = XCTNSPredicateExpectation(predicate: predicate, object: element)
    XCTAssertEqual(
      XCTWaiter.wait(for: [ready], timeout: 10), .completed,
      "Expected \(element) to contain \(text)")
  }
  private func waitForUnobscuredScreen() {
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    let banner = springboard.descendants(matching: .any)
      .matching(identifier: "NotificationShortLookView").firstMatch
    XCTAssertTrue(
      banner.waitForNonExistence(timeout: 15),
      "A system notification obscures the accessibility audit")
  }
  private func reveal(_ element: XCUIElement, towardTop: Bool = false, limit: Int = 12) {
    for _ in 0..<limit {
      let window = app.windows.firstMatch
      let bar = app.tabBars.firstMatch
      let scroll = app.scrollViews.firstMatch
      let bounds = scroll.exists && scroll.isHittable
        ? scroll.frame.intersection(window.frame) : window.frame
      let navigation = app.navigationBars.firstMatch
      let top = max(bounds.minY, navigation.exists ? navigation.frame.maxY : bounds.minY) + 8
      var bottom = bounds.maxY - 8
      if bar.exists && bar.isHittable && bar.frame.minY > window.frame.midY {
        bottom = min(bottom, bar.frame.minY - 8)
      }
      let keyboard = app.keyboards.firstMatch
      if keyboard.exists { bottom = min(bottom, keyboard.frame.minY - 8) }
      if element.exists && element.isHittable && element.frame.minY >= top
        && element.frame.maxY <= bottom { return }
      guard bottom > top else {
        XCTFail("No visible area available for scrolling")
        return
      }
      let upwards = element.exists ? element.frame.midY >= (top + bottom) / 2 : !towardTop
      let edge = min(window.frame.width, window.frame.height) > 600 ? 0.98 : 0.92
      let start = top + (bottom - top) * (upwards ? 0.8 : 0.2)
      let end = top + (bottom - top) * (upwards ? 0.2 : 0.8)
      let origin = window.coordinate(withNormalizedOffset: .zero)
      origin.withOffset(CGVector(dx: window.frame.width * edge, dy: start - window.frame.minY))
        .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(
          dx: window.frame.width * edge, dy: end - window.frame.minY)))
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
  private func openRunPhoto() {
    let button = app.buttons["run.createPhoto"]
    reveal(button)
    button.tap()
    XCTAssertTrue(app.navigationBars["Run Photo"].waitForExistence(timeout: 5))
  }
  private var photoArtwork: XCUIElement {
    app.descendants(matching: .any)["photo.artwork"].firstMatch
  }
  private func revealPhotoControl(_ element: XCUIElement, towardTop: Bool = false) {
    let scroll = app.scrollViews["photo.controls"]
    let window = app.windows.firstMatch
    for _ in 0..<16 {
      // The application frame can retain portrait bounds after iPad rotation.
      let windowFrame = window.frame
      let frame = scroll.frame.intersection(windowFrame)
      guard !frame.isNull, !frame.isEmpty else {
        XCTFail("Photo controls have no visible window bounds")
        return
      }
      let top = max(frame.minY, app.navigationBars["Run Photo"].frame.maxY) + 8
      let bottom = min(frame.maxY, app.buttons["photo.save"].frame.minY) - 12
      if element.exists && element.frame.minY >= top && element.frame.maxY <= bottom
        && element.isHittable
      {
        return
      }
      let origin = window.coordinate(withNormalizedOffset: .zero)
      let scrollToBeginning = element.exists ? element.frame.midY < (top + bottom) / 2 : towardTop
      var startY = scrollToBeginning ? top + 20 : bottom - 20
      let slider = app.sliders["photo.size"]
      if slider.exists && slider.frame.contains(CGPoint(x: frame.midX, y: startY)) {
        // Start on the Size/Zoom label above the slider, which otherwise consumes the drag.
        startY = max(top + 8, slider.frame.minY - 24)
      }
      let start = origin.withOffset(
        CGVector(
          dx: frame.midX - windowFrame.minX,
          dy: startY - windowFrame.minY))
      let step = min(100, (bottom - top) * 0.45)
      let destination = start.withOffset(
        CGVector(dx: 0, dy: scrollToBeginning ? step : -step))
      start.press(
        forDuration: 0.05, thenDragTo: destination,
        withVelocity: .slow, thenHoldForDuration: 0.2)
    }
    let bounds = scroll.frame.intersection(window.frame)
    XCTAssertTrue(
      element.exists && element.frame.minY >= bounds.minY
        && element.frame.maxY <= min(bounds.maxY, app.buttons["photo.save"].frame.minY) - 12
        && element.isHittable,
      "Could not fully reveal editor control \(element)")
  }
  private func photoFormat(_ label: String) {
    let format = app.buttons["photo.format"]
    revealPhotoControl(format, towardTop: true)
    format.tap()
    app.buttons[label].firstMatch.tap()
  }
  private func photoLayer(_ label: String) {
    let picker = app.buttons["photo.layer"]
    revealPhotoControl(picker, towardTop: true)
    picker.tap()
    app.buttons[label].firstMatch.tap()
  }
  func testYellowDashboardAppearanceAndMetricLayout() throws {
    launch(appearance: "light")
    let summary = app.descendants(matching: .any)["run.summary"].firstMatch
    let time = app.descendants(matching: .any)["run.movingTime"].firstMatch
    let pace = app.descendants(matching: .any)["run.averagePace"].firstMatch
    let heart = app.descendants(matching: .any)["run.heartRate"].firstMatch
    XCTAssertTrue(time.waitForExistence(timeout: 5))
    XCTAssertEqual(time.frame.minY, pace.frame.minY, accuracy: 1)
    XCTAssertGreaterThan(pace.frame.minX, time.frame.minX)
    if summary.frame.width - 32 >= 720 {
      XCTAssertEqual(time.frame.minY, heart.frame.minY, accuracy: 1)
    } else {
      XCTAssertGreaterThan(heart.frame.minY, time.frame.minY)
    }
    let colors = try dashboardColors()
    XCTAssertGreaterThan(
      colors.darkFraction, 0.5, "The production dark theme overrides a light fixture request")
    XCTAssertGreaterThan(colors.yellowPixels, 100, "The visible dashboard uses sporty yellow")
    let photo = app.buttons["run.createPhoto"]
    XCTAssertGreaterThanOrEqual(photo.frame.width, 44)
    XCTAssertGreaterThanOrEqual(photo.frame.height, 44)
    assertDarkTabBar()
    captureDashboard("latest")
    for (name, label) in [("Activity", "Every run adds up"), ("Trends", "Built one run at a time"),
      ("Live", "Open Runner on Watch")]
    {
      tab(name)
      XCTAssertTrue(app.descendants(matching: .any)[label].firstMatch.waitForExistence(timeout: 5))
      assertDarkTabBar()
      captureDashboard(name.lowercased())
    }
    tab("History")
    let journal = app.staticTexts["Run journal"]
    XCTAssertTrue(journal.waitForExistence(timeout: 5))
    assertDarkTabBar()
    captureDashboard("history")
    let run = app.buttons["history.run.00000000-0000-0000-0000-000000000001"]
    reveal(run)
    run.tap()
    XCTAssertTrue(app.navigationBars["Run Details"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["run.createPhoto"].exists)
    assertDarkTabBar()
    if app.windows.firstMatch.frame.width >= 700 {
      XCUIDevice.shared.orientation = .landscapeLeft
      let wide = NSPredicate { _, _ in
        self.app.windows.firstMatch.frame.width > self.app.windows.firstMatch.frame.height
      }
      XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: wide, object: app)],
        timeout: 5), .completed)
      XCTAssertGreaterThan(app.staticTexts["Your route"].frame.minX, summary.frame.maxX)
      XCTAssertEqual(time.frame.minY, pace.frame.minY, accuracy: 1)
      XCTAssertGreaterThan(heart.frame.minY, time.frame.minY)
      captureDashboard("landscape")
    }
  }

  private func assertDarkTabBar() {
    // Native dark glass can be lighter than the app's solid charcoal surfaces.
    // Keep it below mid-gray; the former light bar was above 200 per channel.
    let darkBar = NSPredicate { _, _ in
      let bar = self.app.tabBars.firstMatch
      let bounds: CGRect
      if bar.exists {
        bounds = bar.frame
      } else {
        // iPad exposes its top tabs as buttons rather than a TabBar element.
        let tabs = ["Latest", "History", "Activity", "Trends", "Live"].map {
          self.app.buttons[$0].firstMatch
        }
        guard tabs.allSatisfy({ $0.exists }) else { return false }
        bounds = tabs.reduce(CGRect.null) { $0.union($1.frame) }.insetBy(dx: -4, dy: -4)
      }
      return ((try? self.dashboardColors(in: bounds, darkLimit: 128).darkFraction) ?? 0) > 0.5
    }
    XCTAssertEqual(
      XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: darkBar, object: app)], timeout: 5),
      .completed, "The tab bar stays dark after the navigation transition")
  }

  private func captureDashboard(_ name: String) {
    let screenshot = XCUIScreen.main.screenshot()
    let attachment = XCTAttachment(screenshot: screenshot)
    attachment.name = "Yellow dashboard - \(name)"
    attachment.lifetime = .keepAlways
    add(attachment)
    try? screenshot.pngRepresentation.write(to: evidenceURL("\(name).png"))
  }

  func testYellowDashboardLargeTextReflowsAndStaysAccessible() throws {
    launch(appearance: "light", largeText: true)
    let time = app.descendants(matching: .any)["run.movingTime"].firstMatch
    let pace = app.descendants(matching: .any)["run.averagePace"].firstMatch
    XCTAssertTrue(time.waitForExistence(timeout: 5))
    XCTAssertEqual(time.frame.minX, pace.frame.minX, accuracy: 1)
    XCTAssertGreaterThan(pace.frame.minY, time.frame.maxY)
    waitForUnobscuredScreen()
    try app.performAccessibilityAudit(for: [.contrast, .textClipped, .sufficientElementDescription])
    { issue in
      guard issue.auditType == .contrast, let element = issue.element else { return false }
      let bar = self.app.tabBars.firstMatch
      return bar.exists && element.frame.maxY > bar.frame.minY
    }
    XCUIDevice.shared.orientation = .landscapeLeft
    XCTAssertTrue(app.buttons["run.createPhoto"].waitForExistence(timeout: 5))
    XCTAssertEqual(time.frame.minX, pace.frame.minX, accuracy: 1)
    XCTAssertGreaterThan(pace.frame.minY, time.frame.maxY)
  }

  private func dashboardColors(in rect: CGRect? = nil, darkLimit: UInt8 = 80) throws -> (darkFraction: Double, yellowPixels: Int) {
    let screenshot = XCUIScreen.main.screenshot().image
    var image = try XCTUnwrap(screenshot.cgImage)
    if let rect {
      // XCTest screenshots may expose scale == 1 despite containing Retina pixels.
      let window = app.windows.firstMatch.frame
      image = try XCTUnwrap(image.cropping(to: rect.applying(CGAffineTransform(
        scaleX: CGFloat(image.width) / window.width,
        y: CGFloat(image.height) / window.height))))
    }
    let width = image.width
    let height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
    try pixels.withUnsafeMutableBytes { buffer in
      let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    var dark = 0
    var yellow = 0
    for index in stride(from: 0, to: pixels.count, by: 4) {
      if max(pixels[index], pixels[index + 1], pixels[index + 2]) < darkLimit { dark += 1 }
      if pixels[index] > 160 && pixels[index + 1] > 220 && pixels[index + 2] < 60 { yellow += 1 }
    }
    return (Double(dark) / Double(width * height), yellow)
  }

  func testRunPhotoEditorGesturesRouteCropAndExport() {
    launch()
    openRunPhoto()
    XCTAssertTrue(photoArtwork.waitForExistence(timeout: 5))
    XCTAssertTrue(photoArtwork.label.contains("5.00 km"))
    XCTAssertTrue(photoArtwork.label.contains("25m 00s"))
    let stats = app.buttons["photo.statsOverlay"]
    let original = stats.value as? String
    let originalFrame = stats.frame
    stats.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(
      forDuration: 0.05,
      thenDragTo: stats.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.15)))
    XCTAssertNotEqual(stats.value as? String, original)
    XCTAssertEqual(stats.frame.midX - originalFrame.midX, originalFrame.width * 0.2, accuracy: 8)
    XCTAssertEqual(stats.frame.midY - originalFrame.midY, -originalFrame.height * 0.35, accuracy: 8)
    let statsBeforeResize = stats.value as? String
    stats.pinch(withScale: 0.8, velocity: -1)
    XCTAssertNotEqual(stats.value as? String, statsBeforeResize)
    let movedStats = stats.value as? String
    let toggle = app.switches["photo.routeToggle"]
    revealPhotoControl(toggle)
    toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
    let route = app.buttons["photo.routeOverlay"]
    XCTAssertTrue(route.waitForExistence(timeout: 5))
    let before = route.value as? String
    route.pinch(withScale: 0.7, velocity: -1)
    XCTAssertNotEqual(route.value as? String, before)
    XCTAssertEqual(stats.value as? String, movedStats)
    let routeFrame = route.frame
    route.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(
      forDuration: 0.05,
      thenDragTo: route.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.7)))
    XCTAssertEqual(route.frame.midX - routeFrame.midX, -routeFrame.width * 0.2, accuracy: 8)
    XCTAssertEqual(route.frame.midY - routeFrame.midY, routeFrame.height * 0.2, accuracy: 8)
    XCTAssertEqual(stats.value as? String, movedStats)
    let right = app.buttons["photo.arrow.right"]
    revealPhotoControl(right, towardTop: true)
    let routeBeforeMove = route.value as? String
    right.tap()
    XCTAssertNotEqual(route.value as? String, routeBeforeMove)
    photoFormat("Story 9:16")
    photoLayer("Crop")
    let zoom = app.sliders["photo.size"]
    revealPhotoControl(zoom)
    zoom.adjust(toNormalizedSliderPosition: 0.4)
    let crop = app.descendants(matching: .any)["photo.cropCanvas"].firstMatch
    crop.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(
      forDuration: 0.05,
      thenDragTo: crop.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.6)))
    app.buttons["photo.save"].tap()
    XCTAssertTrue(app.alerts["Image saved"].waitForExistence(timeout: 10))
    XCTAssertFalse(
      app.buttons["photo.save"].exists, "Save closes the editor before showing its receipt")
    app.alerts.buttons["Share Image"].tap()
    let complete = app.buttons["photo.fixtureShare.complete"]
    XCTAssertTrue(complete.waitForExistence(timeout: 5))
    XCTAssertFalse(app.alerts["Image shared"].exists)
    complete.tap()
    XCTAssertTrue(app.alerts["Image shared"].waitForExistence(timeout: 5))
    app.alerts.buttons["OK"].tap()
    XCTAssertTrue(app.buttons["run.createPhoto"].waitForExistence(timeout: 5))
  }
  func testRunPhotoUsesHistoricalSessionAndMissingGPS() {
    launch()
    tab("History")
    let older = app.buttons["history.run.00000000-0000-0000-0000-000000000002"]
    reveal(older)
    older.tap()
    openRunPhoto()
    XCTAssertTrue(photoArtwork.waitForExistence(timeout: 5))
    XCTAssertTrue(photoArtwork.label.contains("25m 30s"))
    app.terminate()
    launch("indoor")
    openRunPhoto()
    let toggle = app.switches["photo.routeToggle"]
    revealPhotoControl(toggle)
    XCTAssertFalse(toggle.isEnabled)
    XCTAssertTrue(photoArtwork.label.contains("25m 00s"))
    app.buttons["photo.save"].tap()
    XCTAssertTrue(app.alerts["Image saved"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.buttons["photo.save"].exists)
  }
  func testRunPhotoLoadRetryAndSaveDenialKeepEdits() {
    launch("photo-load-failure")
    openRunPhoto()
    XCTAssertTrue(app.alerts["Couldn’t finish"].waitForExistence(timeout: 5))
    app.alerts.buttons["Retry"].tap()
    XCTAssertTrue(photoArtwork.waitForExistence(timeout: 5))
    app.terminate()
    launch("photo-save-denied")
    openRunPhoto()
    let up = app.buttons["photo.arrow.up"]
    revealPhotoControl(up)
    up.tap()
    let before = app.buttons["photo.statsOverlay"].value as? String
    app.buttons["photo.save"].tap()
    XCTAssertTrue(app.alerts["Couldn’t finish"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.alerts.buttons["Open Settings"].exists)
    app.alerts.buttons["Share Instead"].tap()
    let cancel = app.buttons["photo.fixtureShare.cancel"]
    XCTAssertTrue(cancel.waitForExistence(timeout: 5))
    cancel.tap()
    XCTAssertTrue(app.buttons["photo.share"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.buttons["photo.statsOverlay"].value as? String, before)
    XCTAssertFalse(
      app.alerts["Image shared"].exists, "Cancellation must not claim a completed share")
    XCTAssertTrue(app.buttons["photo.share"].isEnabled)
    app.buttons["photo.share"].tap()
    XCTAssertTrue(app.buttons["photo.fixtureShare.complete"].waitForExistence(timeout: 5))
    app.buttons["photo.fixtureShare.fail"].tap()
    XCTAssertTrue(app.alerts["Couldn’t finish"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.alerts["Image shared"].exists)
    app.alerts.buttons["Retry"].tap()
    XCTAssertTrue(app.buttons["photo.fixtureShare.complete"].waitForExistence(timeout: 5))
    app.buttons["photo.fixtureShare.complete"].tap()
    XCTAssertTrue(app.alerts["Image shared"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["photo.save"].exists)
  }
  func testRunPhotoAccessibilityAndLandscape() throws {
    launch(appearance: "dark", largeText: true)
    openRunPhoto()
    XCTAssertTrue(photoArtwork.waitForExistence(timeout: 5))
    let serif = app.buttons["photo.font.serif"]
    revealPhotoControl(serif)
    serif.tap()
    XCTAssertEqual(
      app.buttons["photo.font.sport"].frame.minX,
      app.buttons["photo.font.clean"].frame.minX, accuracy: 1,
      "Accessibility text sizes use one font-preview column in the full-screen editor")
    let icon = app.switches["photo.iconToggle"]
    revealPhotoControl(icon)
    icon.switches.firstMatch.exists ? icon.switches.firstMatch.tap() : icon.tap()
    let routeToggle = app.switches["photo.routeToggle"]
    revealPhotoControl(routeToggle, towardTop: true)
    routeToggle.switches.firstMatch.exists
      ? routeToggle.switches.firstMatch.tap() : routeToggle.tap()
    XCUIDevice.shared.orientation = .landscapeLeft
    let reset = app.buttons["photo.reset"]
    revealPhotoControl(reset, towardTop: true)
    reset.tap()
    photoLayer("Stats")
    XCTAssertTrue(app.buttons["photo.save"].isHittable)
    XCTAssertTrue(app.buttons["photo.close"].isHittable)
    XCTAssertTrue(photoArtwork.exists)
    // The artwork intentionally has fixed typography; accessible controls carry the same data.
    waitForUnobscuredScreen()
    revealPhotoControl(app.buttons["photo.font.mono"])
    try auditPhotoControls()
    photoLayer("Route")
    let yellow = app.buttons["photo.routeColor.runnerYellow"]
    revealPhotoControl(yellow, towardTop: true)
    XCTAssertEqual(app.buttons["photo.routeColor.white"].frame.minX, yellow.frame.minX, accuracy: 1)
    yellow.tap()
    try auditPhotoControls()
  }
  private func auditPhotoControls() throws {
    let artwork = photoArtwork.frame
    let scroll = app.scrollViews["photo.controls"].frame.intersection(app.windows.firstMatch.frame)
    let top = max(scroll.minY, app.navigationBars["Run Photo"].frame.maxY)
    let visible = CGRect(
      x: scroll.minX, y: top, width: scroll.width,
      height: max(0, app.buttons["photo.save"].frame.minY - 12 - top))
    try app.performAccessibilityAudit(for: [
      .contrast, .elementDetection, .hitRegion, .sufficientElementDescription,
    ]) { issue in
      // The scalable photo artwork contains user-selected backgrounds, not UI text.
      // Its complete metrics are exposed as one accessibility label; audit all controls.
      if issue.auditType == .contrast, let element = issue.element {
        let frame = element.frame
        if artwork.contains(frame) { return true }
        // iOS 26 audits offscreen ScrollView descendants beneath the fixed footer.
        // Hidden content has no visible text contrast; font previews are revealed before auditing.
        if scroll.intersects(frame) && !visible.contains(frame) { return true }
      }
      let description =
        "\(issue.detailedDescription)\n\(issue.element?.debugDescription ?? "Unknown element")"
      try? description.write(to: self.evidenceURL("audit.txt"), atomically: true, encoding: .utf8)
      return false
    }
  }
  func testRunPhotoAlignmentFontsAndIndependentIcon() {
    launch()
    openRunPhoto()
    let stats = app.buttons["photo.statsOverlay"]
    let up = app.buttons["photo.arrow.up"]
    revealPhotoControl(up)
    for _ in 0..<5 { up.tap() }
    let position = stats.frame
    let alignment = app.segmentedControls["photo.alignment"]
    revealPhotoControl(alignment, towardTop: true)
    for label in ["Center", "Trailing", "Leading", "Center"] {
      alignment.buttons[label].tap()
      XCTAssertEqual(stats.frame.midX, position.midX, accuracy: 1)
      XCTAssertEqual(stats.frame.midY, position.midY, accuracy: 1)
    }
    for style in ["clean", "rounded", "mono", "sport", "serif"] {
      let button = app.buttons["photo.font.\(style)"]
      revealPhotoControl(button, towardTop: true)
      button.tap()
      XCTAssertEqual(button.value as? String, "Selected")
      XCTAssertEqual(stats.frame.midX, position.midX, accuracy: 1)
      XCTAssertEqual(stats.frame.midY, position.midY, accuracy: 1)
    }
    let toggle = app.switches["photo.iconToggle"]
    revealPhotoControl(toggle)
    toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
    let icon = app.buttons["photo.iconOverlay"]
    XCTAssertTrue(icon.waitForExistence(timeout: 5))
    let statsBefore = stats.value as? String
    let iconBefore = icon.value as? String
    icon.pinch(withScale: 0.75, velocity: -1)
    icon.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(
      forDuration: 0.05,
      thenDragTo: icon.coordinate(withNormalizedOffset: CGVector(dx: -0.3, dy: -0.4)))
    XCTAssertNotEqual(icon.value as? String, iconBefore)
    XCTAssertEqual(stats.value as? String, statsBefore)
    let moved = icon.value as? String
    let left = app.buttons["photo.arrow.left"]
    revealPhotoControl(left, towardTop: true)
    left.tap()
    XCTAssertNotEqual(icon.value as? String, moved)
    XCTAssertEqual(stats.value as? String, statsBefore)
    let retained = icon.value as? String
    revealPhotoControl(toggle)
    toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
    XCTAssertFalse(icon.exists)
    toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
    XCTAssertEqual(icon.value as? String, retained)
    app.buttons["photo.choose"].tap()
    XCTAssertEqual(icon.value as? String, retained)
    photoLayer("Stats")
    XCTAssertEqual(app.buttons["photo.font.serif"].value as? String, "Selected")
    XCTAssertTrue(alignment.buttons["Center"].isSelected)
    let reset = app.buttons["photo.reset"]
    revealPhotoControl(reset, towardTop: true)
    reset.tap()
    XCTAssertNotEqual(icon.value as? String, retained)
    XCTAssertTrue(icon.exists)
    XCTAssertEqual(app.buttons["photo.font.serif"].value as? String, "Selected")
    XCTAssertTrue(alignment.buttons["Center"].isSelected)
    photoFormat("Square 1:1")
    app.buttons["photo.save"].tap()
    XCTAssertTrue(app.alerts["Image saved"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.buttons["photo.save"].exists)
  }

  func testRunPhotoRouteColorsPersistWithoutMovingLayers() {
    launch()
    openRunPhoto()
    let toggle = app.switches["photo.routeToggle"]
    revealPhotoControl(toggle)
    toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
    let route = app.buttons["photo.routeOverlay"]
    XCTAssertTrue(route.waitForExistence(timeout: 5))
    let before = route.value as? String
    let statsBefore = app.buttons["photo.statsOverlay"].value as? String
    for name in [
      "white", "runnerYellow", "orange", "red", "green", "blue", "purple", "pink", "black",
    ] {
      let color = app.buttons["photo.routeColor.\(name)"]
      revealPhotoControl(color, towardTop: name == "white")
      color.tap()
      XCTAssertEqual(color.value as? String, "Selected")
      XCTAssertEqual(route.value as? String, before)
      XCTAssertEqual(app.buttons["photo.statsOverlay"].value as? String, statsBefore)
    }
    let yellow = app.buttons["photo.routeColor.runnerYellow"]
    revealPhotoControl(yellow, towardTop: true)
    yellow.tap()
    revealPhotoControl(toggle)
    toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
    XCTAssertFalse(route.exists)
    toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
    XCTAssertEqual(route.value as? String, before)
    revealPhotoControl(yellow, towardTop: true)
    XCTAssertEqual(yellow.value as? String, "Selected")
    app.buttons["photo.choose"].tap()
    XCTAssertEqual(yellow.value as? String, "Selected")
    let reset = app.buttons["photo.reset"]
    revealPhotoControl(reset, towardTop: true)
    reset.tap()
    XCTAssertEqual(yellow.value as? String, "Selected")
    app.buttons["photo.save"].tap()
    XCTAssertTrue(app.alerts["Image saved"].waitForExistence(timeout: 10))
    app.alerts.buttons["Share Image"].tap()
    XCTAssertTrue(app.buttons["photo.fixtureShare.cancel"].waitForExistence(timeout: 5))
    app.buttons["photo.fixtureShare.cancel"].tap()
    XCTAssertTrue(app.buttons["run.createPhoto"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.alerts["Image shared"].exists)
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
    assertDarkTabBar()
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
    reveal(app.staticTexts["dashboard.message"])
    waitForLabel(app.staticTexts["dashboard.message"], containing: "Approval could not finish")
    reveal(app.buttons["dashboard.approve"])
    app.buttons["dashboard.approve"].tap()
    XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
  }
  func testAccessibilityAudit() throws {
    launch("empty")
    tab("Activity")
    waitForUnobscuredScreen()
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
    reveal(app.staticTexts["calendar.month"])
    waitForLabel(app.staticTexts["calendar.month"], containing: "October")
    reveal(app.buttons["calendar.day.8"])
    waitForLabel(app.buttons["calendar.day.8"], containing: "October 8")
    app.buttons["calendar.day.8"].tap()
    XCTAssertTrue(app.staticTexts["explorer.count"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.staticTexts["explorer.count"].label, "1 runs")
    app.buttons["explorer.done"].tap()
    XCTAssertTrue(app.buttons["explorer.done"].waitForNonExistence(timeout: 10))
    reveal(app.buttons["calendar.previous"])
    app.buttons["calendar.previous"].tap()
    waitForLabel(app.staticTexts["calendar.month"], containing: "September")
    reveal(app.buttons["calendar.next"])
    app.buttons["calendar.next"].tap()
    waitForLabel(app.staticTexts["calendar.month"], containing: "October")
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
    reveal(app.buttons["zones.save"])
    XCTAssertFalse(app.buttons["zones.save"].isEnabled)
    let maximum = app.textFields["zones.maximum"]
    reveal(maximum, towardTop: true)
    maximum.tap()
    maximum.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4) + "190")
    reveal(app.buttons["zones.generate"])
    app.buttons["zones.generate"].tap()
    app.buttons["zones.keyboardDone"].tap()
    XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 10))
    reveal(app.buttons["zones.save"])
    XCTAssertTrue(app.buttons["zones.save"].isEnabled)
    app.buttons["zones.save"].tap()
    XCTAssertTrue(app.buttons["zones.save"].waitForNonExistence(timeout: 10))
    XCTAssertTrue(app.buttons["settings.done"].waitForExistence(timeout: 10))
    app.buttons["settings.done"].tap()
    tab("Trends")
    XCTAssertTrue(app.staticTexts["load.total.7"].waitForExistence(timeout: 10))
    reveal(app.staticTexts["load.total.7"])
    waitForLabel(app.staticTexts["load.total.7"], containing: " effort")
    reveal(app.staticTexts["Zone 3"], towardTop: true)
    XCTAssertTrue(app.otherElements["zones.total.3"].exists || app.staticTexts["Zone 3"].exists)
    app.terminate()
    launch("partial")
    tab("Trends")
    XCTAssertTrue(app.staticTexts["load.total.7"].waitForExistence(timeout: 10))
    reveal(app.staticTexts["load.total.7"])
    waitForLabel(app.staticTexts["load.total.7"], containing: "unavailable")
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
      waitForUnobscuredScreen()
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
    XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    waitForUnobscuredScreen()
    XCTAssertTrue(app.buttons["settings.done"].isHittable)
    try app.performAccessibilityAudit(for: [.contrast, .textClipped, .sufficientElementDescription])
    { issue in
      let description =
        "\(issue.detailedDescription)\n\(issue.element?.debugDescription ?? "Unknown element")"
      try? description.write(to: self.evidenceURL("audit.txt"), atomically: true, encoding: .utf8)
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
    let contrast = settings.switches["Increase Contrast"].firstMatch
    XCTAssertTrue(contrast.waitForExistence(timeout: 5))
    let originalContrast = contrast.value as? String ?? "0"
    defer {
      _ = navigate("Display & Text Size", toggle: "Reduce Transparency")
      let control = settings.switches["Increase Contrast"].firstMatch
      if control.value as? String != originalContrast { control.tap() }
    }
    if originalContrast == "0" { contrast.tap() }
    launch()
    tab("Activity")
    XCTAssertEqual(app.staticTexts["activity.total"].label, "3 runs")
    let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    screenshot.name = "Reduced motion and transparency"
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }

}
