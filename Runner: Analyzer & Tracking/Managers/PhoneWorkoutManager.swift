import Foundation
import HealthKit
import RunCore
import WatchConnectivity

@MainActor final class PhoneWorkoutManager: NSObject, ObservableObject {
  @Published var snapshot: LiveSnapshot?
  @Published var connected = false
  @Published var message: String?
  @Published var insight: AnalysisReport?
  private var session: HKWorkoutSession?
  private var health: HKHealthStore?
  private var heartSamples: [TimedValue] = []
  private var lastAIRequest = Date.distantPast
  private var requesting = false
  var onWorkoutSaved: (() -> Void)?
  override init() {
    super.init()
    if !AppRuntime.isFixture, WCSession.isSupported() {
      WCSession.default.delegate = self
      WCSession.default.activate()
    }
  }
  func configure(_ health: HKHealthStore) {
    self.health = health
    health.workoutSessionMirroringStartHandler = { [weak self] session in
      Task { @MainActor in
        self?.session = session
        session.delegate = self
        self?.connected = true
        self?.message = nil
        self?.sendTargets()
      }
    }
  }
  func startWatch() async {
    guard let health else { return }
    let config = HKWorkoutConfiguration()
    config.activityType = .running
    config.locationType = .outdoor
    do {
      try await health.startWatchApp(toHandle: config)
      message = "Open Runner on your Watch and start your run."
    } catch { message = "Open Runner on your paired Apple Watch to start a run." }
  }
  func pauseOrResume() {
    guard let snapshot else { return }
    send(WorkoutMessage(kind: "command", command: snapshot.paused ? "resume" : "pause"))
  }
  var targets: CoachingTargets {
    CoachingTargets(
      lowerHeartRate: AppRuntime.defaults.object(forKey: "lowerHR") as? Double,
      upperHeartRate: AppRuntime.defaults.object(forKey: "upperHR") as? Double,
      targetPaceSecondsPerKm: AppRuntime.defaults.object(forKey: "paceTarget") as? Double,
      haptics: AppRuntime.defaults.bool(forKey: "haptics"))
  }
  func sendTargets() {
    guard !AppRuntime.isFixture else { return }
    let value = targets
    send(WorkoutMessage(kind: "targets", targets: value))
    if WCSession.default.activationState == .activated, let data = try? JSONEncoder().encode(value)
    {
      try? WCSession.default.updateApplicationContext([
        "targets": data, "units": AppRuntime.defaults.string(forKey: "units") ?? "metric",
      ])
    }
  }
  private func send(_ packet: WorkoutMessage) {
    guard let session, let data = try? JSONEncoder().encode(packet) else { return }
    Task {
      do { try await session.sendToRemoteWorkoutSession(data: data) } catch { connected = false }
    }
  }
  func analyzeIfDue(account: AccountManager, history: [RunData]) async {
    guard let live = snapshot, connected, !live.paused,
      Date().timeIntervalSince(live.timestamp) < 20, account.signedIn, account.consent,
      account.adultConfirmed,
      Date().timeIntervalSince(lastAIRequest) >= 300, !requesting, live.elapsed >= 300
    else { return }
    lastAIRequest = Date()
    requesting = true
    defer { requesting = false }
    let run = RunData(
      id: live.id, start: live.start, end: live.timestamp, duration: live.elapsed,
      distanceMeters: live.distance, activeEnergyKcal: live.energy, source: "Runner Watch",
      heartRate: heartSamples, pauses: live.pauses)
    do {
      let report = try await APIClient.analyze(
        AnalysisRequest(run: run, history: history), live: true)
      guard snapshot?.id == live.id, connected, account.consent, let expiry = report.expiresAt,
        expiry > Date(), snapshot?.paused == false
      else { return }
      insight = report
      send(
        WorkoutMessage(
          kind: "insight", snapshot: live, insight: report.explanation.summary, expiresAt: expiry))
    } catch { message = "Live AI is unavailable. Watch measurements and local cues continue." }
  }
}
extension PhoneWorkoutManager: HKWorkoutSessionDelegate {
  nonisolated func workoutSession(
    _ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
    from fromState: HKWorkoutSessionState, date: Date
  ) {
    Task { @MainActor in
      if toState == .ended {
        self.connected = false
        self.snapshot = nil
        self.insight = nil
        self.heartSamples = []
        self.onWorkoutSaved?()
      }
      if toState == .paused { self.snapshot?.paused = true }
      if toState == .running { self.snapshot?.paused = false }
    }
  }
  nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error)
  {
    Task { @MainActor in
      self.connected = false
      self.message = "Watch disconnected. Recording continues on your Watch."
    }
  }
  nonisolated func workoutSession(
    _ workoutSession: HKWorkoutSession, didDisconnectFromRemoteDeviceWithError error: Error?
  ) {
    Task { @MainActor in
      self.connected = false
      self.message = "Watch disconnected. Recording continues on your Watch."
    }
  }
  nonisolated func workoutSession(
    _ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]
  ) {
    Task { @MainActor in
      for data in data {
        guard let packet = try? JSONDecoder().decode(WorkoutMessage.self, from: data),
          packet.kind == "snapshot", let live = packet.snapshot
        else { continue }
        if self.snapshot?.id != live.id {
          self.heartSamples = []
          self.insight = nil
          self.lastAIRequest = .distantPast
        }
        if let existing = self.snapshot, existing.id == live.id,
          live.timestamp <= existing.timestamp
        {
          continue
        }
        self.snapshot = live
        self.connected = true
        if !live.paused, let hr = live.heartRate {
          self.heartSamples.append(TimedValue(start: live.timestamp, value: hr))
        }
      }
    }
  }
}
extension PhoneWorkoutManager: WCSessionDelegate {
  nonisolated func session(
    _ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
    error: Error?
  ) { Task { @MainActor in self.sendTargets() } }
  nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
  nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
  nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
    if userInfo["workoutSaved"] as? Bool == true { Task { @MainActor in self.onWorkoutSaved?() } }
  }
}
