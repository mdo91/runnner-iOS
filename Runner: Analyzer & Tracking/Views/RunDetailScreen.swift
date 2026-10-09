import Charts
import RunCore
import SwiftData
import SwiftUI

struct RunDetailScreen: View {
  @Environment(\.dynamicTypeSize) private var typeSize
  @Environment(\.modelContext) private var context
  @EnvironmentObject private var health: HealthKitManager
  @EnvironmentObject private var account: AccountManager
  @EnvironmentObject private var analysis: AnalysisManager
  var row: RecordedRun
  var run: RunData
  var history: [RunData]
  var measurements: [HealthMeasurement]
  var units: UnitSystem
  var latest = false
  @Query private var allRows: [RecordedRun]
  @EnvironmentObject private var analytics: AnalyticsStore
  @State private var selection: Date?
  @State private var selectedSplit: DateInterval?
  @ScaledMetric(relativeTo: .largeTitle) private var heroSize = 52.0
  var body: some View {
    let metrics = analytics.snapshot.metrics[run.id] ?? RunCalculator.metrics(run)
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        MetricPair {
          Label(run.indoor ? "INDOOR RUN" : "OUTDOOR RUN", systemImage: "figure.run").font(
            .caption.weight(.bold)
          ).tracking(1.2).foregroundStyle(RunnerStyle.blue)
          if !typeSize.isAccessibilitySize { Spacer() }
          Text(run.start.formatted(.dateTime.month(.abbreviated).day())).font(.subheadline)
            .foregroundStyle(RunnerStyle.muted)
        }
        VStack(alignment: .leading, spacing: 8) {
          HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(units.distance(metrics.distanceMeters)).font(
              .system(size: heroSize, weight: .semibold, design: .rounded)
            ).minimumScaleFactor(0.6).monospacedDigit()
            Text(units.distanceUnit).font(.title2).foregroundStyle(RunnerStyle.muted)
          }.accessibilityElement(children: .combine).accessibilityLabel(
            "Distance \(units.distance(metrics.distanceMeters)) \(units.distanceUnit)")
          Text(run.start.formatted(.dateTime.weekday(.wide).hour().minute())).font(.subheadline)
            .foregroundStyle(RunnerStyle.muted)
        }
        Surface {
          VStack(spacing: 24) {
            MetricPair {
              Stat(
                title: "Moving time", value: UnitSystem.duration(metrics.movingSeconds),
                unit: "Elapsed \(UnitSystem.duration(metrics.elapsedSeconds))", symbol: "stopwatch")
              Stat(
                title: "Average pace", value: units.pace(metrics.averagePaceSecondsPerKm),
                unit: "min / \(units.distanceUnit)", symbol: "speedometer")
            }
            Divider()
            MetricPair {
              Stat(
                title: "Average heart rate",
                value: metrics.averageHeartRate.map { String(Int($0.rounded())) } ?? "—",
                unit: "bpm", symbol: "heart")
              Stat(
                title: "Active energy",
                value: metrics.activeEnergyKcal.map { String(Int($0.rounded())) } ?? "—",
                unit: "kcal", symbol: "flame")
            }
          }
        }
        if !run.route.isEmpty {
          RouteCard(run: run, units: units, selection: $selection, selectedInterval: selectedSplit)
        } else {
          Surface {
            Label(
              run.indoor ? "Indoor run · route not recorded" : "No GPS route available",
              systemImage: "map"
            ).font(.headline)
            Text("Your measured performance is available without a route.").font(.subheadline)
              .foregroundStyle(RunnerStyle.muted)
          }
        }
        RunCharts(run: run, units: units, selection: $selection)
        RouteComparisons(run: run, rows: allRows, measurements: measurements, units: units)
        splitSection
        assessment(metrics)
        HStack(alignment: .top, spacing: 8) {
          Image(systemName: "applewatch")
          Text("Imported from \(run.source). Missing measurements appear as —.")
        }.font(.caption).foregroundStyle(RunnerStyle.muted).padding(.bottom, 20)
        if let status = health.status { Text(status).font(.footnote).foregroundStyle(.orange) }
      }.padding(20).frame(maxWidth: 960).frame(maxWidth: .infinity)
    }.background(RunnerStyle.background).refreshable { await health.sync() }
      .onChange(of: selection) { _, date in
        if let interval = selectedSplit,
          date.map({ $0 < interval.start || $0 > interval.end }) ?? true
        {
          selectedSplit = nil
        }
      }
      .navigationTitle(latest ? "Latest Run" : "Run Details").navigationBarTitleDisplayMode(
        latest ? .large : .inline)
  }
  @ViewBuilder private var splitSection: some View {
    let splits = RunCalculator.splits(run, length: units.metersPerUnit)
    Surface {
      VStack(alignment: .leading, spacing: 16) {
        SectionTitle(title: "Splits", subtitle: units == .metric ? "Per kilometer" : "Per mile")
        if splits.isEmpty {
          Text("Distance samples aren’t available for accurate splits.").font(.subheadline)
            .foregroundStyle(RunnerStyle.muted)
        } else {
          ForEach(splits) { split in
            Button {
              guard let timeline = DistanceTimeline(run),
                let start = timeline.time(
                  at: Double(split.index - 1) * units.metersPerUnit, starting: true),
                let end = timeline.time(
                  at: min(Double(split.index) * units.metersPerUnit, run.distanceMeters ?? 0),
                  starting: false)
              else { return }
              selectedSplit = DateInterval(start: start, end: end)
              selection = start.addingTimeInterval(end.timeIntervalSince(start) / 2)
            } label: {
              HStack {
                Text("\(split.index)").frame(width: 24, alignment: .leading).foregroundStyle(
                  RunnerStyle.muted)
                Text(units.pace(split.pace)).font(.headline.monospacedDigit())
                GeometryReader { proxy in
                  RoundedRectangle(cornerRadius: 3).fill(RunnerStyle.blue.opacity(0.75)).frame(
                    width: max(
                      4,
                      proxy.size.width
                        * min(1, (splits.map(\.pace).min() ?? split.pace) / max(1, split.pace))),
                    height: 6
                  ).frame(height: proxy.size.height)
                }.frame(height: 20)
                Text(split.averageHeartRate.map { String(Int($0.rounded())) } ?? "—").font(
                  .subheadline.monospacedDigit()
                ).frame(width: 44, alignment: .trailing)
              }
            }.buttonStyle(.plain).accessibilityElement(children: .combine).accessibilityLabel(
              "Split \(split.index), \(units.pace(split.pace)) minutes per \(units.distanceUnit)"
            ).accessibilityIdentifier("run.split.\(split.index)")
          }
          if selectedSplit != nil {
            Text("Selected split highlighted on the route.").accessibilityIdentifier(
              "run.splitSelection"
            ).font(.caption)
            Button("Clear split") {
              selectedSplit = nil
              selection = nil
            }
          }
        }
      }
    }
  }
  private func assessment(_ metrics: MeasuredMetrics) -> some View {
    Surface {
      VStack(alignment: .leading, spacing: 16) {
        HStack {
          SectionTitle(title: "Performance", subtitle: "Measured first. Explained clearly.")
          Spacer()
          Image(systemName: "waveform.path.ecg").foregroundStyle(RunnerStyle.blue)
        }
        if let report = row.report {
          Text(report.explanation.summary).font(.body)
          ForEach(report.explanation.insights) { item in
            VStack(alignment: .leading, spacing: 5) {
              Text(item.title).font(.subheadline.bold())
              Text(item.detail).font(.subheadline).foregroundStyle(RunnerStyle.muted)
              Text("Based on: \(item.evidence.map(evidenceLabel).joined(separator:", "))").font(
                .caption2
              ).foregroundStyle(RunnerStyle.muted)
            }
          }
          Divider()
          Text("Next run").font(.subheadline.bold())
          Text(report.explanation.nextRun).font(.subheadline)
          Text(report.endurance.detail).font(.footnote).foregroundStyle(RunnerStyle.muted)
          ForEach(report.missingData, id: \.self) {
            Text($0).font(.caption).foregroundStyle(RunnerStyle.muted)
          }
          Text(
            "AI fitness coaching · \(report.generatedAt.formatted(date:.abbreviated,time:.shortened))"
          ).font(.caption2).foregroundStyle(RunnerStyle.muted)
        } else {
          if let cv = metrics.pacingCoefficientOfVariation {
            Text("Split pace variation: \(Int((cv*100).rounded()))%.").font(.headline)
          }
          Text(
            "AI analysis explains your pace, effort, and available endurance measurements. Enable it in Settings after signing in."
          ).font(.subheadline).foregroundStyle(RunnerStyle.muted)
        }
        if account.signedIn && account.consent {
          Button {
            Task {
              await analysis.analyze(
                row, history: history, measurements: measurements, account: account,
                context: context)
            }
          } label: {
            if analysis.working.contains(row.id) {
              ProgressView().frame(maxWidth: .infinity)
            } else {
              Text(row.report == nil ? "Analyze this run" : "Refresh analysis").frame(
                maxWidth: .infinity)
            }
          }.buttonStyle(.bordered).disabled(analysis.working.contains(row.id))
        }
        if let message = analysis.messages[row.id] {
          Text(message).font(.footnote).foregroundStyle(RunnerStyle.muted)
        }
        Text("Fitness guidance for adults. Not a medical assessment.").font(.caption2)
          .foregroundStyle(RunnerStyle.muted)
      }
    }
  }
  private func evidenceLabel(_ key: String) -> String {
    switch key {
    case "averagePaceSecondsPerKm": return "average pace"
    case "averageHeartRate": return "average heart rate"
    case "distanceMeters": return "distance"
    case "movingSeconds": return "moving time"
    case "vo2Max": return "recorded VO₂ max"
    default:
      return key.replacingOccurrences(
        of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression
      ).lowercased()
    }
  }
  private func dynamicsLabel(_ key: String) -> String {
    switch key {
    case "HKQuantityTypeIdentifierRunningPower": return "Power"
    case "HKQuantityTypeIdentifierRunningSpeed": return "Speed"
    case "HKQuantityTypeIdentifierRunningStrideLength": return "Stride length"
    case "HKQuantityTypeIdentifierRunningGroundContactTime": return "Ground contact"
    default: return "Vertical oscillation"
    }
  }
  private func dynamicsValue(_ key: String, _ value: Double) -> String {
    if key.contains("Power") { return String(format: "%.0f W", value) }
    if key.contains("Speed") { return String(format: "%.1f m/s", value) }
    if key.contains("Contact") { return String(format: "%.0f ms", value * 1000) }
    return String(format: "%.1f cm", value * 100)
  }
}
