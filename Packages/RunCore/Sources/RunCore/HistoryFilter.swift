import Foundation

public enum RunSort: String, CaseIterable, Sendable {
  case date = "Date"
  case distance = "Distance"
  case pace = "Pace"
}
public enum RunSetting: String, CaseIterable, Sendable {
  case all = "All"
  case outdoor = "Outdoor"
  case indoor = "Indoor"
}
public struct HistoryFilter: Sendable {
  public var interval: DateInterval?
  public var setting: RunSetting = .all
  public var source: String?
  public var minimumMeters: Double = 0
  public var maximumMeters: Double?
  public var sort: RunSort = .date
  public init() {}
  public func apply(to runs: [RunData], metrics: [UUID: MeasuredMetrics]) -> [RunData] {
    runs.filter { run in
      guard run.duration.isFinite, run.duration > 0 else { return false }
      if let interval, !(run.start >= interval.start && run.start < interval.end) { return false }
      if setting == .indoor && !run.indoor || setting == .outdoor && run.indoor { return false }
      if let source, source != run.source { return false }
      if minimumMeters > 0 || maximumMeters != nil {
        guard let distance = run.distanceMeters, distance.isFinite, distance >= minimumMeters else {
          return false
        }
        if let maximumMeters, distance > maximumMeters { return false }
      }
      return true
    }.sorted { a, b in
      switch sort {
      case .date: return a.start > b.start
      case .distance:
        let x = metrics[a.id]?.distanceMeters ?? -.infinity
        let y = metrics[b.id]?.distanceMeters ?? -.infinity
        return x == y ? a.start > b.start : x > y
      case .pace:
        let x = metrics[a.id]?.averagePaceSecondsPerKm ?? .infinity
        let y = metrics[b.id]?.averagePaceSecondsPerKm ?? .infinity
        return x == y ? a.start > b.start : x < y
      }
    }
  }
}
