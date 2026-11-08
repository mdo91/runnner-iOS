import RunCore
import SwiftData
import SwiftUI
import UIKit

struct ContentView: View {
  @Environment(\.modelContext) private var context
  @Environment(\.scenePhase) private var scenePhase
  @EnvironmentObject private var health: HealthKitManager
  @EnvironmentObject private var account: AccountManager
  @EnvironmentObject private var analysis: AnalysisManager
  @EnvironmentObject private var historySync: HistorySyncManager
  @Query private var deletions: [DeletedHealthRecord]
  @Query(sort: \RecordedRun.start, order: .reverse) private var rows: [RecordedRun]
  @Query private var measurements: [HealthMeasurement]
  @AppStorage("units") private var unitRaw = "metric"
  @StateObject private var analytics = AnalyticsStore()
  @State private var settings = false
  @State private var selectedTab = 0
  private var units: UnitSystem { UnitSystem(rawValue: unitRaw) ?? .metric }
  var body: some View {
    TabView(selection: $selectedTab) {
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
                    ? "ContentView.Copy.findingYourLatestRun.text".localized : "ContentView.Copy.yourNextChapterStartsHere.text".localized,
                  detail: health.didRequestAccess
                    ? "ContentView.Copy.noRunningWorkoutsAreAvailableRecordARunOn.text".localized
                    : "ContentView.Copy.connectAppleHealthToSeeYourLatestRunExplore.text".localized
                )
                Button("Common.Copy.connectAppleHealth.text".localized) { Task { await health.requestAccess() } }
                  .buttonStyle(RunnerPrimaryButtonStyle()).controlSize(.large)
                if health.isSyncing { ProgressView() }
              }
            }.refreshable { await health.sync() }
          }
        }.modifier(RunnerTabBarStyle()).navigationTitle("Common.Copy.latestRun.text".localized).toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            Button {
              settings = true
            } label: {
              Image(systemName: "slider.horizontal.3")
            }.accessibilityLabel("Common.Copy.settings.text".localized).accessibilityIdentifier("navigation.settings")
              .accessibilityValue(
                AppRuntime.isFixture ? (analytics.loading ? "Loading fixtures" : "Fixtures ready") : "")
          }
        }
      }.tabItem { tabLabel("Common.Copy.latest.text", symbol: "figure.run", index: 0) }.tag(0)
      NavigationStack {
        HistoryScreen(rows: rows, measurements: measurements, units: units)
          .modifier(RunnerTabBarStyle())
      }
        .tabItem { tabLabel("Common.Copy.history.text", symbol: "clock", index: 1) }.tag(1)
      NavigationStack {
        ActivityScreen(rows: rows, measurements: measurements, units: units)
          .modifier(RunnerTabBarStyle())
      }
        .tabItem { tabLabel("Common.Copy.activity.text", symbol: "chart.bar.xaxis", index: 2) }.tag(2)
      NavigationStack {
        TrendsScreen(rows: rows, measurements: measurements, units: units)
          .modifier(RunnerTabBarStyle())
      }.tabItem
      { tabLabel("Common.Copy.trends.text", symbol: "chart.xyaxis.line", index: 3) }.tag(3)

    }.tint(RunnerStyle.accent).background(RunnerStyle.background).scrollEdgeEffectStyle(
      .hard, for: .bottom
    )
    .environmentObject(analytics)
    .task(id: rows.map(\.payload)) { await analytics.refresh(payloads: rows.map(\.payload)) }
    .sheet(isPresented: $settings) { SettingsScreen().presentationDragIndicator(.visible) }
    .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await health.sync() } } }
    .onChange(of: automaticKey, initial: true) { _, _ in
      Task {
        if !health.isSyncing, analytics.isCurrent(payloads: rows.map(\.payload)),
          let row = rows.first
        {
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

  }
  private func tabLabel(_ key: String, symbol: String, index: Int) -> some View {
    Label {
      Text(key.localized)
    } icon: {
      // SwiftUI can recreate tab images while scrolling; keep their contrast at the source.
      Image(uiImage: (UIImage(systemName: symbol) ?? UIImage()).withTintColor(
        UIColor(selectedTab == index ? RunnerStyle.accent : RunnerStyle.muted),
        renderingMode: .alwaysOriginal))
    }
  }
  private var historyKey: String {
    "\(account.userID ?? "")-\(health.isSyncing)-\(historySync.changeCounter)-\(historySync.changingConsent)-\(rows.map { "\($0.id)-\($0.importedAt.timeIntervalSince1970)-\($0.reportData?.hashValue ?? 0)-\($0.routeDeleted)" }.joined())-\(measurements.count)-\(deletions.count)"
  }
  private var automaticKey: String {
    "\(rows.first?.id.uuidString ?? "")-\(rows.first?.importedAt.timeIntervalSince1970 ?? 0)-\(account.signedIn)-\(account.consent)-\(health.isSyncing)-\(analytics.loading)-\(analytics.revision)"
  }
}
