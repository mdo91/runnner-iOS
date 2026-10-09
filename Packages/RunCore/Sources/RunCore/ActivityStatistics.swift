import Foundation

public enum ActivityRange: String, CaseIterable, Sendable {
  case month, threeMonths, sixMonths, year

  public var title: String {
    switch self {
    case .month: return "Month"
    case .threeMonths: return "3 Months"
    case .sixMonths: return "6 Months"
    case .year: return "Year"
    }
  }

  public var bucketComponent: Calendar.Component { self == .month ? .day : .month }

  /// Multi-month ranges include the current calendar month; year starts at the supplied
  /// calendar's year boundary. All ranges stop at now, not at a future period boundary.
  public func interval(now: Date, calendar: Calendar) -> DateInterval {
    let month = calendar.dateInterval(of: .month, for: now)!.start
    let start: Date
    switch self {
    case .month: start = month
    case .threeMonths: start = calendar.date(byAdding: .month, value: -2, to: month)!
    case .sixMonths: start = calendar.date(byAdding: .month, value: -5, to: month)!
    case .year: start = calendar.dateInterval(of: .year, for: now)!.start
    }
    return DateInterval(start: start, end: now)
  }
}

public struct ActivitySummary: Sendable, Equatable {
  public var runCount = 0
  public var missingDistanceCount = 0
  public var paceRunCount = 0
  public var movingSeconds = 0.0
  private var knownDistanceMeters = 0.0
  private var paceDistanceMeters = 0.0
  private var paceMovingSeconds = 0.0

  /// Empty periods are zero; a period with runs but no measured distance is unavailable.
  public var distanceMeters: Double? {
    runCount > 0 && missingDistanceCount == runCount ? nil : knownDistanceMeters
  }
  public var averagePaceSecondsPerKm: Double? {
    paceDistanceMeters > 0 ? paceMovingSeconds / paceDistanceMeters * 1000 : nil
  }

  mutating func add(_ run: RunData) {
    runCount += 1
    // Use the same duration rule as RunCalculator.metrics without processing GPS/samples.
    let moving =
      run.duration.isFinite
      ? min(max(0, run.end.timeIntervalSince(run.start)), max(0, run.duration)) : 0
    movingSeconds += moving
    guard let distance = run.distanceMeters, distance.isFinite, distance >= 0 else {
      missingDistanceCount += 1
      return
    }
    knownDistanceMeters += distance
    if distance > 0 && moving > 0 {
      paceRunCount += 1
      paceDistanceMeters += distance
      paceMovingSeconds += moving
    }
  }
}

public struct ActivityBucket: Identifiable, Sendable {
  public var interval: DateInterval
  public var summary: ActivitySummary
  public var id: Date { interval.start }
}

public struct ActivityComparison: Sendable {
  public var currentInterval: DateInterval
  public var previousInterval: DateInterval
  public var current: ActivitySummary
  public var previous: ActivitySummary

  public var runCountChange: Int { current.runCount - previous.runCount }
  public var distanceChangeMeters: Double? {
    guard current.missingDistanceCount == 0, previous.missingDistanceCount == 0,
      let currentDistance = current.distanceMeters, let previousDistance = previous.distanceMeters
    else { return nil }
    return currentDistance - previousDistance
  }
  /// Positive means faster. Do not infer a change from a zero or incomplete baseline.
  public var paceImprovementPercent: Double? {
    guard current.paceRunCount == current.runCount, previous.paceRunCount == previous.runCount,
      let currentPace = current.averagePaceSecondsPerKm,
      let previousPace = previous.averagePaceSecondsPerKm, previousPace > 0
    else { return nil }
    return (previousPace - currentPace) / previousPace * 100
  }
}

public struct ActivityStatistics: Sendable {
  public let now: Date
  public let calendar: Calendar
  private let runs: [RunData]

  public init(runs: [RunData], now: Date = Date(), calendar: Calendar = .current) {
    self.now = now
    self.calendar = calendar
    self.runs = runs.filter { $0.start <= now && $0.end <= now && $0.end >= $0.start }
  }

  public func summary(in interval: DateInterval) -> ActivitySummary {
    var result = ActivitySummary()
    // Half-open boundaries assign a workout to exactly one period by its start time.
    for run in runs where run.start >= interval.start && run.start < interval.end {
      result.add(run)
    }
    return result
  }

  public func buckets(for range: ActivityRange) -> [ActivityBucket] {
    let interval = range.interval(now: now, calendar: calendar)
    var date = interval.start
    var result: [ActivityBucket] = []
    repeat {
      let end = calendar.date(byAdding: range.bucketComponent, value: 1, to: date)!
      let bucket = DateInterval(start: date, end: end)
      result.append(ActivityBucket(interval: bucket, summary: summary(in: bucket)))
      date = end
    } while date <= now
    return result
  }

  public func period(_ component: Calendar.Component, previous: Bool = false) -> DateInterval {
    let current = calendar.dateInterval(of: component, for: now)!
    if previous {
      let date = calendar.date(byAdding: component, value: -1, to: current.start)!
      return calendar.dateInterval(of: component, for: date)!
    }
    return DateInterval(start: current.start, end: now)
  }

  /// Compare equal calendar-day/time portions. If the prior month is shorter,
  /// cap both windows at that month's length. Calendar arithmetic preserves DST.
  public func comparison(_ component: Calendar.Component) -> ActivityComparison {
    let current = period(component)
    let previous = period(component, previous: true)
    let elapsed = calendar.dateComponents(
      [.day, .hour, .minute, .second],
      from: current.start, to: now)
    let previousEnd = min(previous.end, calendar.date(byAdding: elapsed, to: previous.start)!)
    let matched = calendar.dateComponents(
      [.day, .hour, .minute, .second],
      from: previous.start, to: previousEnd)
    let currentEnd = min(now, calendar.date(byAdding: matched, to: current.start)!)
    let currentInterval = DateInterval(start: current.start, end: currentEnd)
    let previousInterval = DateInterval(start: previous.start, end: previousEnd)
    return ActivityComparison(
      currentInterval: currentInterval, previousInterval: previousInterval,
      current: summary(in: currentInterval), previous: summary(in: previousInterval))
  }
}
