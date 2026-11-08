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
  public func title(language: AppLanguage = .current) -> String {
    let metricKey: String
    switch metric {
    case .runs: metricKey = "runs"
    case .distance: metricKey = "distance"
    case .movingTime: metricKey = "movingTime"
    case .elevation: metricKey = "elevation"
    }
    return "TrainingGoal.Title.\(period.rawValue.lowercased()).\(metricKey).text".localized(language: language)
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

extension GoalPeriod {
  public var title: String {
    switch self {
    case .week: return "Common.Copy.weekly.text".localized
    case .month: return "Common.Copy.monthly.text".localized
    case .year: return "Common.Copy.annual.text".localized
    }
  }
}
