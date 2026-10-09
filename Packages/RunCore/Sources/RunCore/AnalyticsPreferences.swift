import Foundation

public struct AnalyticsPreferences: Codable, Sendable, Equatable {
  public var version = 1
  public var goals: [TrainingGoal] = []
  public var zones: HeartRateZones?
  public var excludedEfforts: Set<String> = []
  public init() {}
}
