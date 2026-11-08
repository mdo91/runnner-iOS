import Foundation

public enum ActivityMetric: String, CaseIterable, Codable, Sendable {
  case runs = "Runs"
  case distance = "Distance"
  case movingTime = "Moving Time"
  case elevation = "Elevation Gain"
  public func value(_ summary: ActivitySummary, units: UnitSystem) -> Double? {
    switch self {
    case .runs: return Double(summary.runCount)
    case .distance: return summary.distanceMeters.map { $0 / units.metersPerUnit }
    case .movingTime: return summary.movingTimeSeconds.map { $0 / 60 }
    case .elevation: return summary.elevationGainMeters.map { $0 / units.metersPerElevationUnit }
    }
  }
  public func unit(_ units: UnitSystem) -> String {
    switch self {
    case .runs: return "Common.Copy.runs.text".localized
    case .distance: return units.distanceUnit
    case .movingTime: return "min"
    case .elevation: return units.elevationUnit
    }
  }
  public func formatted(_ summary: ActivitySummary, units: UnitSystem) -> String {
    switch self {
    case .runs: return "Common.Count.runs.text".localized(summary.runCount)
    case .distance: return "\(units.distance(summary.distanceMeters)) \(units.distanceUnit)"
    case .movingTime: return summary.movingTimeSeconds.map(UnitSystem.duration) ?? "—"
    case .elevation: return "\(units.elevation(summary.elevationGainMeters)) \(units.elevationUnit)"
    }
  }
  public func missingCount(_ summary: ActivitySummary) -> Int {
    switch self {
    case .runs: return 0
    case .distance: return summary.missingDistanceCount
    case .movingTime: return summary.missingTimeCount
    case .elevation: return summary.missingElevationCount
    }
  }
}
extension UnitSystem {
  public var elevationUnit: String { self == .metric ? "m" : "ft" }
  public var metersPerElevationUnit: Double { self == .metric ? 1 : 0.3048 }
  public func elevation(_ meters: Double?) -> String {
    meters.map { String(format: "%.0f", locale: Locale.current, $0 / metersPerElevationUnit) } ?? "—"
  }
}

extension ActivityMetric {
  public var title: String {
    switch self {
    case .runs: return "Common.Copy.runs.text".localized
    case .distance: return "Common.Copy.distance.text".localized
    case .movingTime: return "Common.Copy.movingTime3.text".localized
    case .elevation: return "Common.Copy.elevationGain.text".localized
    }
  }
}
