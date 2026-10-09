import XCTest

@testable import RunCore

final class ActivityStatisticsTests: XCTestCase {
  var calendar: Calendar {
    var value = Calendar(identifier: .gregorian)
    value.timeZone = TimeZone(identifier: "Europe/Istanbul")!
    value.firstWeekday = 2
    value.minimumDaysInFirstWeek = 4
    return value
  }

  func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

  func run(_ start: String, distance: Double? = 5000, duration: Double = 1800) -> RunData {
    let start = date(start)
    return RunData(
      start: start, end: start.addingTimeInterval(duration), duration: duration,
      distanceMeters: distance, source: "Test")
  }

  func testCurrentMonthCountsDailyRunsAndExcludesFutureAndOtherMonths() {
    let now = date("2026-10-09T12:00:00+03:00")
    let stats = ActivityStatistics(
      runs: [
        run("2026-09-30T23:00:00+03:00"),
        run("2026-10-01T00:00:00+03:00", distance: 3000),
        run("2026-10-09T08:00:00+03:00", distance: 5000),
        run("2026-10-09T10:00:00+03:00", distance: 7000),
        run("2026-10-09T11:50:00+03:00"),  // Not completed yet.
        run("2026-10-10T08:00:00+03:00"),
      ], now: now, calendar: calendar)
    let buckets = stats.buckets(for: .month)
    XCTAssertEqual(buckets.count, 9)
    XCTAssertEqual(buckets.first?.summary.runCount, 1)
    XCTAssertEqual(buckets[1].summary.runCount, 0)
    XCTAssertEqual(buckets.last?.summary.runCount, 2)
    let total = stats.summary(in: ActivityRange.month.interval(now: now, calendar: calendar))
    XCTAssertEqual(total.runCount, 3)
    XCTAssertEqual(total.distanceMeters, 15000)
    XCTAssertEqual(buckets.reduce(0) { $0 + $1.summary.runCount }, total.runCount)
    XCTAssertEqual(
      buckets.reduce(0) { $0 + ($1.summary.distanceMeters ?? 0) }, total.distanceMeters)
  }

  func testMultiMonthRangesCrossYearsAndIncludeEmptyMonths() {
    let now = date("2026-02-09T12:00:00+03:00")
    let stats = ActivityStatistics(
      runs: [
        run("2025-08-31T23:00:00+03:00"),
        run("2025-09-01T00:00:00+03:00"),
        run("2025-12-31T23:00:00+03:00"),
        run("2026-01-01T00:00:00+03:00"),
      ], now: now, calendar: calendar)
    XCTAssertEqual(stats.buckets(for: .threeMonths).map(\.summary.runCount), [1, 1, 0])
    XCTAssertEqual(stats.buckets(for: .sixMonths).map(\.summary.runCount), [1, 0, 0, 1, 1, 0])
    XCTAssertEqual(stats.buckets(for: .year).map(\.summary.runCount), [1, 0])
    XCTAssertEqual(
      ActivityRange.sixMonths.interval(now: now, calendar: calendar).start,
      date("2025-09-01T00:00:00+03:00"))
  }

  func testMissingAndInvalidDistancesRemainUnavailableAndPaceIsWeighted() {
    let now = date("2026-10-09T12:00:00+03:00")
    let valid = [
      run("2026-10-02T08:00:00+03:00", distance: 1000, duration: 240),
      run("2026-10-03T08:00:00+03:00", distance: 9000, duration: 3240),
    ]
    let invalid = [
      run("2026-10-04T08:00:00+03:00", distance: nil),
      run("2026-10-05T08:00:00+03:00", distance: -.infinity),
      run("2026-10-06T08:00:00+03:00", distance: -1),
      run("2026-10-07T08:00:00+03:00", distance: .nan),
    ]
    let stats = ActivityStatistics(runs: valid + invalid, now: now, calendar: calendar)
    let summary = stats.summary(in: stats.period(.month))
    XCTAssertEqual(summary.runCount, 6)
    XCTAssertEqual(summary.distanceMeters, 10000)
    XCTAssertEqual(summary.missingDistanceCount, 4)
    XCTAssertEqual(summary.averagePaceSecondsPerKm!, 348, accuracy: 0.001)
    XCTAssertNil(stats.comparison(.month).distanceChangeMeters)
    XCTAssertNil(stats.comparison(.month).paceImprovementPercent)
    let missing = ActivityStatistics(runs: invalid, now: now, calendar: calendar)
    XCTAssertNil(missing.summary(in: missing.period(.month)).distanceMeters)
    XCTAssertNil(missing.summary(in: missing.period(.month)).averagePaceSecondsPerKm)
  }

  func testPerformancePeriodsAndComparisonsUseDifferentCutoffs() {
    let stats = ActivityStatistics(
      runs: [
        run("2026-09-01T08:00:00+03:00", distance: 5000, duration: 1800),
        run("2026-09-09T13:00:00+03:00"),  // Full last-month total only.
        run("2026-10-02T08:00:00+03:00", distance: 10000, duration: 3000),
        run("2026-10-09T08:00:00+03:00", distance: 5000, duration: 1500),
      ], now: date("2026-10-09T12:00:00+03:00"), calendar: calendar)
    XCTAssertEqual(stats.summary(in: stats.period(.month)).runCount, 2)
    XCTAssertEqual(stats.summary(in: stats.period(.month, previous: true)).runCount, 2)
    XCTAssertEqual(stats.summary(in: stats.period(.weekOfYear)).runCount, 1)
    XCTAssertEqual(stats.summary(in: stats.period(.weekOfYear, previous: true)).runCount, 1)
    let comparison = stats.comparison(.month)
    XCTAssertEqual(comparison.previous.runCount, 1)
    XCTAssertEqual(comparison.runCountChange, 1)
    XCTAssertEqual(comparison.distanceChangeMeters, 10000)
    XCTAssertEqual(comparison.paceImprovementPercent!, 100.0 / 6, accuracy: 0.001)
  }

  func testShorterPreviousMonthCapsBothComparisonWindowsInLeapYear() {
    let stats = ActivityStatistics(
      runs: [
        run("2024-02-29T08:00:00+03:00"),
        run("2024-03-29T08:00:00+03:00"),
        run("2024-03-30T08:00:00+03:00"),
      ], now: date("2024-03-31T12:00:00+03:00"), calendar: calendar)
    let comparison = stats.comparison(.month)
    XCTAssertEqual(comparison.previousInterval.end, date("2024-03-01T00:00:00+03:00"))
    XCTAssertEqual(comparison.currentInterval.end, date("2024-03-30T00:00:00+03:00"))
    XCTAssertEqual(comparison.current.runCount, 1)
    XCTAssertEqual(comparison.previous.runCount, 1)
    XCTAssertEqual(stats.summary(in: stats.period(.month)).runCount, 2)
  }

  func testWeekBoundariesFollowCalendarAcrossDaylightSavingTime() {
    var calendar = calendar
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    calendar.firstWeekday = 1
    let stats = ActivityStatistics(
      runs: [
        run("2026-03-07T23:00:00-05:00"),
        run("2026-03-08T00:00:00-05:00"),
      ], now: date("2026-03-10T12:00:00-04:00"), calendar: calendar)
    XCTAssertEqual(stats.period(.weekOfYear).start, date("2026-03-08T00:00:00-05:00"))
    XCTAssertEqual(stats.summary(in: stats.period(.weekOfYear)).runCount, 1)
    XCTAssertEqual(stats.summary(in: stats.period(.weekOfYear, previous: true)).runCount, 1)
    XCTAssertEqual(
      stats.comparison(.weekOfYear).previousInterval.end,
      date("2026-03-03T12:00:00-05:00"))
    let day = stats.buckets(for: .month)[7]
    XCTAssertEqual(day.interval.duration, 23 * 3600)
    calendar.firstWeekday = 2
    let monday = ActivityStatistics(runs: [], now: stats.now, calendar: calendar)
    XCTAssertEqual(monday.period(.weekOfYear).start, date("2026-03-09T00:00:00-04:00"))
  }

  func testEmptyAndZeroDistancePeriodsDoNotInventPaceOrDivideByZero() {
    let now = date("2026-01-01T00:00:00+03:00")
    let empty = ActivityStatistics(runs: [], now: now, calendar: calendar)
    XCTAssertEqual(empty.buckets(for: .year).count, 1)
    XCTAssertEqual(empty.buckets(for: .month).count, 1)
    XCTAssertEqual(empty.summary(in: empty.period(.month)).distanceMeters, 0)
    XCTAssertEqual(empty.comparison(.month).runCountChange, 0)
    XCTAssertNil(empty.comparison(.month).paceImprovementPercent)
    let zero = ActivityStatistics(
      runs: [run("2025-12-01T08:00:00+03:00", distance: 0)],
      now: now, calendar: calendar)
    let summary = zero.summary(in: zero.period(.month, previous: true))
    XCTAssertEqual(summary.runCount, 1)
    XCTAssertEqual(summary.distanceMeters, 0)
    XCTAssertNil(summary.averagePaceSecondsPerKm)
  }

  func testDeclinesAndNoPreviousRunsHaveHonestComparisons() {
    let now = date("2026-10-09T12:00:00+03:00")
    let current = run("2026-10-01T08:00:00+03:00", distance: 4000, duration: 1600)
    let stats = ActivityStatistics(
      runs: [
        current,
        run("2026-09-01T08:00:00+03:00", distance: 5000, duration: 1500),
        run("2026-09-02T08:00:00+03:00", distance: 5000, duration: 1500),
      ], now: now, calendar: calendar)
    let comparison = stats.comparison(.month)
    XCTAssertEqual(comparison.runCountChange, -1)
    XCTAssertEqual(comparison.distanceChangeMeters, -6000)
    XCTAssertEqual(comparison.paceImprovementPercent!, -100.0 / 3, accuracy: 0.001)
    let first = ActivityStatistics(runs: [current], now: now, calendar: calendar).comparison(.month)
    XCTAssertEqual(first.runCountChange, 1)
    XCTAssertEqual(first.distanceChangeMeters, 4000)
    XCTAssertNil(first.paceImprovementPercent)
  }
}
