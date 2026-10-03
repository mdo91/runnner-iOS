import Foundation

public struct DatedMeasurement: Codable, Sendable, Equatable {
  public var value: Double
  public var measuredAt: Date
  public init(value: Double, measuredAt: Date) {
    self.value = value
    self.measuredAt = measuredAt
  }
}
public struct HistoricalBaseline: Codable, Sendable {
  public var comparableRunCount: Int
  public var averagePaceSecondsPerKm: Double?
  public var averageHeartRate: Double?
  public var paceChangePercent: Double?
  public var vo2Max: DatedMeasurement?
  public var previousVo2Max: DatedMeasurement?
  public var recoveryBpm: DatedMeasurement?
  public static func make(
    for run: RunData, history: [RunData], vo2: [DatedMeasurement], recovery: [DatedMeasurement]
  ) -> HistoricalBaseline {
    let metrics = RunCalculator.metrics(run)
    let matches = history.filter { other in
      guard other.id != run.id, other.end < run.start, other.indoor == run.indoor,
        run.start.timeIntervalSince(other.start) < 90 * 86400,
        let distance = run.distanceMeters, let otherDistance = other.distanceMeters,
        let currentHR = metrics.averageHeartRate
      else { return false }
      let m = RunCalculator.metrics(other)
      guard let hr = m.averageHeartRate, m.heartRateCoverage >= 0.5,
        metrics.heartRateCoverage >= 0.5
      else { return false }
      return abs(otherDistance - distance) <= distance * 0.2 && abs(hr - currentHR) <= 10
    }
    let values = matches.map(RunCalculator.metrics)
    let paces = values.compactMap(\.averagePaceSecondsPerKm)
    let heartRates = values.compactMap(\.averageHeartRate)
    let pace = paces.isEmpty ? nil : paces.reduce(0, +) / Double(paces.count)
    let hr = heartRates.isEmpty ? nil : heartRates.reduce(0, +) / Double(heartRates.count)
    let eligibleVo2 = vo2.filter { $0.measuredAt <= run.end }.sorted {
      $0.measuredAt > $1.measuredAt
    }
    return HistoricalBaseline(
      comparableRunCount: matches.count, averagePaceSecondsPerKm: pace, averageHeartRate: hr,
      paceChangePercent: matches.count >= 5
        ? pace.flatMap { previous in
          metrics.averagePaceSecondsPerKm.map { ($0 - previous) / previous * 100 }
        } : nil,
      vo2Max: eligibleVo2.first, previousVo2Max: eligibleVo2.dropFirst().first,
      recoveryBpm: recovery.filter { $0.measuredAt <= run.end.addingTimeInterval(300) }.max {
        $0.measuredAt < $1.measuredAt
      })
  }
  // Explicit nulls keep the wire contract independent of Swift's optional omission behavior.
  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: Keys.self)
    try c.encode(comparableRunCount, forKey: .comparableRunCount)
    try c.encode(averagePaceSecondsPerKm, forKey: .averagePaceSecondsPerKm)
    try c.encode(averageHeartRate, forKey: .averageHeartRate)
    try c.encode(paceChangePercent, forKey: .paceChangePercent)
    try c.encode(vo2Max, forKey: .vo2Max)
    try c.encode(previousVo2Max, forKey: .previousVo2Max)
    try c.encode(recoveryBpm, forKey: .recoveryBpm)
  }
  enum Keys: String, CodingKey {
    case comparableRunCount, averagePaceSecondsPerKm, averageHeartRate, paceChangePercent, vo2Max,
      previousVo2Max, recoveryBpm
  }
}
public struct AnalysisRequest: Encodable, Sendable {
  public let schemaVersion = 1
  public let consentVersion = "2026-10-03"
  public var id: UUID
  public var metrics: MeasuredMetrics
  public var baseline: HistoricalBaseline
  public var splits: [Split]
  public var quality: Quality
  public struct Quality: Codable, Sendable {
    public var hasRoute, hasPauses, distanceSamplesAvailable, heartRateSamplesAvailable,
      isIndoor: Bool
  }
  public init(
    run: RunData, history: [RunData], vo2: [DatedMeasurement] = [],
    recovery: [DatedMeasurement] = []
  ) {
    id = run.id
    metrics = RunCalculator.metrics(run)
    splits = RunCalculator.splits(run)
    baseline = .make(for: run, history: history, vo2: vo2, recovery: recovery)
    quality = Quality(
      hasRoute: !run.route.isEmpty, hasPauses: !run.pauses.isEmpty,
      distanceSamplesAvailable: !run.distances.isEmpty,
      heartRateSamplesAvailable: !run.heartRate.isEmpty, isIndoor: run.indoor)
  }
}
public struct AnalysisReport: Codable, Sendable {
  public var schemaVersion: Int
  public var id: UUID
  public var status: String
  public var metrics: MeasuredMetrics
  public var explanation: Explanation
  public var endurance: Endurance
  public var missingData: [String]
  public var generatedAt: Date
  public var expiresAt: Date?
  public struct Explanation: Codable, Sendable {
    public var summary: String
    public var insights: [Insight]
    public var nextRun: String
  }
  public struct Insight: Codable, Sendable, Identifiable {
    public var title: String
    public var detail: String
    public var evidence: [String]
    public var id: String { title }
  }
  public struct Endurance: Codable, Sendable {
    public var status: String
    public var detail: String
  }
}
public struct LiveSnapshot: Codable, Sendable {
  public var id: UUID
  public var start: Date
  public var timestamp: Date
  public var elapsed: Double
  public var distance: Double
  public var heartRate: Double?
  public var energy: Double?
  public var paused: Bool
  public var pauses: [Pause]
  public init(
    id: UUID, start: Date, timestamp: Date, elapsed: Double, distance: Double, heartRate: Double?,
    energy: Double?, paused: Bool, pauses: [Pause] = []
  ) {
    self.id = id
    self.start = start
    self.timestamp = timestamp
    self.elapsed = elapsed
    self.distance = distance
    self.heartRate = heartRate
    self.energy = energy
    self.paused = paused
    self.pauses = pauses
  }
}
public struct CoachingTargets: Codable, Sendable {
  public var lowerHeartRate: Double?
  public var upperHeartRate: Double?
  public var targetPaceSecondsPerKm: Double?
  public var haptics: Bool
  public init(
    lowerHeartRate: Double? = nil, upperHeartRate: Double? = nil,
    targetPaceSecondsPerKm: Double? = nil, haptics: Bool = false
  ) {
    self.lowerHeartRate = lowerHeartRate
    self.upperHeartRate = upperHeartRate
    self.targetPaceSecondsPerKm = targetPaceSecondsPerKm
    self.haptics = haptics
  }
  public func cue(heartRate: Double?, pace: Double?) -> String? {
    if let heartRate, let upperHeartRate, heartRate > upperHeartRate {
      return "Above your heart-rate target. Ease your effort."
    }
    if let heartRate, let lowerHeartRate, heartRate < lowerHeartRate {
      return "Below your heart-rate target."
    }
    if let pace, let target = targetPaceSecondsPerKm, abs(pace - target) > 20 {
      return pace < target ? "Faster than your target pace." : "Slower than your target pace."
    }
    return nil
  }
}

public struct WorkoutMessage: Codable, Sendable {
  public var kind: String
  public var snapshot: LiveSnapshot?
  public var targets: CoachingTargets?
  public var command: String?
  public var insight: String?
  public var expiresAt: Date?
  public init(
    kind: String, snapshot: LiveSnapshot? = nil, targets: CoachingTargets? = nil,
    command: String? = nil, insight: String? = nil, expiresAt: Date? = nil
  ) {
    self.kind = kind
    self.snapshot = snapshot
    self.targets = targets
    self.command = command
    self.insight = insight
    self.expiresAt = expiresAt
  }
}

/// Ignore import timestamps and private coordinates while detecting changes to the numerical analysis input.
public enum RunRevision {
  public static func hasSameAnalysisData(_ lhs: RunData, _ rhs: RunData) -> Bool {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    guard let a = try? encoder.encode(AnalysisRequest(run: lhs, history: [])),
      let b = try? encoder.encode(AnalysisRequest(run: rhs, history: []))
    else { return false }
    return a == b
  }
}
