import Charts
import RunCore
import SwiftUI

struct TrendsScreen: View {
  var rows: [RecordedRun]
  var measurements: [HealthMeasurement]
  var units: UnitSystem
  private var runs: [RunData] { rows.compactMap(\.run) }
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
              Chart(Array(runs.prefix(20).reversed())) { run in
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
            if let latest = runs.first {
              let baseline = HistoricalBaseline.make(
                for: latest, history: runs, vo2: [], recovery: [])
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
        measurementCard(
          kind: "HKQuantityTypeIdentifierVO2Max", title: "Recorded VO₂ max", unit: "mL/kg/min",
          symbol: "lungs")
        measurementCard(
          kind: "HKQuantityTypeIdentifierHeartRateRecoveryOneMinute", title: "Heart-rate recovery",
          unit: "bpm after one minute", symbol: "heart")
        Text(
          "These are fitness trends, not a medical assessment. Runner does not estimate missing VO₂ max or recovery values."
        ).font(.footnote).foregroundStyle(RunnerStyle.muted)
      }.padding(20)
    }.background(RunnerStyle.background).navigationTitle("Trends")
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
            }.frame(height: 140)
          }
        } else {
          Text("No recorded measurement available.").font(.subheadline).foregroundStyle(
            RunnerStyle.muted)
        }
      }
    }
  }
}
