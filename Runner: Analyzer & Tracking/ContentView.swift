import RunCore
import SwiftData
import SwiftUI

struct ContentView: View {
  @Environment(\.modelContext) private var context
  @Environment(\.scenePhase) private var scenePhase
  @EnvironmentObject private var health: HealthKitManager
  @EnvironmentObject private var account: AccountManager
  @EnvironmentObject private var analysis: AnalysisManager
  @EnvironmentObject private var live: PhoneWorkoutManager
  @EnvironmentObject private var historySync: HistorySyncManager
  @Query private var deletions: [DeletedHealthRecord]
  @Query(sort: \RecordedRun.start, order: .reverse) private var rows: [RecordedRun]
  @Query private var measurements: [HealthMeasurement]
  @AppStorage("units") private var unitRaw = "metric"
  @StateObject private var analytics = AnalyticsStore()
  @State private var settings = false
  private var units: UnitSystem { UnitSystem(rawValue: unitRaw) ?? .metric }
  var body: some View {
    TabView {
      NavigationStack {
        Group {
          if let run = analytics.snapshot.runs.first,
            let row = rows.first(where: { $0.id == run.id })
          {
            RunDetailScreen(
              row: row, run: run, history: analytics.snapshot.runs, measurements: measurements,
              units: units, latest: true)
          } else {
            ScrollView {
              VStack {
                EmptyState(
                  symbol: "figure.run",
                  title: health.isSyncing
                    ? "Finding your latest run" : "Your next chapter starts here",
                  detail: health.didRequestAccess
                    ? "No running workouts are available. Record a run on Apple Watch, or check Runner’s read access in Health. Health may need time to sync."
                    : "Connect Apple Health to see your latest run, explore your routes, and follow your progress."
                )
                Button("Connect Apple Health") { Task { await health.requestAccess() } }
                  .buttonStyle(.borderedProminent).controlSize(.large)
                if health.isSyncing { ProgressView() }
              }
            }.refreshable { await health.sync() }
          }
        }.navigationTitle("Latest Run").toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            Button {
              settings = true
            } label: {
              Image(systemName: "slider.horizontal.3")
            }.accessibilityLabel("Settings").accessibilityIdentifier("navigation.settings")
          }
        }
      }.tabItem { Label("Latest", systemImage: "figure.run") }
      NavigationStack { HistoryScreen(rows: rows, measurements: measurements, units: units) }
        .tabItem { Label("History", systemImage: "clock") }
      NavigationStack { ActivityScreen(rows: rows, measurements: measurements, units: units) }
        .tabItem { Label("Activity", systemImage: "chart.bar.xaxis") }
      NavigationStack { TrendsScreen(rows: rows, measurements: measurements, units: units) }.tabItem
      { Label("Trends", systemImage: "chart.xyaxis.line") }
      NavigationStack { LiveScreen(history: analytics.snapshot.runs, units: units) }.tabItem {
        Label("Live", systemImage: "waveform.path.ecg")
      }
    }.tint(RunnerStyle.blue).background(RunnerStyle.background).scrollEdgeEffectStyle(
      .hard, for: .bottom
    )
    .environmentObject(analytics)
    .task(id: rows.map(\.payload)) { await analytics.refresh(payloads: rows.map(\.payload)) }
    .sheet(isPresented: $settings) { SettingsScreen().presentationDragIndicator(.visible) }
    .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await health.sync() } } }
    .task { live.onWorkoutSaved = { Task { await health.sync() } } }
    .onChange(of: automaticKey, initial: true) { _, _ in
      Task {
        if !health.isSyncing, !analytics.loading, let row = rows.first {
          await analysis.analyze(
            row, history: analytics.snapshot.runs, measurements: measurements, account: account,
            context: context, automatic: true)
        }
      }
    }
    .onChange(of: historyKey, initial: true) { _, _ in
      historySync.selectAccount(account.userID)
      if !health.isSyncing { Task { await historySync.sync(context: context, account: account) } }
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { Task { await historySync.sync(context: context, account: account) } }
    }
    .onChange(of: live.snapshot?.timestamp) { _, _ in
      Task { await live.analyzeIfDue(account: account, history: analytics.snapshot.runs) }
    }
  }
  private var historyKey: String {
    "\(account.userID ?? "")-\(health.isSyncing)-\(historySync.changeCounter)-\(historySync.changingConsent)-\(rows.map { "\($0.id)-\($0.importedAt.timeIntervalSince1970)-\($0.reportData?.hashValue ?? 0)-\($0.routeDeleted)" }.joined())-\(measurements.count)-\(deletions.count)"
  }
  private var automaticKey: String {
    "\(rows.first?.id.uuidString ?? "")-\(rows.first?.importedAt.timeIntervalSince1970 ?? 0)-\(account.signedIn)-\(account.consent)-\(health.isSyncing)-\(analytics.loading)"
  }
}
