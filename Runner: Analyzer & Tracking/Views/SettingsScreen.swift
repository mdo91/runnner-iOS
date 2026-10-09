import AuthenticationServices
import RunCore
import SwiftData
import SwiftUI

struct SettingsScreen: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var context
  @EnvironmentObject private var health: HealthKitManager
  @EnvironmentObject private var account: AccountManager
  @EnvironmentObject private var live: PhoneWorkoutManager
  @EnvironmentObject private var historySync: HistorySyncManager
  @AppStorage("units") private var units = "metric"
  @AppStorage("haptics") private var haptics = false
  @State private var lower = ""
  @State private var upper = ""
  @State private var pace = ""
  @State private var targetError: String?
  @State private var deleteAccount = false
  @State private var clearLocal = false
  @State private var clearCloud = false
  @State private var connectDashboard = false
  private let dashboardService = DashboardLinkService()
  var body: some View {
    NavigationStack {
      Form {
        Section("Apple Health") {
          Text(
            "Workouts, heart rate, GPS routes, and running measurements are stored on this device. Runner can import runs recorded by Apple Workout and other Watch apps."
          ).font(.subheadline)
          Button("Review Health access") { Task { await health.requestAccess() } }
          Text(
            "Apple does not reveal which read permissions you granted. Empty results can mean no data, disabled access, or a pending Watch sync."
          ).font(.caption).foregroundStyle(.secondary)
        }
        Section("Display") {
          Picker("Units", selection: $units) {
            Text("Kilometers").tag("metric")
            Text("Miles").tag("imperial")
          }
        }
        Section {
          TextField("Lower heart rate (bpm)", text: $lower).keyboardType(.numberPad)
          TextField("Upper heart rate (bpm)", text: $upper).keyboardType(.numberPad)
          TextField("Target pace, min:sec / km", text: $pace).keyboardType(.numbersAndPunctuation)
          Toggle("Watch haptics", isOn: $haptics)
          Button("Save targets") { saveTargets() }
          if let targetError { Text(targetError).foregroundStyle(.orange) }
        } header: {
          Text("Your live targets")
        } footer: {
          Text(
            "Targets are optional. Without your settings, Runner shows measurements without assigning heart-rate zones. Cues appear on screen; haptics are optional."
          )
        }
        Section {
          if account.signedIn {
            Label("Signed in with Apple", systemImage: "checkmark.circle.fill").foregroundStyle(
              .green)
            Button("Sign out") { account.signOut() }
          } else {
            SignInWithAppleButton(
              .signIn, onRequest: { account.prepare($0) },
              onCompletion: { result in Task { await account.finish(result) } }
            ).signInWithAppleButtonStyle(.white).frame(height: 48).disabled(
              !AccountManager.configured)
          }
          Toggle("I am 18 or older", isOn: $account.adultConfirmed).onChange(
            of: account.adultConfirmed
          ) { _, value in
            UserDefaults.standard.set(value, forKey: "adultConfirmed")
            if !value { account.setConsent(false) }
          }
          Toggle(
            "Allow AI analysis",
            isOn: Binding(get: { account.consent }, set: { account.setConsent($0) })
          ).disabled(!account.signedIn || !account.adultConfirmed)
          Text(
            "With your permission, Runner sends numerical run summaries, splits, data-quality flags, and a compact historical baseline to Runner’s backend and Google Gemini to provide fitness coaching. Precise GPS routes, names, email addresses, and raw HealthKit samples are excluded."
          ).font(.footnote)
          Text(
            "The latest run is analyzed automatically, then new runs as they arrive. Older runs are analyzed only when requested. Cloud reports expire after 24 hours; reports saved on this device remain available. You can turn sharing off at any time."
          ).font(.footnote)
          Text(
            "Limits: 3 completed runs and 24 live updates per day. Live AI updates are at least five minutes apart. Measured stats and local Watch coaching work without AI."
          ).font(.caption).foregroundStyle(.secondary)
          if let message = account.message { Text(message).font(.footnote) }
        } header: {
          Text("Private by choice")
        } footer: {
          Text(
            "AI feedback is adult fitness coaching, not medical diagnosis. Consent version: October 3, 2026."
          )
        }
        Section {
          Toggle("Sync running history",isOn:Binding(get:{ historySync.enabled },set:{ value in
            Task { await historySync.configure(enabled:value,gps:value && historySync.gpsEnabled) }
          })).disabled(!account.signedIn || historySync.changingConsent)
          Text("With your consent, Runner stores your running history, measured stats, splits, chart summaries, dated VO₂ max and recovery measurements, and saved AI reports in your private backend account. Synced history stays until you delete it; it does not expire after 24 hours.").font(.footnote)
          Toggle("Also sync precise GPS routes",isOn:Binding(get:{ historySync.gpsEnabled },set:{ value in
            Task { await historySync.configure(enabled:historySync.enabled,gps:value) }
          })).disabled(!account.signedIn || !historySync.enabled || historySync.changingConsent)
          Text("GPS sharing is a separate choice. Routes reveal where you run. They are stored in your account for dashboard maps and are never sent to Gemini. Turning this off deletes uploaded coordinates across your account. If offline, removal finishes when this phone reconnects.").font(.footnote)
          if historySync.isSyncing || historySync.changingConsent { ProgressView() }
          if let message = historySync.message { Text(message).font(.caption).foregroundStyle(.secondary) }
          Button("Sync now") { Task { await historySync.sync(context:context,account:account) } }
            .disabled(!account.signedIn || !historySync.enabled || health.isSyncing || historySync.isSyncing || historySync.changingConsent)
          Button("Connect dashboard") { connectDashboard = true }.disabled(!account.signedIn)
          if let url = dashboardService.dashboardURL { Link("Open dashboard",destination:url) }
        } header: { Text("Cloud history") } footer: {
          Text("Only runs available through Apple Health on this phone can be uploaded. Sign in with the same Runner Apple account on each phone. Consent version: October 3, 2026.")
        }
        Section("Your data") {
          Button("Clear data from this device", role: .destructive) { clearLocal = true }.disabled(health.isSyncing || historySync.isSyncing)
          if account.signedIn {
            Button("Delete uploaded history",role:.destructive) { clearCloud = true }.disabled(historySync.changingConsent)
            Button("Delete cloud account", role: .destructive) { deleteAccount = true }
          }
        }
        Section {
          Text("Runner 1.0 · Built for the long run").font(.caption).foregroundStyle(.secondary)
        }
      }.navigationTitle("Settings").toolbar {
        ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
      }
    }
    .onAppear {
      lower = string(live.targets.lowerHeartRate)
      upper = string(live.targets.upperHeartRate)
      if let target = live.targets.targetPaceSecondsPerKm { pace = UnitSystem.metric.pace(target) }
    }
    .onDisappear { live.sendTargets() }
    .confirmationDialog(
      "Clear local workouts and reports?", isPresented: $clearLocal, titleVisibility: .visible
    ) {
      Button("Clear local data", role: .destructive) {
        do {
          account.setConsent(false)
          historySync.pauseOnDevice()
          try context.delete(model: RecordedRun.self)
          try context.delete(model: HealthMeasurement.self)
          try context.delete(model: HealthCheckpoint.self)
          try context.delete(model: CloudSyncCheckpoint.self)
          try context.delete(model: DeletedHealthRecord.self)
          try context.save()
          health.didRequestAccess = false
          UserDefaults.standard.set(false, forKey: "healthRequested")
        } catch { targetError = "Local data could not be cleared." }
      }
    } message: {
      Text(
        "This does not delete workouts from Apple Health. You can reconnect Health to import them again."
      )
    }
    .sheet(isPresented:$connectDashboard) { DashboardConnectScreen(service: dashboardService) }
    .confirmationDialog("Delete uploaded history and routes?",isPresented:$clearCloud,titleVisibility:.visible) {
      Button("Delete uploaded history",role:.destructive) { Task { await historySync.clear(context:context) } }
    } message: {
      Text("This removes dashboard history and routes from the database and disables history sync. Local workouts and Apple Health records remain. AI analysis cache and account access are removed separately by deleting your cloud account.")
    }
    .sheet(isPresented: $deleteAccount) {
      VStack(spacing: 24) {
        Text("Delete your cloud account").font(.title2.bold())
        Text(
          "Your synced history, GPS routes, cloud analyses, dashboard sessions, and account access will be removed. Your local workouts and Apple Health records stay on your device. Confirm with Apple to continue."
        ).multilineTextAlignment(.center)
        SignInWithAppleButton(
          .continue, onRequest: { account.prepare($0, deleting: true) },
          onCompletion: { result in
            Task {
              await account.finish(result)
              if !account.signedIn { deleteAccount = false }
            }
          }
        ).signInWithAppleButtonStyle(.white).frame(height: 50)
        if let message = account.message { Text(message).font(.footnote) }
        Button("Cancel") { deleteAccount = false }
      }.padding(28).presentationDetents([.medium])
    }
  }
  private func string(_ value: Double?) -> String { value.map { String(Int($0)) } ?? "" }
  private func saveTargets() {
    let low = Double(lower)
    let high = Double(upper)
    guard lower.isEmpty || low.map { (30...240).contains($0) } == true,
      upper.isEmpty || high.map { (30...240).contains($0) } == true,
      low == nil || high == nil || low! < high!
    else {
      targetError =
        "Enter heart-rate targets between 30 and 240, with the upper value above the lower value."
      return
    }
    let parts = pace.split(separator: ":")
    let minutes = parts.first.flatMap { Double($0) }
    let seconds = parts.count == 2 ? Double(parts[1]) : nil
    let target: Double? =
      pace.isEmpty
      ? nil
      : minutes.flatMap { m in
        seconds.flatMap { s in m >= 2 && m <= 30 && s >= 0 && s < 60 ? m * 60 + s : nil }
      }
    guard pace.isEmpty || target != nil else {
      targetError = "Use a pace such as 5:30, in minutes per kilometer."
      return
    }
    UserDefaults.standard.set(low, forKey: "lowerHR")
    UserDefaults.standard.set(high, forKey: "upperHR")
    UserDefaults.standard.set(target, forKey: "paceTarget")
    live.sendTargets()
    targetError = "Targets saved to sync with your Watch."
  }
}
