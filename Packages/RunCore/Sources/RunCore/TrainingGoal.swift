import Foundation

public struct TrainingGoal: Codable, Identifiable, Sendable, Equatable {
  public var id: UUID = UUID()
  public var metric: ActivityMetric
  public var period: GoalPeriod
  /// SI units: runs, meters, seconds, or meters of elevation.
  public var target: Double
  public init(metric: ActivityMetric, period: GoalPeriod, target: Double) {
    self.metric = metric
    self.period = period
    self.target = target
  }
  public func progress(in statistics: ActivityStatistics) -> Double? {
    let summary = statistics.summary(in: statistics.period(period.component))
    switch metric {
    case .runs: return Double(summary.runCount)
    case .distance: return summary.distanceMeters
    case .movingTime: return summary.movingTimeSeconds
    case .elevation: return summary.elevationGainMeters
    }
  }
}
public enum GoalPeriod: String, Codable, CaseIterable, Sendable {
  case week = "Weekly"
  case month = "Monthly"
  case year = "Annual"
  public var component: Calendar.Component {
    self == .week ? .weekOfYear : self == .month ? .month : .year
  }
}
