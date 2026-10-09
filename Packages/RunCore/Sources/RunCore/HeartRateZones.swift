import Foundation

public struct HeartRateZones: Codable, Sendable, Equatable {
  public var maximum: Double
  public var boundaries: [Double]
  public init(maximum: Double) {
    self.maximum = maximum
    boundaries = [0.5, 0.6, 0.7, 0.8, 0.9].map { maximum * $0 }
  }
  public var isValid: Bool {
    maximum.isFinite && (80...240).contains(maximum) && boundaries.count == 5
      && boundaries.allSatisfy { $0.isFinite && $0 >= 25 && $0 < maximum }
      && zip(boundaries, boundaries.dropFirst()).allSatisfy { $1 - $0 >= 1 }
  }
}
public struct ZoneDistribution: Sendable {
  public let seconds: [Double]  // index 0: below Zone 1; index 1...5: Zones 1...5
  public let aboveMaximumSeconds: Double
  public let coverage: Double
  public var effort: Double { (1...5).reduce(0) { $0 + seconds[$1] / 60 * Double($1) } }
  public static func make(run: RunData, zones: HeartRateZones) -> ZoneDistribution? {
    guard zones.isValid else { return nil }
    let values = run.heartRate.filter {
      $0.start >= run.start.addingTimeInterval(-30) && $0.start < run.end
    }.sorted { $0.start < $1.start }
    var totals = Array(repeating: 0.0, count: 6)
    var above = 0.0
    for (index, sample) in values.enumerated() {
      // Invalid readings end the previous observation instead of filling their gap.
      guard sample.value.isFinite && (25...250).contains(sample.value) else { continue }
      let next = index + 1 < values.count ? values[index + 1].start : run.end
      let end = min(next, run.end, sample.start.addingTimeInterval(30))
      let seconds = RunCalculator.activeSeconds(
        from: max(run.start, sample.start), to: end, pauses: run.pauses)
      let zone = zones.boundaries.filter { sample.value >= $0 }.count
      totals[zone] += seconds
      if sample.value > zones.maximum { above += seconds }
    }
    let moving = RunCalculator.activeSeconds(from: run.start, to: run.end, pauses: run.pauses)
    let coverage = moving > 0 ? min(1, totals.reduce(0, +) / moving) : 0
    return ZoneDistribution(seconds: totals, aboveMaximumSeconds: above, coverage: coverage)
  }
}
public struct TrainingLoadBucket: Identifiable, Sendable {
  public var id: Date { interval.start }
  public let interval: DateInterval
  public let observedEffort: Double
  public let runCount: Int
  public let incompleteCount: Int
}
public struct TrainingLoad: Sendable {
  public let distributions: [UUID: ZoneDistribution]
  public init(runs: [RunData], zones: HeartRateZones) {
    distributions = Dictionary(
      uniqueKeysWithValues: runs.compactMap { run in
        ZoneDistribution.make(run: run, zones: zones).map { (run.id, $0) }
      })
  }
  public func bucket(in interval: DateInterval, runs: [RunData]) -> TrainingLoadBucket {
    let matching = runs.filter {
      $0.start >= interval.start && $0.start < interval.end && $0.duration > 0
    }
    return TrainingLoadBucket(
      interval: interval,
      observedEffort: matching.reduce(0) { $0 + (distributions[$1.id]?.effort ?? 0) },
      runCount: matching.count,
      incompleteCount: matching.filter { (distributions[$0.id]?.coverage ?? 0) < 0.8 }.count)
  }
  public func completeTotal(in interval: DateInterval, runs: [RunData]) -> Double? {
    let bucket = bucket(in: interval, runs: runs)
    return bucket.incompleteCount == 0 ? bucket.observedEffort : nil
  }
}
