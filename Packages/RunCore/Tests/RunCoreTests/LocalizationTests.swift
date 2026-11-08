import Foundation
import XCTest
@testable import RunCore

final class LocalizationTests: XCTestCase {
  func testCatalogResolvesSharedAndOnboardingKeys() {
    XCTAssertEqual("Common.Copy.distance.text".localized(language: .german), "Distanz")
    XCTAssertEqual("Common.Copy.distance.text".localized(language: .english), "Distance")
    XCTAssertEqual("OnboardingView.HealthPage.title.text".localized(language: .german), "Deine Läufe. An einem Ort.")
  }

  func testPluralResourcesAndReorderedArguments() {
    let german = "Common.Count.runs.text".localized(language: .german)
    XCTAssertEqual(String(format: german, locale: Locale(identifier: "de_DE"), 1), "1 Lauf")
    XCTAssertEqual(String(format: german, locale: Locale(identifier: "de_DE"), 3), "3 Läufe")
    let progress = "OnboardingView.Progress.accessibility.text".localized(language: .german)
    XCTAssertEqual(String(format: progress, 2, 6), "Seite 2 von 6")
  }

  func testGermanGoalTitlesUseCompleteGrammaticalPhrases() {
    XCTAssertEqual(TrainingGoal(metric: .distance, period: .week, target: 20000).title(language: .german), "Wöchentliche Distanz")
    XCTAssertEqual(TrainingGoal(metric: .runs, period: .month, target: 12).title(language: .german), "Monatliche Läufe")
  }

  func testPresentationDoesNotChangePersistedIdentifiers() throws {
    XCTAssertEqual(ActivityMetric.distance.rawValue, "Distance")
    XCTAssertEqual(try JSONDecoder().decode(GoalPeriod.self, from: Data("\"Weekly\"".utf8)), .week)
    XCTAssertEqual(try JSONDecoder().decode(AppLanguage.self, from: Data("\"de\"".utf8)), .german)
    XCTAssertThrowsError(try JSONDecoder().decode(AppLanguage.self, from: Data("\"fr\"".utf8)))
  }

  func testExistingReportsDecodeWithoutLanguageAndPreserveGermanReports() throws {
    let source = #"{"schemaVersion":1,"id":"27f937c4-bc4c-4e10-9a52-467039d8a428","status":"complete","metrics":{"elapsedSeconds":1800,"movingSeconds":1500,"heartRateCoverage":0},"explanation":{"summary":"Steady run","insights":[],"nextRun":"Keep it easy"},"endurance":{"status":"insufficient_data","detail":"More runs needed"},"missingData":[],"generatedAt":"2026-10-03T12:00:00Z"}"#
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let old = try decoder.decode(AnalysisReport.self, from: Data(source.utf8))
    XCTAssertNil(old.language)
    XCTAssertEqual(old.effectiveLanguage, .english)
    var translated = old
    translated.language = .german
    translated.explanation.summary = "Gleichmäßiger Lauf"
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let restored = try decoder.decode(AnalysisReport.self, from: encoder.encode(translated))
    XCTAssertEqual(restored.effectiveLanguage, .german)
    XCTAssertEqual(restored.explanation.summary, "Gleichmäßiger Lauf")
    XCTAssertEqual(old.explanation.summary, "Steady run")
  }
}
