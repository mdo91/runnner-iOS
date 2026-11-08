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
          title: "Common.Copy.repeatedRoute.text".localized,
          subtitle: "RouteComparisons.Copy.reliableOutdoorRoutesMatchedInTheSameDirection.text".localized)
        if related.isEmpty {
          Text("RouteComparisons.Copy.noReliableMatchingRouteYet.text".localized).foregroundStyle(RunnerStyle.muted)
        } else {
          Text("RouteComparisons.Format.completions.text".localized(String(describing: related.count + 1))).font(.headline).accessibilityIdentifier(
            "route.completions")
          Chart(matching) { workout in
            if let pace = analytics.snapshot.metrics[workout.id]?.averagePaceSecondsPerKm {
              LineMark(
                x: .value("Common.Copy.date.text".localized, workout.start),
                y: .value("Common.Copy.pace.text".localized, pace * units.metersPerUnit / 1000 / 60)
              ).foregroundStyle(RunnerStyle.accent)
              PointMark(
                x: .value("Common.Copy.date.text".localized, workout.start),
                y: .value("Common.Copy.pace.text".localized, pace * units.metersPerUnit / 1000 / 60)
              ).foregroundStyle(RunnerStyle.accent)
            }
          }.chartYAxisLabel("RouteComparisons.Format.min.text".localized(String(describing: units.distanceUnit))).frame(height: 150)
          Button("Common.Copy.compareRouteRuns.text".localized) {
            drilldown = RunDrilldown(title: "Common.Copy.repeatedRoute.text".localized, runIDs: matching.map(\.id))
          }.buttonStyle(RunnerSecondaryButtonStyle()).accessibilityIdentifier("route.runs")
          Text(
            "RouteComparisons.Copy.endpointsWithin100MDistancesWithin10AndAt.text".localized
          ).font(.caption).foregroundStyle(RunnerStyle.muted)
        }
      }
    }.sheet(item: $drilldown) {
      RunExplorer(selection: $0, rows: rows, measurements: measurements, units: units)
    }
  }
}
