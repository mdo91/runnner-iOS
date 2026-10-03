import RunCore
import SwiftUI

struct HistoryScreen: View {
  @EnvironmentObject private var health: HealthKitManager
  var rows: [RecordedRun]
  var measurements: [HealthMeasurement]
  var units: UnitSystem
  @State private var days = 30
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        DensityMap(runs: rows.compactMap(\.run))
        SectionTitle(
          title: "Run journal", subtitle: "\(rows.count) runs imported from Apple Health")
        Picker("History range", selection: $days) {
          Text("Month").tag(30)
          Text("Year").tag(365)
          Text("All").tag(100000)
        }.pickerStyle(.segmented)
        if rows.isEmpty {
          EmptyState(
            symbol: "clock", title: "A story in every run",
            detail: "Your completed Apple Watch runs will appear here after syncing with Health.")
        }
        ForEach(rows.filter { $0.start > Date().addingTimeInterval(-Double(days) * 86400) }) {
          row in
          if let run = row.run {
            NavigationLink {
              RunDetailScreen(
                row: row, run: run, history: rows.compactMap(\.run), measurements: measurements,
                units: units)
            } label: {
              RunListRow(run: run, units: units)
            }.buttonStyle(.plain)
            Divider()
          }
        }
        if health.isSyncing { ProgressView("Importing history…").frame(maxWidth: .infinity) }
      }.padding(20)
    }.background(RunnerStyle.background).navigationTitle("History").refreshable {
      await health.sync()
    }
  }
}
