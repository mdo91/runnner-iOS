import Foundation

public enum RunSeriesMetric: String, CaseIterable, Sendable, Codable {
  case pace, heartRate, elevation, power, stride, groundContact, verticalOscillation
  public var title: String {
    switch self {
    case .pace: return "Pace"
    case .heartRate: return "Heart rate"
    case .elevation: return "Elevation"
    case .power: return "Power"
    case .stride: return "Stride length"
    case .groundContact: return "Ground contact"
    case .verticalOscillation: return "Vertical oscillation"
    }
  }
}
public struct RunSeriesPoint: Identifiable, Sendable, Equatable {
  public let id: Int
  public let elapsedSeconds: Double
  public let distanceMeters: Double?
  public let value: Double
  public let segment: Int
}
public struct RunSeries: Sendable {
  public let metric: RunSeriesMetric
  public let source: String
  public let points: [RunSeriesPoint]
  public var supportsDistanceAxis: Bool {
    !points.isEmpty && points.allSatisfy { $0.distanceMeters != nil }
  }
}

/// A trustworthy piecewise distance timeline. Totals alone never produce splits or best efforts.
public struct DistanceTimeline: Sendable {
  public struct Interval: Sendable {
    public let start, end: Date
    public let fromMeters, toMeters: Double
  }
  public let intervals: [Interval]
  private let pauses: [Pause]
  public init?(_ run: RunData) {
    guard let total = run.distanceMeters, total.isFinite, total > 0 else { return nil }
    let values = run.distances.filter {
      $0.value.isFinite && $0.value > 0 && $0.end > $0.start && $0.start >= run.start
        && $0.end <= run.end
    }.sorted { $0.start < $1.start }
    guard !values.isEmpty, abs(values.reduce(0) { $0 + $1.value } - total) / total <= 0.05 else {
      return nil
    }
    var result: [Interval] = []
    var meters = 0.0
    for value in values {
      guard RunCalculator.activeSeconds(from: value.start, to: value.end, pauses: run.pauses) > 0
      else { return nil }
      if let previous = result.last, value.start < previous.end { return nil }
      result.append(
        Interval(
          start: value.start, end: value.end, fromMeters: meters, toMeters: meters + value.value))
      meters += value.value
    }
    intervals = result
    pauses = RunCalculator.pauses(run.pauses, from: run.start, to: run.end)
  }
  public func distance(at date: Date) -> Double? {
    guard let first = intervals.first, let last = intervals.last, date >= first.start,
      date <= last.end
    else { return nil }
    var lower = 0
    var upper = intervals.count
    while lower < upper {
      let middle = (lower + upper) / 2
      if intervals[middle].end < date { lower = middle + 1 } else { upper = middle }
    }
    guard lower < intervals.count else { return nil }
    let interval = intervals[lower]
    guard date >= interval.start else { return nil }
    return interval.fromMeters + (interval.toMeters - interval.fromMeters)
      * RunCalculator.activeSeconds(from: interval.start, to: date, pauses: pauses)
      / max(
        0.001, RunCalculator.activeSeconds(from: interval.start, to: interval.end, pauses: pauses))
  }
  public func time(at meters: Double, starting: Bool) -> Date? {
    guard let last = intervals.last, meters.isFinite, meters >= 0, meters <= last.toMeters else {
      return nil
    }
    var lower = 0
    var upper = intervals.count
    while lower < upper {
      let middle = (lower + upper) / 2
      let end = intervals[middle].toMeters
      if starting ? end <= meters : end < meters { lower = middle + 1 } else { upper = middle }
    }
    let interval = intervals[min(lower, intervals.count - 1)]
    var remaining =
      RunCalculator.activeSeconds(from: interval.start, to: interval.end, pauses: pauses)
      * (meters - interval.fromMeters) / (interval.toMeters - interval.fromMeters)
    var cursor = interval.start
    for pause in pauses where pause.end > interval.start && pause.start < interval.end {
      let boundary = max(interval.start, pause.start)
      let active = max(0, boundary.timeIntervalSince(cursor))
      if remaining < active || (!starting && remaining == active) {
        return cursor.addingTimeInterval(remaining)
      }
      remaining -= active
      cursor = min(interval.end, pause.end)
    }
    return min(interval.end, cursor.addingTimeInterval(remaining))
  }
}

public enum RecordedSeries {
  public static func make(_ run: RunData, metric: RunSeriesMetric, limit: Int = 1000) -> RunSeries {
    let timeline = DistanceTimeline(run)
    var values: [(Date, Double, Int)] = []
    var source = "Recorded Health samples"
    if metric == .elevation {
      source = "Recorded GPS altitude · vertical accuracy ≤10 m"
      for (segment, points) in RunCalculator.routeSegments(run).enumerated() {
        var part = segment * 100_000
        var previous: Date?
        for point in points {
          guard point.altitude.isFinite, point.verticalAccuracy >= 0, point.verticalAccuracy <= 10
          else {
            part += 1
            previous = nil
            continue
          }
          if let previous, point.timestamp.timeIntervalSince(previous) > 20 { part += 1 }
          values.append((point.timestamp, point.altitude, part))
          previous = point.timestamp
        }
      }
    } else {
      let key: String
      let range: ClosedRange<Double>
      switch metric {
      case .pace:
        key = "HKQuantityTypeIdentifierRunningSpeed"
        range = 0.14...12
      case .heartRate:
        key = ""
        range = 25...250
      case .power:
        key = "HKQuantityTypeIdentifierRunningPower"
        range = 0...3000
      case .stride:
        key = "HKQuantityTypeIdentifierRunningStrideLength"
        range = 0...5
      case .groundContact:
        key = "HKQuantityTypeIdentifierRunningGroundContactTime"
        range = 0...2
      case .verticalOscillation:
        key = "HKQuantityTypeIdentifierRunningVerticalOscillation"
        range = 0...1
      case .elevation:
        key = ""
        range = -1000...10000
      }
      var samples = metric == .heartRate ? run.heartRate : run.dynamics[key] ?? []
      if metric == .pace, samples.isEmpty, let timeline {
        source = "Pace derived from recorded distance intervals"
        samples = timeline.intervals.compactMap { interval in
          let active = RunCalculator.activeSeconds(
            from: interval.start, to: interval.end, pauses: run.pauses)
          guard active > 0 else { return nil }
          return TimedValue(
            start: interval.start.addingTimeInterval(
              interval.end.timeIntervalSince(interval.start) / 2),
            value: (interval.toMeters - interval.fromMeters) / active)
        }
      } else if metric == .pace {
        source = "Pace derived from recorded running speed"
      }
      var segment = 0
      var previous: Date?
      for sample in samples.sorted(by: { $0.start < $1.start }) {
        guard sample.start >= run.start, sample.start <= run.end, sample.value.isFinite,
          range.contains(sample.value),
          !run.pauses.contains(where: { sample.start >= $0.start && sample.start < $0.end })
        else {
          segment += 1
          previous = nil
          continue
        }
        let gapLimit = 30.0
        if let previous,
          sample.start.timeIntervalSince(previous) > gapLimit
            || run.pauses.contains(where: { $0.start < sample.start && $0.end > previous })
        {
          segment += 1
        }
        let value: Double
        switch metric {
        case .pace: value = 1000 / sample.value
        case .groundContact: value = sample.value * 1000
        case .verticalOscillation: value = sample.value * 100
        default: value = sample.value
        }
        values.append((sample.start, value, segment))
        previous = sample.start
      }
    }
    let cap = max(2, min(1000, limit))
    let step = max(1, Int(ceil(Double(values.count) / Double(cap))))
    var indices = Array(stride(from: 0, to: values.count, by: step))
    if !indices.isEmpty, indices.last != values.count - 1 {
      indices[indices.count - 1] = values.count - 1
    }
    return RunSeries(
      metric: metric, source: source,
      points: indices.map { index in
        let value = values[index]
        return RunSeriesPoint(
          id: index, elapsedSeconds: value.0.timeIntervalSince(run.start),
          distanceMeters: timeline?.distance(at: value.0), value: value.1, segment: value.2)
      })
  }
}

public struct RunAnalyticsSnapshot: Sendable {
  public let runs: [RunData]
  public let metrics: [UUID: MeasuredMetrics]
  public let baseline: HistoricalBaseline?
  public let baselineRunIDs: [UUID]
  public let efforts: [BestEffort]
  public let routeMatches: [RouteMatch]
  public init(runs: [RunData], metrics: [UUID: MeasuredMetrics]? = nil) {
    let ordered = runs.sorted { $0.start > $1.start }
    let measured =
      metrics ?? Dictionary(uniqueKeysWithValues: runs.map { ($0.id, RunCalculator.metrics($0)) })
    self.runs = ordered
    self.metrics = measured
    efforts = ordered.flatMap { BestEfforts.make(run: $0) }
    routeMatches = RepeatedRoutes.match(runs: ordered)
    baseline = ordered.first.map {
      HistoricalBaseline.make(
        for: $0, history: ordered, vo2: [], recovery: [], metricsByRun: measured)
    }
    baselineRunIDs =
      ordered.first.map {
        HistoricalBaseline.comparableRuns(for: $0, history: ordered, measured: measured).map(\.id)
      } ?? []
  }
  public static let empty = RunAnalyticsSnapshot(runs: [])
}
