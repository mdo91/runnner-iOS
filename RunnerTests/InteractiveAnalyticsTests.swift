import XCTest

@testable import RunCore

final class InteractiveAnalyticsTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 1_700_000_000)
  private func fixtureRun() -> RunData {
    var run = RunData(
      start: start, end: start.addingTimeInterval(300), duration: 300, distanceMeters: 1000,
      source: "Test")
    run.distances = (0..<10).map {
      TimedValue(
        start: start.addingTimeInterval(Double($0) * 30),
        end: start.addingTimeInterval(Double($0 + 1) * 30), value: 100)
    }
    return run
  }
  func testDistanceTimelineInterpolatesAndRejectsOverlapAndInaccurateTotals() {
    let original = fixtureRun()
    let timeline = DistanceTimeline(original)!
    XCTAssertEqual(timeline.distance(at: start.addingTimeInterval(45))!, 150, accuracy: 0.001)
    XCTAssertEqual(timeline.time(at: 150, starting: true)!, start.addingTimeInterval(45))
    var overlap = original
    overlap.distances[1].start = start.addingTimeInterval(29)
    XCTAssertNil(DistanceTimeline(overlap))
    var inaccurate = original
    inaccurate.distanceMeters = 1200
    XCTAssertNil(DistanceTimeline(inaccurate))
  }
  func testPaceSourceAndGapSegmentsNeverFillPauses() {
    var run = fixtureRun()
    XCTAssertEqual(RecordedSeries.make(run, metric: .pace).points.first!.value, 300, accuracy: 0.01)
    XCTAssertTrue(RecordedSeries.make(run, metric: .pace).source.contains("distance intervals"))
    run.dynamics["HKQuantityTypeIdentifierRunningSpeed"] = [
      TimedValue(start: start, value: 4), TimedValue(start: start.addingTimeInterval(10), value: 0),
      TimedValue(start: start.addingTimeInterval(20), value: 4),
      TimedValue(start: start.addingTimeInterval(100), value: 4),
    ]
    let series = RecordedSeries.make(run, metric: .pace)
    XCTAssertEqual(series.points.map(\.value), [250, 250, 250])
    XCTAssertEqual(Set(series.points.map(\.segment)).count, 3)
    run.pauses = [Pause(start: start.addingTimeInterval(15), end: start.addingTimeInterval(25))]
    XCTAssertEqual(RecordedSeries.make(run, metric: .pace).points.count, 2)
  }
  func testDisplaySeriesCapPreservesSegmentBreaksAndMissingSensors() {
    var run = fixtureRun()
    run.end = start.addingTimeInterval(10000)
    run.duration = 10000
    run.heartRate = (0..<5000).map {
      TimedValue(start: start.addingTimeInterval(Double($0)), value: 140)
    }
    run.pauses = [Pause(start: start.addingTimeInterval(1500), end: start.addingTimeInterval(1800))]
    let series = RecordedSeries.make(run, metric: .heartRate)
    XCTAssertLessThanOrEqual(series.points.count, 1000)
    XCTAssertEqual(series.points.last!.elapsedSeconds, 4999)
    XCTAssertGreaterThan(Set(series.points.map(\.segment)).count, 1)
    XCTAssertTrue(RecordedSeries.make(run, metric: .power).points.isEmpty)
  }
  func testCustomBucketsAcrossDSTAndHalfOpenDrilldown() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    let date = ISO8601DateFormatter().date(from: "2026-03-07T00:00:00-05:00")!
    let end = calendar.date(byAdding: .day, value: 3, to: date)!
    let stats = ActivityStatistics(runs: [], now: end, calendar: calendar)
    let interval = DateInterval(start: date, end: end)
    let buckets = stats.buckets(in: interval, component: .day)
    XCTAssertEqual(buckets.count, 3)
    XCTAssertEqual(buckets[1].interval.duration, 23 * 3600)
    XCTAssertEqual(stats.customBucketComponent(in: interval), .day)
    XCTAssertEqual(
      stats.customBucketComponent(in: DateInterval(start: date, duration: 100 * 86400)), .weekOfYear
    )
    XCTAssertEqual(
      stats.customBucketComponent(in: DateInterval(start: date, duration: 300 * 86400)), .month)
    let run = fixtureRun()
    let selection = ActivityStatistics(runs: [run], now: run.end)
    XCTAssertEqual(selection.runIDs(in: DateInterval(start: run.start, end: run.end)), [run.id])
    XCTAssertEqual(
      selection.runIDs(in: DateInterval(start: run.start.addingTimeInterval(-300), end: run.start)),
      [])
  }
  func testFiltersExcludeUnknownDistanceAndSortPace() {
    let first = fixtureRun()
    var second = fixtureRun()
    second.id = UUID()
    second.indoor = true
    second.distanceMeters = nil
    let snapshot = RunAnalyticsSnapshot(runs: [first, second])
    var filter = HistoryFilter()
    filter.minimumMeters = 500
    XCTAssertEqual(filter.apply(to: snapshot.runs, metrics: snapshot.metrics).map(\.id), [first.id])
    filter.minimumMeters = 0
    filter.setting = .indoor
    XCTAssertEqual(
      filter.apply(to: snapshot.runs, metrics: snapshot.metrics).map(\.id), [second.id])
  }
  func testAllMissingElevationIsUnavailableAndUnitsAreConverted() {
    let run = fixtureRun()
    let stats = ActivityStatistics(runs: [run], now: run.end)
    let summary = stats.summary(in: stats.period(.year))
    XCTAssertNil(summary.elevationGainMeters)
    XCTAssertEqual(
      ActivityMetric.distance.value(summary, units: .imperial)!, 1000 / 1609.344, accuracy: 0.001)
    XCTAssertEqual(summary.missingElevationCount, 1)
  }
  func testPausedIntervalInterpolationDoesNotMoveDuringThePause() {
    var run = fixtureRun()
    run.pauses = [Pause(start: start.addingTimeInterval(15), end: start.addingTimeInterval(45))]
    let timeline = DistanceTimeline(run)!
    XCTAssertEqual(timeline.distance(at: start.addingTimeInterval(25))!, 100, accuracy: 0.001)
    XCTAssertEqual(timeline.time(at: 100, starting: false), start.addingTimeInterval(15))
    XCTAssertEqual(timeline.time(at: 100, starting: true), start.addingTimeInterval(45))
    XCTAssertEqual(timeline.time(at: 120, starting: true), start.addingTimeInterval(48))
  }
  func testUnreliableAltitudeDoesNotBecomeMeasuredZeroOrBridgeAGap() {
    var run = fixtureRun()
    run.route = (0...4).map { i in
      RoutePoint(
        timestamp: start.addingTimeInterval(Double(i) * 3), latitude: 41 + Double(i) * 0.00001,
        longitude: 29, altitude: Double(i) * 10, verticalAccuracy: i.isMultiple(of: 2) ? 5 : -1)
    }
    XCTAssertNil(RunCalculator.metrics(run).elevationGainMeters)
    for i in run.route.indices {
      run.route[i].altitude = 10
      run.route[i].verticalAccuracy = 5
    }
    XCTAssertEqual(RunCalculator.metrics(run).elevationGainMeters, 0)
  }
  func testAnalyticsCacheInvalidatesChangedAndRemovedWorkouts() async throws {
    let service = CachedRunAnalyticsService()
    var run = fixtureRun()
    let original = try JSONEncoder().encode(run)
    let first = await service.snapshot(payloads: [original])
    XCTAssertNil(first.metrics[run.id]?.averageHeartRate)
    run.heartRate = [TimedValue(start: run.start, value: 150)]
    let revised = try JSONEncoder().encode(run)
    let next = await service.snapshot(payloads: [revised])
    XCTAssertEqual(next.metrics[run.id]?.averageHeartRate, 150)
    let series = await service.series(run: run)
    XCTAssertEqual(series[.heartRate]?.points.count, 1)
    let empty = await service.snapshot(payloads: [])
    XCTAssertTrue(empty.runs.isEmpty)
  }

}
