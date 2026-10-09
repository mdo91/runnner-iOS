import Foundation
import SwiftUI

/// Test configuration is available only in Debug. Release always uses live services.
enum AppRuntime {
  static var scenario: String? {
    #if DEBUG
      let arguments = ProcessInfo.processInfo.arguments
      if let index = arguments.firstIndex(of: "--ui-scenario"), arguments.count > index + 1 {
        return arguments[index + 1]
      }
      if arguments.contains("--runner-fixtures") { return "populated" }
    #endif
    return nil
  }
  static var isFixture: Bool { scenario != nil }
  static var now: Date {
    isFixture ? Date(timeIntervalSince1970: 1_791_540_000) : Date()
  }
  static var calendar: Calendar {
    var result = Calendar.current
    if isFixture {
      result = Calendar(identifier: .gregorian)
      result.timeZone = TimeZone(identifier: "Europe/Istanbul")!
      result.firstWeekday = 2
      result.minimumDaysInFirstWeek = 4
    }
    return result
  }
  static let defaults: UserDefaults = {
    guard isFixture else { return .standard }
    let raw = ProcessInfo.processInfo.environment["RUNNER_TEST_ID"] ?? "preview"
    let identifier = String(raw.filter { $0.isLetter || $0.isNumber || $0 == "-" }.prefix(64))
    return UserDefaults(suiteName: "com.runner.uitests.\(identifier)")!
  }()
  static var appearance: ColorScheme? {
    guard isFixture else { return nil }
    switch ProcessInfo.processInfo.environment["RUNNER_APPEARANCE"] {
    case "light": return .light
    case "dark": return .dark
    default: return nil
    }
  }
  static var largeText: Bool {
    isFixture && ProcessInfo.processInfo.environment["RUNNER_LARGE_TEXT"] == "1"
  }
  @MainActor static func dashboardService() -> any DashboardLinkServicing {
    #if DEBUG
      if isFixture { return FixtureDashboardService(scenario: scenario ?? "populated") }
    #endif
    return DashboardLinkService()
  }
}

#if DEBUG
  @MainActor final class FixtureDashboardService: DashboardLinkServicing {
    let dashboardURL: URL? = nil
    private let scenario: String
    private var reviews = 0
    private var approvals = 0
    init(scenario: String) { self.scenario = scenario }
    func review(code: DashboardLinkCode, userID: String) async throws -> DashboardBrowser {
      reviews += 1
      if scenario == "dashboard-review-failure" && reviews == 1 {
        throw URLError(.notConnectedToInternet)
      }
      return DashboardBrowser(
        agent: "Simulator Safari · Fixture browser",
        expiresAt: AppRuntime.now.addingTimeInterval(scenario == "dashboard-expired" ? -1 : 600))
    }
    func approve(code: DashboardLinkCode, userID: String) async throws {
      approvals += 1
      if scenario == "dashboard-approval-failure" && approvals == 1 {
        throw URLError(.notConnectedToInternet)
      }
    }
  }
#endif
