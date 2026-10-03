import Foundation

public struct DensityCell: Identifiable, Sendable {
  public var id: String
  public var latitude: Double
  public var longitude: Double
  public var runs: Int
}
public enum RouteDensity {
  public static func cells(runs: [RunData]) -> [DensityCell] {
    var counts: [String: (Int, Int, Int)] = [:]
    let radius = 6_371_000.0
    let size = 100.0
    func cell(_ point: RoutePoint) -> (Int, Int) {
      let latitude = min(85, max(-85, point.latitude)) * Double.pi / 180
      return (
        Int(floor(radius * point.longitude * Double.pi / 180 / size)),
        Int(floor(radius * log(tan(Double.pi / 4 + latitude / 2)) / size))
      )
    }
    for run in runs {
      var visited: Set<String> = []
      for segment in RunCalculator.routeSegments(run) {
        for index in 1..<segment.count {
          let a = segment[index - 1]
          let b = segment[index]
          let steps = max(1, Int(ceil(RunCalculator.distance(a, b) / 25)))
          for step in 0...steps {
            let t = Double(step) / Double(steps)
            let p = RoutePoint(
              timestamp: a.timestamp, latitude: a.latitude + (b.latitude - a.latitude) * t,
              longitude: a.longitude + (b.longitude - a.longitude) * t)
            let (x, y) = cell(p)
            let key = "\(x):\(y)"
            if visited.insert(key).inserted {
              let old = counts[key]?.2 ?? 0
              counts[key] = (x, y, old + 1)
            }
          }
        }
      }
    }
    return counts.map { key, value in
      DensityCell(
        id: key,
        latitude: (2 * atan(exp((Double(value.1) + 0.5) * size / radius)) - Double.pi / 2) * 180
          / Double.pi, longitude: (Double(value.0) + 0.5) * size / radius * 180 / Double.pi,
        runs: value.2)
    }.sorted { $0.runs > $1.runs }
  }
}
