import Charts
import RunCore
import SwiftUI

struct TrendsScreen: View {
  var rows: [RecordedRun]
  var measurements: [HealthMeasurement]
  var units: UnitSystem
  @EnvironmentObject private var analytics: AnalyticsStore
  @State private var kind = "HKQuantityTypeIdentifierVO2Max"
  @State private var selectedDate: Date?
  @State private var drilldown: RunDrilldown?
  private var runs: [RunData] { analytics.snapshot.runs }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        SectionTitle(
          title: "TrendsScreen.Copy.builtOneRunAtATime.text".localized,
          subtitle: "TrendsScreen.Copy.yourProgressGroundedInRecordedMeasurements.text".localized)
        DashboardGrid {
          Surface {
            VStack(alignment: .leading, spacing: 16) {
              SectionTitle(title: "Common.Copy.recentDistance.text".localized)
              if runs.isEmpty {
                Text("TrendsScreen.Copy.completeARunToBeginYourTrends.text".localized).foregroundStyle(RunnerStyle.muted)
              } else {
                Chart(Array(runs.filter { $0.distanceMeters != nil }.prefix(20).reversed())) {
                  run in
                  BarMark(
                    x: .value("Common.Copy.date.text".localized, run.start, unit: .day),
                    y: .value("Common.Copy.distance.text".localized, (run.distanceMeters ?? 0) / units.metersPerUnit)
                  ).foregroundStyle(RunnerStyle.accent)
                }.chartYAxisLabel(units.distanceUnit).frame(height: 190)
              }
            }
          }
          Surface {
            VStack(alignment: .leading, spacing: 14) {
              SectionTitle(
                title: "Common.Copy.cardiovascularEndurance.text".localized,
                subtitle: "TrendsScreen.Copy.comparableRunsRecordedVOMaxAndRecovery.text".localized)
              if let baseline = analytics.snapshot.baseline {
                if let change = baseline.paceChangePercent {
                  Text(
                    "TrendsScreen.Format.pace.text".localized(String(describing: abs(change).formatted(.number.precision(.fractionLength(1)))), String(describing: change<0 ? "Common.Copy.faster.text".localized:"Common.Copy.slower.text".localized))
                  ).font(.title2.bold())
                  Text(
                    "TrendsScreen.Format.comparedWithPriorRunsOfSimilarDistanceSetting.text".localized(String(describing: baseline.comparableRunCount))
                  ).font(.subheadline).foregroundStyle(RunnerStyle.muted)
                } else {
                  Text("Common.Copy.buildingYourBaseline.text".localized).font(.headline)
                  Text(
                    "TrendsScreen.Format.atLeastFiveComparableRunsWithSufficientHeart.text".localized(String(describing: baseline.comparableRunCount))
                  ).font(.subheadline).foregroundStyle(RunnerStyle.muted)
                }
              } else {
                Text("TrendsScreen.Copy.importYourRunsToBuildAnEnduranceBaseline.text".localized).foregroundStyle(
                  RunnerStyle.muted)
              }
            }
          }
        }
        DashboardGrid {
          VStack(alignment: .leading, spacing: 12) {
            Picker("Common.Copy.measurementTrend.text".localized, selection: $kind) {
              Text("Common.Copy.vOMax.text".localized).tag("HKQuantityTypeIdentifierVO2Max")
              Text("Common.Copy.recovery.text".localized).tag("HKQuantityTypeIdentifierHeartRateRecoveryOneMinute")
            }.pickerStyle(.segmented).onChange(of: kind) { _, _ in selectedDate = nil }
            measurementCard(
              kind: kind, title: kind.contains("VO2") ? "Common.Copy.recordedVOMax.text".localized : "Common.Copy.heartRateRecovery.text".localized,
              unit: kind.contains("VO2") ? "mL/kg/min" : "TrendsScreen.Copy.bpmAfterOneMinute.text".localized,
              symbol: kind.contains("VO2") ? "lungs" : "heart")
            Button("TrendsScreen.Copy.runsInDistanceTrend.text".localized) {
              drilldown = RunDrilldown(
                title: "Common.Copy.recentRuns.text".localized,
                runIDs: Array(runs.filter { $0.distanceMeters != nil }.prefix(20).map(\.id)))
            }.buttonStyle(RunnerSecondaryButtonStyle()).accessibilityIdentifier("trends.runs")
            if !analytics.snapshot.baselineRunIDs.isEmpty {
              Button("TrendsScreen.Copy.runsInEnduranceBaseline.text".localized) {
                drilldown = RunDrilldown(
                  title: "Common.Copy.comparableRuns.text".localized, runIDs: analytics.snapshot.baselineRunIDs)
              }.buttonStyle(RunnerSecondaryButtonStyle()).accessibilityIdentifier("trends.baselineRuns")
            }
          }
          PerformanceInsights(
            snapshot: analytics.snapshot, rows: rows, measurements: measurements, units: units)
        }
        Text(
          "TrendsScreen.Copy.theseAreFitnessTrendsNotAMedicalAssessmentRunner.text".localized
        ).font(.footnote).foregroundStyle(RunnerStyle.muted)
      }.padding(20).frame(maxWidth: 1200).frame(maxWidth: .infinity)
    }.background(RunnerStyle.background).navigationTitle("Common.Copy.trends.text".localized)
      .sheet(item: $drilldown) {
        RunExplorer(selection: $0, rows: rows, measurements: measurements, units: units)
      }
  }
  private func measurementCard(kind: String, title: String, unit: String, symbol: String)
    -> some View
  {
    let values = measurements.filter { $0.kind == kind }.sorted { $0.date < $1.date }
    return Surface {
      VStack(alignment: .leading, spacing: 14) {
        Label(title, systemImage: symbol).font(.headline)
        if let latest = values.last {
          Text(latest.value.formatted(.number.precision(.fractionLength(1)))).font(
            RunnerStyle.metricFont(.largeTitle))
          Text("\(unit) · \(latest.date.formatted(date:.abbreviated,time:.omitted))").font(
            .subheadline
          ).foregroundStyle(RunnerStyle.muted)
          if values.count > 1 {
            Chart(values) { value in
              LineMark(x: .value("Common.Copy.date.text".localized, value.date), y: .value(title, value.value))
                .foregroundStyle(RunnerStyle.accent)
              PointMark(x: .value("Common.Copy.date.text".localized, value.date), y: .value(title, value.value))
                .foregroundStyle(RunnerStyle.accent)
            }.chartXSelection(value: $selectedDate).frame(height: 140)
          }
          if let selectedDate,
            let measurement = values.min(by: {
              abs($0.date.timeIntervalSince(selectedDate))
                < abs($1.date.timeIntervalSince(selectedDate))
            })
          {
            Text(
              "\(measurement.date.formatted(date: .abbreviated, time: .omitted)): \(measurement.value.formatted(.number.precision(.fractionLength(1)))) \(unit)"
            ).accessibilityIdentifier("trends.selection")
          }
          DisclosureGroup("Common.Copy.recordedMeasurements.text".localized) {
            ForEach(values) { value in
              Button(
                "\(value.date.formatted(date: .abbreviated, time: .omitted)) · \(value.value.formatted(.number.precision(.fractionLength(1))))"
              ) { selectedDate = value.date }.accessibilityIdentifier(
                "trends.measurement.\(value.id.uuidString)")
            }
          }
        } else {
          Text("TrendsScreen.Copy.noRecordedMeasurementAvailable.text".localized).font(.subheadline).foregroundStyle(
            RunnerStyle.muted)
        }
      }
    }
  }
}
