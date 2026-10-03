import XCTest

@testable import RunCore

final class ImportAndTrendsTests: XCTestCase {
  let start = Date(timeIntervalSince1970: 1_800_000_000)
  func fixtureRun(daysAgo: Double = 0, duration: Double = 1500) -> RunData {
    let date = start.addingTimeInterval(-daysAgo * 86400)
    return RunData(
      start: date, end: date.addingTimeInterval(duration), duration: duration,
      distanceMeters: 5000, source: "Apple Watch",
      heartRate: stride(from: 0.0, to: duration, by: 10).map {
        TimedValue(start: date.addingTimeInterval($0), value: 145)
      })
  }
  func testRepeatedImportDoesNotInvalidateAnalysisButDelayedSamplesDo() {
    let original = fixtureRun()
    var imported = original
    imported.importedAt = start.addingTimeInterval(1000)
    XCTAssertTrue(RunRevision.hasSameAnalysisData(original, imported))
    imported.heartRate = []
    XCTAssertFalse(RunRevision.hasSameAnalysisData(original, imported))
    imported = original
    imported.route = [RoutePoint(timestamp: start, latitude: 41, longitude: 29)]
    XCTAssertFalse(RunRevision.hasSameAnalysisData(original, imported))
    imported = original
    imported.id = UUID()
    XCTAssertFalse(RunRevision.hasSameAnalysisData(original, imported))
  }
  func testComparableHistoryRequiresFiveRunsAndRetainsMeasurementDates() {
    let current = fixtureRun(duration: 1450)
    let history = (1...5).map { fixtureRun(daysAgo: Double($0)) }
    let old = DatedMeasurement(value: 43, measuredAt: start.addingTimeInterval(-86400))
    let future = DatedMeasurement(value: 48, measuredAt: start.addingTimeInterval(86400))
    let insufficient = HistoricalBaseline.make(
      for: current, history: Array(history.prefix(4)), vo2: [old, future], recovery: [])
    XCTAssertNil(insufficient.paceChangePercent)
    let baseline = HistoricalBaseline.make(
      for: current, history: history, vo2: [old, future], recovery: [])
    XCTAssertEqual(baseline.comparableRunCount, 5)
    XCTAssertEqual(baseline.paceChangePercent!, -3.333333, accuracy: 0.0001)
    XCTAssertEqual(baseline.vo2Max, old)
    XCTAssertNil(baseline.previousVo2Max)
    var indoor = history[0]
    indoor.indoor = true
    var sparse = history[1]
    sparse.heartRate = Array(sparse.heartRate.prefix(1))
    XCTAssertEqual(
      HistoricalBaseline.make(for: current, history: [indoor, sparse], vo2: [], recovery: [])
        .comparableRunCount, 0)
  }
  func testDensityCountsRouteVisitsRatherThanStationarySamples() {
    var first = fixtureRun()
    first.route = (0...10).map {
      RoutePoint(
        timestamp: start.addingTimeInterval(Double($0) * 5), latitude: 41 + Double($0) * 0.00005,
        longitude: 29)
    }
    let cells = RouteDensity.cells(runs: [first])
    XCTAssertFalse(cells.isEmpty)
    XCTAssertTrue(cells.allSatisfy { $0.runs == 1 })
    var linger = first
    let last = first.route.last!
    linger.route += (1...50).map {
      RoutePoint(
        timestamp: last.timestamp.addingTimeInterval(Double($0) * 5), latitude: last.latitude,
        longitude: last.longitude)
    }
    XCTAssertEqual(Set(cells.map(\.id)), Set(RouteDensity.cells(runs: [linger]).map(\.id)))
    var second = first
    second.id = UUID()
    XCTAssertTrue(RouteDensity.cells(runs: [first, second]).allSatisfy { $0.runs == 2 })
  }
  func testLivePauseExcludesRecoveryHeartRate() {
    var current = fixtureRun(duration: 120)
    current.duration = 60
    current.pauses = [Pause(start: start.addingTimeInterval(30), end: start.addingTimeInterval(90))]
    current.heartRate = [
      TimedValue(start: start, value: 150),
      TimedValue(start: start.addingTimeInterval(30), value: 95),
      TimedValue(start: start.addingTimeInterval(90), value: 150),
    ]
    let metrics = RunCalculator.metrics(current)
    XCTAssertEqual(metrics.averageHeartRate, 150)
    XCTAssertEqual(metrics.heartRateCoverage, 1)
    XCTAssertEqual(metrics.movingSeconds, 60)
  }
}
