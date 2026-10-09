#if DEBUG
  import Foundation
  import RunCore
  import SwiftData

  enum PreviewFixtures {
    static var enabled: Bool { AppRuntime.isFixture }
    @MainActor static func install(in context: ModelContext) throws {
      guard AppRuntime.scenario != "empty" else { return }
      for (index, day) in [1, 3, 6, 12, 20, 28, 50, 100, 200].enumerated() {
        let start = AppRuntime.calendar.date(byAdding: .day, value: -day, to: AppRuntime.now)!
          .addingTimeInterval(-3600)
        let active = Double(1500 + index * 30)
        let paused = AppRuntime.scenario == "paused" && index == 0
        let pauseSeconds = paused ? 90.0 : 0
        func wall(_ t: Double, end: Bool = false) -> Double {
          t + (paused && (end ? t > active / 2 : t >= active / 2) ? pauseSeconds : 0)
        }
        let partial = AppRuntime.scenario == "partial"
        let indoor = AppRuntime.scenario == "indoor" && index == 0
        let heart = (0..<Int(active / 5)).map { i in
          TimedValue(
            start: start.addingTimeInterval(wall(Double(i) * 5)),
            value: 140 + Double(index) + sin(Double(i) / 30) * 8)
        }
        let distances = (0..<100).map { i in
          TimedValue(
            start: start.addingTimeInterval(wall(Double(i) * active / 100)),
            end: start.addingTimeInterval(wall(Double(i + 1) * active / 100, end: true)), value: 50)
        }
        let route = (0..<500).map { i in
          let t = Double(i) / 499 * Double.pi * 2
          return RoutePoint(
            timestamp: start.addingTimeInterval(wall(Double(i) * active / 499)),
            latitude: 41.175 + sin(t) * 0.007157, longitude: 28.985 + cos(t) * 0.00951,
            altitude: 50 + sin(t) * 12, verticalAccuracy: 4, speed: 5000 / active)
        }
        func samples(_ base: Double, amplitude: Double) -> [TimedValue] {
          heart.enumerated().map { i, value in
            TimedValue(start: value.start, value: base + sin(Double(i) / 20) * amplitude)
          }
        }
        let run = RunData(
          id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!,
          start: start, end: start.addingTimeInterval(active + pauseSeconds), duration: active,
          distanceMeters: partial && index == 0 ? nil : 5000, activeEnergyKcal: 382 + Double(index),
          source: AppRuntime.scenario == "mixed-source" && index.isMultiple(of: 3)
            ? "Fixture Garmin" : "Fixture Apple Watch", indoor: indoor,
          heartRate: partial && index < 2 ? [] : heart,
          distances: partial && index == 0 ? [] : distances,
          pauses: paused
            ? [
              Pause(
                start: start.addingTimeInterval(active / 2),
                end: start.addingTimeInterval(active / 2 + pauseSeconds))
            ] : [],
          route: indoor || (partial && index == 0) ? [] : route,
          dynamics: partial && index == 0
            ? [:]
            : [
              "HKQuantityTypeIdentifierRunningSpeed": samples(5000 / active, amplitude: 0.15),
              "HKQuantityTypeIdentifierRunningPower": samples(240, amplitude: 25),
              "HKQuantityTypeIdentifierRunningStrideLength": samples(1.1, amplitude: 0.05),
              "HKQuantityTypeIdentifierRunningGroundContactTime": samples(0.24, amplitude: 0.01),
              "HKQuantityTypeIdentifierRunningVerticalOscillation": samples(0.08, amplitude: 0.005),
            ])
        context.insert(try RecordedRun(run))
      }
      for (day, value) in [(1, 45.8), (30, 44.9), (90, 44.0)] {
        context.insert(
          HealthMeasurement(
            id: UUID(), kind: "HKQuantityTypeIdentifierVO2Max", value: value,
            date: AppRuntime.calendar.date(byAdding: .day, value: -day, to: AppRuntime.now)!))
        context.insert(
          HealthMeasurement(
            id: UUID(), kind: "HKQuantityTypeIdentifierHeartRateRecoveryOneMinute",
            value: 30 + value / 10,
            date: AppRuntime.calendar.date(byAdding: .day, value: -day, to: AppRuntime.now)!))
      }
      context.insert(
        CloudSyncCheckpoint(key: "fixture-checkpoint", payloadDigest: "fixture-digest"))
      try context.save()
      _ = try context.fetch(FetchDescriptor<CloudSyncCheckpoint>())
    }
  }
#endif
