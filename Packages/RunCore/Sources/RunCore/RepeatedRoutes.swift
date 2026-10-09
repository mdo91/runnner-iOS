import Foundation

public struct RouteMatch: Identifiable, Sendable {
  public var id: UUID { runID }
  public let runID: UUID
  public let relatedRunIDs: [UUID]
}
public enum RepeatedRoutes {
  private static func resample(_ run: RunData) -> [RoutePoint]? {
    guard !run.indoor, let workout = run.distanceMeters, workout > 0 else { return nil }
    let segments = RunCalculator.routeSegments(run)
    // Require a single trustworthy route, including its start and finish.
    guard segments.count == 1, let points = segments.first, points.count >= 20,
      let first = points.first, let last = points.last,
      RunCalculator.activeSeconds(from: run.start, to: first.timestamp, pauses: run.pauses) <= 30,
      RunCalculator.activeSeconds(from: last.timestamp, to: run.end, pauses: run.pauses) <= 30
    else { return nil }
    var cumulative = [0.0]
    for pair in zip(points, points.dropFirst()) {
      cumulative.append(cumulative.last! + RunCalculator.distance(pair.0, pair.1))
    }
    guard let total = cumulative.last, total > 0, abs(total - workout) / workout <= 0.1 else {
      return nil
    }
    var result: [RoutePoint] = []
    var index = 1
    for step in 0...100 {
      let distance = total * Double(step) / 100
      while index < points.count - 1 && cumulative[index] < distance { index += 1 }
      let fraction =
        (distance - cumulative[index - 1]) / max(0.001, cumulative[index] - cumulative[index - 1])
      let a = points[index - 1]
      let b = points[index]
      result.append(
        RoutePoint(
          timestamp: a.timestamp, latitude: a.latitude + (b.latitude - a.latitude) * fraction,
          longitude: a.longitude + (b.longitude - a.longitude) * fraction))
    }
    return result
  }
  private static func sameDirection(_ a: [RoutePoint], _ b: [RoutePoint], closed: Bool) -> Bool {
    if closed {
      // Ordered proximity alone cannot distinguish opposite directions on small loops.
      func area(_ points: [RoutePoint]) -> Double {
        let origin = points[0]
        return zip(points, points.dropFirst()).reduce(0) { sum, pair in
          sum + (pair.0.longitude - origin.longitude) * (pair.1.latitude - origin.latitude)
            - (pair.1.longitude - origin.longitude) * (pair.0.latitude - origin.latitude)
        }
      }
      let aa = area(a)
      let ab = area(b)
      // Ambiguous self-intersecting loops cannot establish a reliable orientation.
      return abs(aa) > 1e-12 && abs(ab) > 1e-12 && aa * ab > 0
    }
    let forward = zip(a, b).reduce(0) { $0 + RunCalculator.distance($1.0, $1.1) }
    let reverse = zip(a, b.reversed()).reduce(0) { $0 + RunCalculator.distance($1.0, $1.1) }
    return forward < reverse
  }
  public static func match(runs: [RunData]) -> [RouteMatch] {
    let candidates = runs.compactMap { run in resample(run).map { (run, $0) } }
    var related: [UUID: [UUID]] = [:]
    for i in candidates.indices {
      for j in candidates.indices where j > i {
        let a = candidates[i]
        let b = candidates[j]
        guard let da = a.0.distanceMeters, let db = b.0.distanceMeters,
          abs(da - db) / max(da, db) <= 0.1, RunCalculator.distance(a.1.first!, b.1.first!) <= 100,
          RunCalculator.distance(a.1.last!, b.1.last!) <= 100
        else { continue }
        let close = zip(a.1, b.1).filter { RunCalculator.distance($0, $1) <= 60 }.count
        guard Double(close) / Double(a.1.count) >= 0.9 else { continue }
        let closed =
          RunCalculator.distance(a.1.first!, a.1.last!) <= min(100, da * 0.05)
          && RunCalculator.distance(b.1.first!, b.1.last!) <= min(100, db * 0.05)
        guard sameDirection(a.1, b.1, closed: closed) else { continue }
        related[a.0.id, default: []].append(b.0.id)
        related[b.0.id, default: []].append(a.0.id)
      }
    }
    return related.map { RouteMatch(runID: $0.key, relatedRunIDs: $0.value) }
  }
}
