import CoreLocation
import Foundation
import HealthKit
import RunCore
import WatchConnectivity
import WatchKit

@MainActor final class WorkoutRecorder: NSObject, ObservableObject {
  static let shared = WorkoutRecorder()
  enum Phase { case ready, starting, running, paused, review, saving, saved }
  @Published var phase: Phase = .ready
  @Published var snapshot: LiveSnapshot?
  @Published var message: String?
  @Published var cue: String?
  @Published var aiInsight: String?
  @Published var indoor = false
  @Published var units: UnitSystem = .metric
  private let health = HKHealthStore(), location = CLLocationManager()
  private var session: HKWorkoutSession?, builder: HKLiveWorkoutBuilder?,
    routeBuilder: HKWorkoutRouteBuilder?
  private var timer: Timer?, started: Date?, ended: Date?, lastMirror = Date.distantPast,
    lastSend = Date.distantPast, lastHaptic = Date.distantPast
  private var sessionID = UUID(), heart: Double?, distance = 0.0, energy: Double?,
    lastHeartDate: Date?, aiExpiry: Date?
  private var targets = CoachingTargets(), mirrorConnected = false, routeHasPoints = false,
    saving = false
  private var savedWorkout: HKWorkout?
  private var collectionEnded = false
  private var pauses: [Pause] = []
  private var pauseStart: Date?
  override init() {
    super.init()
    location.delegate = self
    location.desiredAccuracy = kCLLocationAccuracyBest
    location.distanceFilter = 5
    if let data = UserDefaults.standard.data(forKey: "targets"),
      let value = try? JSONDecoder().decode(CoachingTargets.self, from: data)
    {
      targets = value
    }
    if WCSession.isSupported() {
      WCSession.default.delegate = self
      WCSession.default.activate()
    }
  }
  func start() async {
    guard phase == .ready || phase == .saved else { return }
    phase = .starting
    message = nil
    do {
      let types: Set<HKSampleType> = [
        .workoutType(), HKSeriesType.workoutRoute(),
        HKQuantityType.quantityType(forIdentifier: .heartRate)!,
        HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!,
        HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!,
      ]
      try await health.requestAuthorization(toShare: types, read: types)
      let configuration = HKWorkoutConfiguration()
      configuration.activityType = .running
      configuration.locationType = indoor ? .indoor : .outdoor
      let session = try HKWorkoutSession(healthStore: health, configuration: configuration)
      let builder = session.associatedWorkoutBuilder()
      builder.dataSource = HKLiveWorkoutDataSource(
        healthStore: health, workoutConfiguration: configuration)
      self.session = session
      self.builder = builder
      session.delegate = self
      builder.delegate = self
      routeBuilder = indoor ? nil : HKWorkoutRouteBuilder(healthStore: health, device: .local())
      sessionID = UUID()
      UserDefaults.standard.set(sessionID.uuidString, forKey: "activeSessionID")
      heart = nil
      distance = 0
      energy = nil
      routeHasPoints = false
      ended = nil
      aiInsight = nil
      savedWorkout = nil
      collectionEnded = false
      pauses = []
      pauseStart = nil
      cue = nil
      mirrorConnected = false
      let date = Date()
      started = date
      session.startActivity(with: date)
      try await builder.beginCollection(at: date)
      phase = .running
      if !indoor {
        location.requestWhenInUseAuthorization()
        location.startUpdatingLocation()
      }
      startTimer()
      await mirror()
    } catch {
      message = "The run could not start. Check Health permissions and try again."
      session?.end()
      phase = .ready
    }
  }
  func recover() async {
    do {
      guard let active = try await health.recoverActiveWorkoutSession() else { return }
      session = active
      builder = active.associatedWorkoutBuilder()
      active.delegate = self
      builder?.delegate = self
      started = active.startDate
      sessionID =
        UserDefaults.standard.string(forKey: "activeSessionID").flatMap(UUID.init(uuidString:))
        ?? UUID()
      indoor = active.workoutConfiguration.locationType == .indoor
      phase = active.state == .paused ? .paused : .running
      for event in builder?.workoutEvents ?? [] {
        if event.type == .pause || event.type == .motionPaused {
          pauseStart = pauseStart ?? event.dateInterval.start
        }
        if event.type == .resume || event.type == .motionResumed, let pauseStart {
          pauses.append(Pause(start: pauseStart, end: event.dateInterval.start))
          self.pauseStart = nil
        }
      }
      // A new route series after recovery preserves the gap rather than connecting unknown GPS data.
      if !indoor {
        routeBuilder = HKWorkoutRouteBuilder(healthStore: health, device: .local())
        location.startUpdatingLocation()
      }
      startTimer()
      await mirror()
    } catch { message = "The interrupted workout could not be recovered." }
  }
  func pauseOrResume() {
    if phase == .running { session?.pause() } else if phase == .paused { session?.resume() }
  }
  func end() {
    guard phase == .running || phase == .paused else { return }
    ended = Date()
    location.stopUpdatingLocation()
    session?.end()
    timer?.invalidate()
    updateSnapshot()
  }
  func save() async {
    guard phase == .review, !saving, let builder else { return }
    saving = true
    phase = .saving
    defer { saving = false }
    do {
      if !collectionEnded {
        try await builder.endCollection(at: ended ?? Date())
        collectionEnded = true
      }
      // Retain the committed workout if only its route fails. A retry must never finish a second workout.
      if savedWorkout == nil { savedWorkout = try await builder.finishWorkout() }
      guard let workout = savedWorkout else { throw SaveError.noWorkout }
      if let routeBuilder, routeHasPoints {
        _ = try await routeBuilder.finishRoute(with: workout, metadata: nil)
        self.routeBuilder = nil
        routeHasPoints = false
      }
      phase = .saved
      message = "Saved to Apple Health. It will appear on your iPhone after Health sync."
      if WCSession.default.activationState == .activated {
        WCSession.default.transferUserInfo(["workoutSaved": true])
      }
      UserDefaults.standard.removeObject(forKey: "activeSessionID")
    } catch {
      phase = .review
      message = "Saving did not finish. Tap Save to retry."
    }
  }
  private enum SaveError: Error { case noWorkout }
  private func startTimer() {
    timer?.invalidate()
    timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.tick() }
    }
  }
  private func tick() {
    updateSnapshot()
    if let aiExpiry, aiExpiry < Date() { aiInsight = nil }
    if Date().timeIntervalSince(lastSend) >= 5 {
      lastSend = Date()
      Task { await sendSnapshot() }
    }
    if !mirrorConnected, Date().timeIntervalSince(lastMirror) > 30 { Task { await mirror() } }
  }
  private func updateSnapshot() {
    guard let started, let builder else { return }
    let now = ended ?? Date()
    let elapsed = builder.elapsedTime(at: now)
    let currentHR = lastHeartDate.map { now.timeIntervalSince($0) < 30 } == true ? heart : nil
    snapshot = LiveSnapshot(
      id: sessionID, start: started, timestamp: now, elapsed: elapsed, distance: distance,
      heartRate: currentHR, energy: energy, paused: phase == .paused,
      pauses: pauses + (pauseStart.map { [Pause(start: $0, end: now)] } ?? []))
    cue =
      phase != .running
      ? nil
      : targets.cue(heartRate: currentHR, pace: distance > 100 ? elapsed / distance * 1000 : nil)
    if cue != nil, targets.haptics, Date().timeIntervalSince(lastHaptic) > 60 {
      WKInterfaceDevice.current().play(.notification)
      lastHaptic = Date()
    }
  }
  private func mirror() async {
    lastMirror = Date()
    do {
      try await session?.startMirroringToCompanionDevice()
      mirrorConnected = true
      await sendSnapshot()
    } catch { mirrorConnected = false }
  }
  private func sendSnapshot() async {
    guard let session, let snapshot,
      let data = try? JSONEncoder().encode(WorkoutMessage(kind: "snapshot", snapshot: snapshot))
    else { return }
    do { try await session.sendToRemoteWorkoutSession(data: data) } catch {
      mirrorConnected = false
    }
  }
  private func receive(_ packet: WorkoutMessage) {
    if packet.kind == "targets", let value = packet.targets {
      targets = value
      UserDefaults.standard.set(try? JSONEncoder().encode(value), forKey: "targets")
    }
    if packet.kind == "command" {
      if packet.command == "pause" && phase == .running { session?.pause() }
      if packet.command == "resume" && phase == .paused { session?.resume() }
    }
    if packet.kind == "insight", packet.snapshot?.id == sessionID, let expiry = packet.expiresAt,
      expiry > Date()
    {
      aiInsight = packet.insight
      aiExpiry = expiry
    }
  }
}
extension WorkoutRecorder: HKWorkoutSessionDelegate {
  nonisolated func workoutSession(
    _ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
    from fromState: HKWorkoutSessionState, date: Date
  ) {
    Task { @MainActor in
      if toState == .running {
        if let start = self.pauseStart {
          self.pauses.append(Pause(start: start, end: date))
          self.pauseStart = nil
        }
        self.phase = .running
      }
      if toState == .paused {
        self.pauseStart = self.pauseStart ?? date
        self.phase = .paused
        self.aiInsight = nil
      }
      if toState == .ended {
        self.ended = date
        self.location.stopUpdatingLocation()
        self.timer?.invalidate()
        self.aiInsight = nil
        if let start = self.pauseStart {
          self.pauses.append(Pause(start: start, end: date))
          self.pauseStart = nil
        }
        do {
          try await self.builder?.endCollection(at: date)
          self.collectionEnded = true
          self.phase = .review
        } catch {
          self.message = "Workout data collection could not finish."
          self.phase = .review
        }
      }
      self.updateSnapshot()
    }
  }
  nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error)
  {
    Task { @MainActor in
      self.message = "Workout recording was interrupted. Reopen Runner to recover it."
    }
  }
  nonisolated func workoutSession(
    _ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]
  ) {
    Task { @MainActor in
      for value in data {
        if let packet = try? JSONDecoder().decode(WorkoutMessage.self, from: value) {
          self.receive(packet)
        }
      }
    }
  }
  nonisolated func workoutSession(
    _ workoutSession: HKWorkoutSession, didDisconnectFromRemoteDeviceWithError error: Error?
  ) { Task { @MainActor in self.mirrorConnected = false } }
}
extension WorkoutRecorder: HKLiveWorkoutBuilderDelegate {
  nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
  nonisolated func workoutBuilder(
    _ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>
  ) {
    Task { @MainActor in
      for type in collectedTypes.compactMap({ $0 as? HKQuantityType }) {
        guard let stats = workoutBuilder.statistics(for: type) else { continue }
        switch type.identifier {
        case HKQuantityTypeIdentifier.heartRate.rawValue:
          self.heart = stats.mostRecentQuantity()?.doubleValue(
            for: HKUnit.count().unitDivided(by: .minute()))
          self.lastHeartDate = stats.mostRecentQuantityDateInterval()?.end
        case HKQuantityTypeIdentifier.distanceWalkingRunning.rawValue:
          self.distance = stats.sumQuantity()?.doubleValue(for: .meter()) ?? self.distance
        case HKQuantityTypeIdentifier.activeEnergyBurned.rawValue:
          self.energy = stats.sumQuantity()?.doubleValue(for: .kilocalorie())
        default: break
        }
      }
      self.updateSnapshot()
    }
  }
}
extension WorkoutRecorder: CLLocationManagerDelegate {
  nonisolated func locationManager(
    _ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]
  ) {
    Task { @MainActor in
      guard self.phase == .running, let routeBuilder = self.routeBuilder else { return }
      let valid = locations.filter {
        $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy <= 35 && $0.speed < 12
          && Date().timeIntervalSince($0.timestamp) < 30
      }
      guard !valid.isEmpty else { return }
      do {
        try await routeBuilder.insertRouteData(valid)
        self.routeHasPoints = true
      } catch {
        self.message = "GPS route is temporarily unavailable. Workout measurements continue."
      }
    }
  }
  nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    Task { @MainActor in self.message = "GPS is unavailable. Workout measurements continue." }
  }
}
extension WorkoutRecorder: WCSessionDelegate {
  nonisolated func session(
    _ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
    error: Error?
  ) {}
  nonisolated func session(
    _ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]
  ) {
    guard let data = applicationContext["targets"] as? Data else { return }
    Task { @MainActor in
      if let targets = try? JSONDecoder().decode(CoachingTargets.self, from: data) {
        self.receive(WorkoutMessage(kind: "targets", targets: targets))
      }
      if let units = applicationContext["units"] as? String, let value = UnitSystem(rawValue: units)
      {
        self.units = value
      }
    }
  }
}
