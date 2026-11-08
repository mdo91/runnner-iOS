import RunCore
import SwiftUI

struct HistoryScreen: View {
  @EnvironmentObject private var health: HealthKitManager
  @EnvironmentObject private var analytics: AnalyticsStore
  var rows: [RecordedRun]
  var measurements: [HealthMeasurement]
  var units: UnitSystem
  @State private var filter = HistoryFilter()
  @State private var days = 30
  @State private var dates = false
  private var selection: [RunData] {
    var effective = filter
    if effective.interval == nil, days != 100000 {
      effective.interval = DateInterval(
        start: AppRuntime.now.addingTimeInterval(-Double(days) * 86400), end: AppRuntime.now)
    }
    return effective.apply(to: analytics.snapshot.runs, metrics: analytics.snapshot.metrics)
  }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        SectionTitle(title: "Common.Copy.runJournal.text".localized, subtitle: "Common.Count.matchingRuns.text".localized(selection.count))
        Text("Common.Count.runs.text".localized(selection.count)).accessibilityIdentifier("history.count")
        Picker("Common.Copy.historyRange.text".localized, selection: $days) {
          Text("Common.Copy.month.text".localized).tag(30)
          Text("Common.Copy.year.text".localized).tag(365)
          Text("Common.Copy.all.text".localized).tag(100000)
        }.pickerStyle(.segmented).onChange(of: days) { _, _ in filter.interval = nil }
        Surface {
          VStack(alignment: .leading, spacing: 12) {
            Picker("Common.Copy.setting.text".localized, selection: $filter.setting) {
              ForEach(RunSetting.allCases, id: \.self) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented)
            Picker("Common.Copy.source.text".localized, selection: $filter.source) {
              Text("Common.Copy.allSources.text".localized).tag(String?.none)
              ForEach(Array(Set(analytics.snapshot.runs.map(\.source))).sorted(), id: \.self) {
                Text($0).tag(Optional($0))
              }
            }.accessibilityIdentifier("history.source")
            Picker("Common.Copy.sortBy.text".localized, selection: $filter.sort) {
              ForEach(RunSort.allCases, id: \.self) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented)
            HStack {
              Text("HistoryScreen.Format.minimum.text".localized(String(describing: units.distanceUnit)))
              TextField(
                "0",
                value: Binding(
                  get: { filter.minimumMeters / units.metersPerUnit },
                  set: { filter.minimumMeters = max(0, $0) * units.metersPerUnit }), format: .number
              ).keyboardType(.decimalPad).textFieldStyle(.roundedBorder).accessibilityIdentifier(
                "history.minimum")
            }
            HStack {
              Text("HistoryScreen.Format.maximum.text".localized(String(describing: units.distanceUnit)))
              TextField(
                "Common.Copy.any.text".localized,
                value: Binding(
                  get: { filter.maximumMeters.map { $0 / units.metersPerUnit } },
                  set: { filter.maximumMeters = $0.map { max(0, $0) * units.metersPerUnit } }),
                format: .number
              ).keyboardType(.decimalPad).textFieldStyle(.roundedBorder).accessibilityIdentifier(
                "history.maximum")
            }
            HStack {
              Button("Common.Copy.customDates.text".localized) { dates = true }.accessibilityIdentifier("history.customDates")
              Button("Common.Copy.resetFilters.text".localized) {
                filter = HistoryFilter()
                days = 30
              }.accessibilityIdentifier("history.reset")
            }.buttonStyle(RunnerSecondaryButtonStyle())
            if let interval = filter.interval {
              Text(
                "\(interval.start.formatted(date: .abbreviated, time: .omitted)) – \(interval.end.addingTimeInterval(-1).formatted(date: .abbreviated, time: .omitted))"
              ).font(.caption)
            }
          }
        }
        if selection.isEmpty {
          Text("HistoryScreen.Copy.noRunsMatchTheseFilters.text".localized).foregroundStyle(RunnerStyle.muted)
        }
        ForEach(selection) { run in
          if let row = rows.first(where: { $0.id == run.id }) {
            NavigationLink {
              RunDetailScreen(
                row: row, run: run, history: analytics.snapshot.runs, measurements: measurements,
                units: units)
            } label: {
              RunListRow(run: run, units: units)
            }.buttonStyle(.plain).accessibilityIdentifier("history.run.\(run.id.uuidString)")
          }
        }
        DensityMap(runs: selection)
        if health.isSyncing || analytics.loading { ProgressView("Common.Copy.importingHistory.text".localized) }
        if analytics.unreadableCount > 0 {
          Text("HistoryScreen.Format.storedRunsCouldNotBeRead.text".localized(String(describing: analytics.unreadableCount)))
        }
      }.padding(20).frame(maxWidth: 1200).frame(maxWidth: .infinity)
    }.background(RunnerStyle.background).navigationTitle("Common.Copy.history.text".localized).refreshable {
      await health.sync()
    }
    .sheet(isPresented: $dates) {
      CustomDates(
        start: filter.interval?.start ?? AppRuntime.now.addingTimeInterval(-30 * 86400),
        end: filter.interval.map { ActivityDateRange.inclusiveEnd(of: $0) } ?? AppRuntime.now
      ) { filter.interval = $0 }
    }
  }
}
