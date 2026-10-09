import CoreLocation
import Foundation
import HealthKit
import RunCore
import SwiftData

@MainActor final class HealthKitManager: ObservableObject {
  let healthStore = HKHealthStore()
  @Published var isSyncing = false
  @Published var status: String?
  @Published var didRequestAccess = AppRuntime.defaults.bool(forKey: "healthRequested")
  @Published var importedCount = 0
  private var context: ModelContext?
  private var observers: [HKQuery] = []
  private var needsAnotherSync = false
  var onLatestImported: ((UUID) -> Void)?
  private let quantityTypes: [(HKQuantityTypeIdentifier, HKUnit)] = [
    (.heartRate, HKUnit.count().unitDivided(by: .minute())), (.distanceWalkingRunning, .meter()),
    (.runningSpeed, HKUnit.meter().unitDivided(by: .second())), (.runningPower, .watt()),
    (.runningStrideLength, .meter()), (.runningGroundContactTime, .second()),
    (.runningVerticalOscillation, .meter()),
  ]
  var readTypes: Set<HKObjectType> {
    Set(
      quantityTypes.compactMap { HKQuantityType.quantityType(forIdentifier: $0.0) } + [
        HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!,
        HKQuantityType.quantityType(forIdentifier: .vo2Max)!,
        HKQuantityType.quantityType(forIdentifier: .heartRateRecoveryOneMinute)!,
      ]
    )
    .union([HKObjectType.workoutType(), HKSeriesType.workoutRoute()])
  }
  func configure(_ context: ModelContext) {
    self.context = context
    startObserving()
  }
  func requestAccess() async {
    guard !AppRuntime.isFixture else { status = "Health access is simulated for UI tests."; return }
    guard HKHealthStore.isHealthDataAvailable() else {
      status = "Health data is unavailable on this device."
      return
    }
    do {
      try await healthStore.requestAuthorization(toShare: [], read: readTypes)
      didRequestAccess = true
      AppRuntime.defaults.set(true, forKey: "healthRequested")
      // Completion means the sheet finished. Apple intentionally does not disclose read authorization.
      await sync()
    } catch { status = "Health access could not be requested. You can try again in Settings." }
  }
  private func startObserving() {
    guard observers.isEmpty, HKHealthStore.isHealthDataAvailable() else { return }
    for type in [HKObjectType.workoutType(), HKSeriesType.workoutRoute()] {
      let query = HKObserverQuery(sampleType: type, predicate: nil) {
        [weak self] _, completion, error in
        Task { @MainActor in
          if error == nil { await self?.sync() }
          completion()
        }
      }
      observers.append(query)
      healthStore.execute(query)
      healthStore.enableBackgroundDelivery(for: type, frequency: .immediate) { _, _ in }
    }
  }
  func sync() async {
    guard !AppRuntime.isFixture else { return }
    guard didRequestAccess, let context else { return }
    guard !isSyncing else {
      needsAnotherSync = true
      return
    }
    isSyncing = true
    status = nil
    defer {
      isSyncing = false
      if needsAnotherSync {
        needsAnotherSync = false
        Task { await sync() }
      }
    }
    do {
      let latest = try await workouts(limit: 1)
      if let first = latest.first {
        try await persist(first, context: context)
        onLatestImported?(first.uuid)
      }
      let checkpoint =
        try context.fetch(FetchDescriptor<HealthCheckpoint>()).first(where: { $0.key == "workouts" }
        ) ?? HealthCheckpoint(key: "workouts")
      if checkpoint.modelContext == nil { context.insert(checkpoint) }
      var anchor = checkpoint.anchor.flatMap {
        try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: $0)
      }
      while !Task.isCancelled {
        let (added, deleted, next) = try await changes(anchor: anchor)
        for workout in added where workout.uuid != latest.first?.uuid {
          try await persist(workout, context: context)
        }
        for object in deleted {
          let id = object.uuid
          context.insert(DeletedHealthRecord(id:id,kind:"run"))
          if let row = try context.fetch(
            FetchDescriptor<RecordedRun>(predicate: #Predicate { $0.id == id })
          ).first {
            context.delete(row)
          }
        }
        checkpoint.anchor = try NSKeyedArchiver.archivedData(
          withRootObject: next, requiringSecureCoding: true)
        try context.save()
        anchor = next
        importedCount += added.count
        if added.count + deleted.count < 40 { break }
      }
      // Samples and routes may arrive after the workout. Rehydrate recent runs on every foreground sync.
      for workout in try await workouts(limit: 12) where workout.uuid != latest.first?.uuid {
        try await persist(workout, context: context)
      }
      try await syncRoutes(context)
      try await syncMeasurements(context)
    } catch { status = "Sync paused. Your saved runs remain available. Pull to refresh to retry." }
  }
  private func workouts(limit: Int) async throws -> [HKWorkout] {
    try await samples(
      type: HKObjectType.workoutType(), predicate: HKQuery.predicateForWorkouts(with: .running),
      limit: limit) as? [HKWorkout] ?? []
  }
  private func samples(
    type: HKSampleType, predicate: NSPredicate?, limit: Int = HKObjectQueryNoLimit
  ) async throws -> [HKSample] {
    try await withCheckedThrowingContinuation { continuation in
      let query = HKSampleQuery(
        sampleType: type, predicate: predicate, limit: limit,
        sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
      ) { _, values, error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume(returning: values ?? [])
        }
      }
      healthStore.execute(query)
    }
  }
  private func changes(anchor: HKQueryAnchor?) async throws -> (
    [HKWorkout], [HKDeletedObject], HKQueryAnchor
  ) {
    try await withCheckedThrowingContinuation { continuation in
      let query = HKAnchoredObjectQuery(
        type: HKObjectType.workoutType(), predicate: HKQuery.predicateForWorkouts(with: .running),
        anchor: anchor, limit: 40,
        resultsHandler: { _, added, deleted, next, error in
          if let error {
            continuation.resume(throwing: error)
          } else if let next {
            continuation.resume(returning: (added as? [HKWorkout] ?? [], deleted ?? [], next))
          } else {
            continuation.resume(throwing: ImportError.missingAnchor)
          }
        })
      healthStore.execute(query)
    }
  }
  private func persist(_ workout: HKWorkout, context: ModelContext) async throws {
    let predicate = HKQuery.predicateForObjects(from: workout)
    var values: [String: [TimedValue]] = [:]
    for (identifier, unit) in quantityTypes {
      let samples = try await samples(
        type: HKQuantityType.quantityType(forIdentifier: identifier)!, predicate: predicate)
      values[identifier.rawValue] = (samples as? [HKQuantitySample] ?? []).map {
        TimedValue(start: $0.startDate, end: $0.endDate, value: $0.quantity.doubleValue(for: unit))
      }
    }
    var pauses: [Pause] = []
    var pauseStart: Date?
    for event in (workout.workoutEvents ?? []).sorted(by: {
      $0.dateInterval.start < $1.dateInterval.start
    }) {
      if event.type == .pause || event.type == .motionPaused {
        pauseStart = pauseStart ?? event.dateInterval.start
      }
      if event.type == .resume || event.type == .motionResumed, let start = pauseStart {
        pauses.append(Pause(start: start, end: event.dateInterval.start))
        pauseStart = nil
      }
    }
    if let pauseStart { pauses.append(Pause(start: pauseStart, end: workout.endDate)) }
    var route: [RoutePoint] = []
    let routes =
      try await samples(type: HKSeriesType.workoutRoute(), predicate: predicate)
      as? [HKWorkoutRoute] ?? []
    for (index, sample) in routes.sorted(by: { $0.startDate < $1.startDate }).enumerated() {
      let points = try await routeLocations(sample)
      route += points.map {
        RoutePoint(
          timestamp: $0.timestamp, latitude: $0.coordinate.latitude,
          longitude: $0.coordinate.longitude, altitude: $0.altitude,
          horizontalAccuracy: $0.horizontalAccuracy, verticalAccuracy: $0.verticalAccuracy,
          speed: $0.speed >= 0 ? $0.speed : nil, segment: index)
      }
    }
    let heart = values.removeValue(forKey: HKQuantityTypeIdentifier.heartRate.rawValue) ?? []
    let distance =
      values.removeValue(forKey: HKQuantityTypeIdentifier.distanceWalkingRunning.rawValue) ?? []
    let run = RunData(
      id: workout.uuid, start: workout.startDate, end: workout.endDate, duration: workout.duration,
      distanceMeters: workout.statistics(
        for: HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!)?.sumQuantity()?
        .doubleValue(for: .meter()) ?? workout.totalDistance?.doubleValue(for: .meter()),
      activeEnergyKcal: workout.statistics(
        for: HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!)?.sumQuantity()?
        .doubleValue(for: .kilocalorie()),
      source: workout.sourceRevision.source.name,
      sourceBundle: workout.sourceRevision.source.bundleIdentifier,
      indoor: workout.metadata?[HKMetadataKeyIndoorWorkout] as? Bool ?? false, heartRate: heart,
      distances: distance, pauses: pauses, route: route, dynamics: values)
    let id = workout.uuid
    if let row = try context.fetch(
      FetchDescriptor<RecordedRun>(predicate: #Predicate { $0.id == id })
    ).first {
      try row.update(run)
      if !run.route.isEmpty { row.routeDeleted = false }
    } else {
      context.insert(try RecordedRun(run))
    }
    try context.save()
  }
  private enum ImportError: Error { case missingAnchor }
  private func routeLocations(_ route: HKWorkoutRoute) async throws -> [CLLocation] {
    try await withCheckedThrowingContinuation { continuation in
      let buffer = RouteBuffer()
      let query = HKWorkoutRouteQuery(route: route) { _, locations, done, error in
        if let error {
          if buffer.fail() { continuation.resume(throwing: error) }
          return
        }
        if let points = buffer.append(locations ?? [], done: done) {
          continuation.resume(returning: points)
        }
      }
      healthStore.execute(query)
    }
  }
  private func syncRoutes(_ context: ModelContext) async throws {
    let checkpoint =
      try context.fetch(FetchDescriptor<HealthCheckpoint>()).first(where: { $0.key == "routes" })
      ?? HealthCheckpoint(key: "routes")
    if checkpoint.modelContext == nil { context.insert(checkpoint) }
    var anchor = checkpoint.anchor.flatMap {
      try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: $0)
    }
    while !Task.isCancelled {
      let (added, deleted, next): ([HKWorkoutRoute], [HKDeletedObject], HKQueryAnchor) =
        try await withCheckedThrowingContinuation { continuation in
          let query = HKAnchoredObjectQuery(
            type: HKSeriesType.workoutRoute(), predicate: nil, anchor: anchor, limit: 40,
            resultsHandler: { _, samples, deleted, next, error in
              if let error {
                continuation.resume(throwing: error)
              } else if let next {
                continuation.resume(
                  returning: (samples as? [HKWorkoutRoute] ?? [], deleted ?? [], next))
              } else {
                continuation.resume(throwing: ImportError.missingAnchor)
              }
            })
          healthStore.execute(query)
        }
      // Route updates can arrive for any historical run, not just the latest page.
      for route in added {
        let dates = HKQuery.predicateForSamples(
          withStart: route.startDate.addingTimeInterval(-1),
          end: route.endDate.addingTimeInterval(1), options: [])
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
          dates, HKQuery.predicateForWorkouts(with: .running),
        ])
        for workout in try await samples(type: HKObjectType.workoutType(), predicate: predicate)
          as? [HKWorkout] ?? []
        { try await persist(workout, context: context) }
      }
      if !deleted.isEmpty {
        // A deleted route does not expose its workout ID. Reconcile cached outdoor runs conservatively.
        for row in try context.fetch(FetchDescriptor<RecordedRun>())
        where row.run?.route.isEmpty == false {
          let id = row.id
          let predicate = HKQuery.predicateForObject(with: id)
          if let workout = try await samples(
            type: HKObjectType.workoutType(), predicate: predicate, limit: 1
          ).first as? HKWorkout {
            try await persist(workout, context: context)
            if row.run?.route.isEmpty == true { row.routeDeleted = true }
          }
        }
      }
      checkpoint.anchor = try NSKeyedArchiver.archivedData(
        withRootObject: next, requiringSecureCoding: true)
      try context.save()
      anchor = next
      if added.count + deleted.count < 40 { break }
    }
  }
  private func syncMeasurements(_ context: ModelContext) async throws {
    let kinds: [(HKQuantityTypeIdentifier, HKUnit)] = [
      (.vo2Max, HKUnit(from: "ml/kg*min")),
      (.heartRateRecoveryOneMinute, HKUnit.count().unitDivided(by: .minute())),
    ]
    for (kind, unit) in kinds {
      let type = HKQuantityType.quantityType(forIdentifier: kind)!
      let key = "measurement-" + kind.rawValue
      let checkpoint = try context.fetch(FetchDescriptor<HealthCheckpoint>()).first { $0.key == key } ?? HealthCheckpoint(key:key)
      if checkpoint.modelContext == nil { context.insert(checkpoint) }
      var anchor = checkpoint.anchor.flatMap { try? NSKeyedUnarchiver.unarchivedObject(ofClass:HKQueryAnchor.self,from:$0) }
      while !Task.isCancelled {
        let (values,deleted,next): ([HKQuantitySample],[HKDeletedObject],HKQueryAnchor) = try await withCheckedThrowingContinuation { continuation in
          let query = HKAnchoredObjectQuery(type:type,predicate:nil,anchor:anchor,limit:100) { _, samples, deleted, next, error in
            if let error { continuation.resume(throwing:error) }
            else if let next { continuation.resume(returning:(samples as? [HKQuantitySample] ?? [],deleted ?? [],next)) }
            else { continuation.resume(throwing:ImportError.missingAnchor) }
          }
          healthStore.execute(query)
        }
        for value in values {
          let id = value.uuid
          if let row = try context.fetch(FetchDescriptor<HealthMeasurement>(predicate:#Predicate { $0.id == id })).first {
            row.value = value.quantity.doubleValue(for:unit); row.date = value.endDate
          } else {
            context.insert(HealthMeasurement(id:id,kind:kind.rawValue,value:value.quantity.doubleValue(for:unit),date:value.endDate))
          }
        }
        for value in deleted {
          let id = value.uuid
          context.insert(DeletedHealthRecord(id:id,kind:"measurement"))
          if let row = try context.fetch(FetchDescriptor<HealthMeasurement>(predicate:#Predicate { $0.id == id })).first { context.delete(row) }
        }
        checkpoint.anchor = try NSKeyedArchiver.archivedData(withRootObject:next,requiringSecureCoding:true)
        try context.save(); anchor = next
        if values.count + deleted.count < 100 { break }
      }
    }
    try context.save()
  }
}

private final class RouteBuffer: @unchecked Sendable {
  private let lock = NSLock()
  private var points: [CLLocation] = []
  private var finished = false
  func append(_ values: [CLLocation], done: Bool) -> [CLLocation]? {
    lock.lock()
    defer { lock.unlock() }
    guard !finished else { return nil }
    points += values
    if done {
      finished = true
      return points
    }
    return nil
  }
  func fail() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard !finished else { return false }
    finished = true
    return true
  }
}
