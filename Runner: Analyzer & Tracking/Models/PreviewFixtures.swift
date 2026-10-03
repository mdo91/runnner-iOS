#if DEBUG
  import Foundation
  import SwiftData
  import RunCore

  enum PreviewFixtures {
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("--runner-fixtures") }
    @MainActor static func install(in context: ModelContext) throws {
      for day in 0..<9 {
        let start = Calendar.current.date(byAdding: .day, value: -day * 3, to: Date())!
          .addingTimeInterval(-3600)
        let duration = Double(1550 + day * 12)
        let distance = 5000.0
        let hr = (0..<Int(duration / 5)).map { i in
          TimedValue(
            start: start.addingTimeInterval(Double(i) * 5),
            value: 142 + sin(Double(i) / 30) * 9 + Double(i) / 70)
        }
        let distances = (0..<100).map { i in
          TimedValue(
            start: start.addingTimeInterval(Double(i) * duration / 100),
            end: start.addingTimeInterval(Double(i + 1) * duration / 100), value: distance / 100)
        }
        let route = (0..<500).map { i in
          let t = Double(i) / 499 * Double.pi * 2
          return RoutePoint(
            timestamp: start.addingTimeInterval(Double(i) * duration / 499),
            latitude: 41.175 + sin(t) * 0.006, longitude: 28.985 + cos(t) * 0.014,
            altitude: 50 + sin(t) * 12, verticalAccuracy: 4, speed: 3.2 + sin(t) * 0.3)
        }
        let run = RunData(
          start: start, end: start.addingTimeInterval(duration), duration: duration,
          distanceMeters: distance, activeEnergyKcal: 382 + Double(day),
          source: "Preview Apple Watch", heartRate: hr, distances: distances, route: route)
        context.insert(try RecordedRun(run))
      }
      context.insert(
        HealthMeasurement(
          id: UUID(), kind: "HKQuantityTypeIdentifierVO2Max", value: 45.8,
          date: Date().addingTimeInterval(-86400)))
      context.insert(
        HealthMeasurement(
          id: UUID(), kind: "HKQuantityTypeIdentifierVO2Max", value: 44.9,
          date: Date().addingTimeInterval(-30 * 86400)))
      try context.save()
    }
  }
#endif
