import Charts
import RunCore
import SwiftUI

struct RouteComparisons: View {
  var run: RunData
  var rows: [RecordedRun]
  var measurements: [HealthMeasurement]
  var units: UnitSystem
  @EnvironmentObject private var analytics: AnalyticsStore
  @State private var drilldown: RunDrilldown?
  var body: some View {
    let related = analytics.snapshot.routeMatches.first { $0.runID == run.id }?.relatedRunIDs ?? []
    let matching = analytics.snapshot.runs.filter { related.contains($0.id) || $0.id == run.id }
      .sorted { $0.start < $1.start }
    Surface {
      VStack(alignment: .leading, spacing: 14) {
        SectionTitle(
          title: "Repeated route",
          subtitle: "Reliable outdoor routes, matched in the same direction")
        if related.isEmpty {
          Text("No reliable matching route yet.").foregroundStyle(RunnerStyle.muted)
        } else {
          Text("\(related.count + 1) completions").font(.headline).accessibilityIdentifier(
            "route.completions")
          Chart(matching) { workout in
            if let pace = analytics.snapshot.metrics[workout.id]?.averagePaceSecondsPerKm {
              LineMark(
                x: .value("Date", workout.start),
                y: .value("Pace", pace * units.metersPerUnit / 1000 / 60)
              ).foregroundStyle(RunnerStyle.blue)
              PointMark(
                x: .value("Date", workout.start),
                y: .value("Pace", pace * units.metersPerUnit / 1000 / 60)
              ).foregroundStyle(RunnerStyle.blue)
            }
          }.chartYAxisLabel("min/\(units.distanceUnit)").frame(height: 150)
          Button("Compare route runs") {
            drilldown = RunDrilldown(title: "Repeated route", runIDs: matching.map(\.id))
          }.accessibilityIdentifier("route.runs")
          Text(
            "Endpoints within 100 m, distances within 10%, and at least 90% of corresponding route points within 60 m. Weather, stops, and effort affect pace."
          ).font(.caption).foregroundStyle(RunnerStyle.muted)
        }
      }
    }.sheet(item: $drilldown) {
      RunExplorer(selection: $0, rows: rows, measurements: measurements, units: units)
    }
  }
}
