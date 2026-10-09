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
      VStack(alignment: .leading, spacing: 22) {
        DensityMap(runs: selection)
        SectionTitle(title: "Run journal", subtitle: "\(selection.count) matching runs")
        Text("\(selection.count) runs").accessibilityIdentifier("history.count")
        Picker("History range", selection: $days) {
          Text("Month").tag(30)
          Text("Year").tag(365)
          Text("All").tag(100000)
        }.pickerStyle(.segmented).onChange(of: days) { _, _ in filter.interval = nil }
        Surface {
          VStack(alignment: .leading, spacing: 12) {
            Picker("Setting", selection: $filter.setting) {
              ForEach(RunSetting.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            Picker("Source", selection: $filter.source) {
              Text("All sources").tag(String?.none)
              ForEach(Array(Set(analytics.snapshot.runs.map(\.source))).sorted(), id: \.self) {
                Text($0).tag(Optional($0))
              }
            }.accessibilityIdentifier("history.source")
            Picker("Sort by", selection: $filter.sort) {
              ForEach(RunSort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            HStack {
              Text("Minimum \(units.distanceUnit)")
              TextField(
                "0",
                value: Binding(
                  get: { filter.minimumMeters / units.metersPerUnit },
                  set: { filter.minimumMeters = max(0, $0) * units.metersPerUnit }), format: .number
              ).keyboardType(.decimalPad).textFieldStyle(.roundedBorder).accessibilityIdentifier(
                "history.minimum")
            }
            HStack {
              Text("Maximum \(units.distanceUnit)")
              TextField(
                "Any",
                value: Binding(
                  get: { filter.maximumMeters.map { $0 / units.metersPerUnit } },
                  set: { filter.maximumMeters = $0.map { max(0, $0) * units.metersPerUnit } }),
                format: .number
              ).keyboardType(.decimalPad).textFieldStyle(.roundedBorder).accessibilityIdentifier(
                "history.maximum")
            }
            HStack {
              Button("Custom dates") { dates = true }.accessibilityIdentifier("history.customDates")
              Button("Reset filters") {
                filter = HistoryFilter()
                days = 30
              }.accessibilityIdentifier("history.reset")
            }.buttonStyle(.bordered)
            if let interval = filter.interval {
              Text(
                "\(interval.start.formatted(date: .abbreviated, time: .omitted)) – \(interval.end.addingTimeInterval(-1).formatted(date: .abbreviated, time: .omitted))"
              ).font(.caption)
            }
          }
        }
        if selection.isEmpty {
          Text("No runs match these filters.").foregroundStyle(RunnerStyle.muted)
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
            Divider()
          }
        }
        if health.isSyncing || analytics.loading { ProgressView("Importing history…") }
        if analytics.unreadableCount > 0 {
          Text("\(analytics.unreadableCount) stored runs could not be read.")
        }
      }.padding(20).frame(maxWidth: 960).frame(maxWidth: .infinity)
    }.background(RunnerStyle.background).navigationTitle("History").refreshable {
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
