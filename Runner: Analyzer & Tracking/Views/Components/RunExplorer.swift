import RunCore
import SwiftUI

struct RunDrilldown: Identifiable {
  let id = UUID()
  let title: String
  let runIDs: [UUID]
}
struct RunExplorer: View {
  var selection: RunDrilldown
  var rows: [RecordedRun]
  var measurements: [HealthMeasurement]
  var units: UnitSystem
  @EnvironmentObject private var analytics: AnalyticsStore
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    NavigationStack {
      List {
        Text("\(selection.runIDs.count) runs").accessibilityIdentifier("explorer.count")
        ForEach(selection.runIDs, id: \.self) { id in
          if let run = analytics.snapshot.runs.first(where: { $0.id == id }),
            let row = rows.first(where: { $0.id == id })
          {
            NavigationLink {
              RunDetailScreen(
                row: row, run: run, history: analytics.snapshot.runs, measurements: measurements,
                units: units)
            } label: {
              RunListRow(run: run, units: units)
            }
            .accessibilityIdentifier("explorer.run.\(id.uuidString)")
          }
        }
        if selection.runIDs.isEmpty { Text("No completed runs in this selection.") }
      }.navigationTitle(selection.title).toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }.accessibilityIdentifier("explorer.done")
        }
      }
    }
  }
}
