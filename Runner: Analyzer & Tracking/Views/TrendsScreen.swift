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
      VStack(alignment: .leading, spacing: 22) {
        SectionTitle(
          title: "Built one run at a time",
          subtitle: "Your progress, grounded in recorded measurements.")
        Surface {
          VStack(alignment: .leading, spacing: 16) {
            SectionTitle(title: "Recent distance")
            if runs.isEmpty {
              Text("Complete a run to begin your trends.").foregroundStyle(RunnerStyle.muted)
            } else {
              Chart(Array(runs.filter { $0.distanceMeters != nil }.prefix(20).reversed())) { run in
                BarMark(
                  x: .value("Date", run.start, unit: .day),
                  y: .value("Distance", (run.distanceMeters ?? 0) / units.metersPerUnit)
                ).foregroundStyle(RunnerStyle.blue.gradient)
              }.chartYAxisLabel(units.distanceUnit).frame(height: 190)
            }
          }
        }
        Surface {
          VStack(alignment: .leading, spacing: 14) {
            SectionTitle(
              title: "Cardiovascular endurance",
              subtitle: "Comparable runs, recorded VO₂ max, and recovery")
            if let baseline = analytics.snapshot.baseline {
              if let change = baseline.paceChangePercent {
                Text(
                  "\(abs(change).formatted(.number.precision(.fractionLength(1))))% \(change<0 ? "faster":"slower") pace"
                ).font(.title2.bold())
                Text(
                  "Compared with \(baseline.comparableRunCount) prior runs of similar distance, setting, and heart rate. Weather, terrain, and effort still influence this comparison."
                ).font(.subheadline).foregroundStyle(RunnerStyle.muted)
              } else {
                Text("Building your baseline").font(.headline)
                Text(
                  "At least five comparable runs with sufficient heart-rate coverage are needed before showing a pace trend. You have \(baseline.comparableRunCount)."
                ).font(.subheadline).foregroundStyle(RunnerStyle.muted)
              }
            } else {
              Text("Import your runs to build an endurance baseline.").foregroundStyle(
                RunnerStyle.muted)
            }
          }
        }
        Picker("Measurement trend", selection: $kind) {
          Text("VO₂ max").tag("HKQuantityTypeIdentifierVO2Max")
          Text("Recovery").tag("HKQuantityTypeIdentifierHeartRateRecoveryOneMinute")
        }.pickerStyle(.segmented).onChange(of: kind) { _, _ in selectedDate = nil }
        measurementCard(
          kind: kind, title: kind.contains("VO2") ? "Recorded VO₂ max" : "Heart-rate recovery",
          unit: kind.contains("VO2") ? "mL/kg/min" : "bpm after one minute",
          symbol: kind.contains("VO2") ? "lungs" : "heart")
        Button("Runs in distance trend") {
          drilldown = RunDrilldown(
            title: "Recent runs",
            runIDs: Array(runs.filter { $0.distanceMeters != nil }.prefix(20).map(\.id)))
        }.accessibilityIdentifier("trends.runs")
        if !analytics.snapshot.baselineRunIDs.isEmpty {
          Button("Runs in endurance baseline") {
            drilldown = RunDrilldown(
              title: "Comparable runs", runIDs: analytics.snapshot.baselineRunIDs)
          }.accessibilityIdentifier("trends.baselineRuns")
        }
        Text(
          "These are fitness trends, not a medical assessment. Runner does not estimate missing VO₂ max or recovery values."
        ).font(.footnote).foregroundStyle(RunnerStyle.muted)
      }.padding(20).frame(maxWidth: 960).frame(maxWidth: .infinity)
    }.background(RunnerStyle.background).navigationTitle("Trends")
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
            .system(.largeTitle, design: .rounded, weight: .semibold))
          Text("\(unit) · \(latest.date.formatted(date:.abbreviated,time:.omitted))").font(
            .subheadline
          ).foregroundStyle(RunnerStyle.muted)
          if values.count > 1 {
            Chart(values) { value in
              LineMark(x: .value("Date", value.date), y: .value(title, value.value))
                .foregroundStyle(RunnerStyle.blue)
              PointMark(x: .value("Date", value.date), y: .value(title, value.value))
                .foregroundStyle(RunnerStyle.blue)
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
          DisclosureGroup("Recorded measurements") {
            ForEach(values) { value in
              Button(
                "\(value.date.formatted(date: .abbreviated, time: .omitted)) · \(value.value.formatted(.number.precision(.fractionLength(1))))"
              ) { selectedDate = value.date }.accessibilityIdentifier(
                "trends.measurement.\(value.id.uuidString)")
            }
          }
        } else {
          Text("No recorded measurement available.").font(.subheadline).foregroundStyle(
            RunnerStyle.muted)
        }
      }
    }
  }
}
