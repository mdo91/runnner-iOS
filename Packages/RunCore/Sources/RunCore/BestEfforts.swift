import Foundation

public enum EffortDistance: String, Codable, CaseIterable, Sendable {
  case m400 = "400 m"
  case km1 = "1 km"
  case mile = "1 mile"
  case km5 = "5 km"
  case km10 = "10 km"
  case half = "Half marathon"
  case marathon = "Marathon"
  public var meters: Double {
    switch self {
    case .m400: return 400
    case .km1: return 1000
    case .mile: return 1609.344
    case .km5: return 5000
    case .km10: return 10000
    case .half: return 21097.5
    case .marathon: return 42195
    }
  }
}
public struct BestEffort: Identifiable, Sendable {
  public let runID: UUID
  public let distance: EffortDistance
  public let start: Date
  public let end: Date
  public var seconds: Double { end.timeIntervalSince(start) }
  public var id: String { "\(runID.uuidString):\(distance.rawValue)" }
}
public enum BestEfforts {
  public static func make(run: RunData) -> [BestEffort] {
    guard let timeline = DistanceTimeline(run), let total = timeline.intervals.last?.toMeters else {
      return []
    }
    let pauses = RunCalculator.pauses(run.pauses, from: run.start, to: run.end)
    let gaps = zip(timeline.intervals, timeline.intervals.dropFirst()).compactMap {
      a, b -> DateInterval? in
      let active = RunCalculator.activeSeconds(from: a.end, to: b.start, pauses: pauses)
      return active > 30 ? DateInterval(start: a.end, end: b.start) : nil
    }
    // A single interval cannot justify an effort through a long unexplained recording gap.
    let sparse = timeline.intervals.filter {
      RunCalculator.activeSeconds(from: $0.start, to: $0.end, pauses: pauses) > 30
    }
    // A pause inside an interval adds a breakpoint to the elapsed-time function.
    let boundaries = timeline.intervals.flatMap { [$0.fromMeters, $0.toMeters] }
      + pauses.flatMap { [timeline.distance(at: $0.start), timeline.distance(at: $0.end)] }
        .compactMap { $0 }
    return EffortDistance.allCases.compactMap { distance in
      guard total >= distance.meters else { return nil }
      let candidates = Set(
        ([0, total - distance.meters] + boundaries + boundaries.map { $0 - distance.meters }).filter
        { $0 >= 0 && $0 + distance.meters <= total })
      var best: BestEffort?
      for meters in candidates.sorted() {
        guard let start = timeline.time(at: meters, starting: true),
          let end = timeline.time(at: meters + distance.meters, starting: false), end > start
        else { continue }
        guard !gaps.contains(where: { $0.start < end && $0.end > start }),
          !sparse.contains(where: { $0.start < end && $0.end > start })
        else { continue }
        let effort = BestEffort(runID: run.id, distance: distance, start: start, end: end)
        if best == nil || effort.seconds < best!.seconds { best = effort }
      }
      return best
    }
  }
  public static func ranked(
    _ efforts: [BestEffort], distance: EffortDistance, excluded: Set<String>, year: Int? = nil,
    calendar: Calendar = .current
  ) -> [BestEffort] {
    efforts.filter {
      $0.distance == distance && !excluded.contains($0.id)
        && (year == nil || calendar.component(.year, from: $0.start) == year)
    }.sorted { $0.seconds == $1.seconds ? $0.start < $1.start : $0.seconds < $1.seconds }
  }
}
