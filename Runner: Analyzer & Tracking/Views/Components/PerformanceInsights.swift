import Charts
import RunCore
import SwiftUI

struct PerformanceInsights: View {
  var snapshot: RunAnalyticsSnapshot
  var rows: [RecordedRun]
  var measurements: [HealthMeasurement]
  var units: UnitSystem
  @EnvironmentObject private var settings: TrainingSettings
  @EnvironmentObject private var analytics: AnalyticsStore
  @State private var distance: EffortDistance = .km5
  @State private var effortYear = AppRuntime.calendar.component(.year, from: AppRuntime.now)
  @State private var drilldown: RunDrilldown?
  @State private var load: TrainingLoad?
  @State private var weekly = false
  private var completed: [RunData] { snapshot.runs.filter { $0.end <= AppRuntime.now } }
  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      bests
      Surface {
        VStack(alignment: .leading, spacing: 14) {
          SectionTitle(
            title: "Intensity and observed training load",
            subtitle:
              "Minutes in Zones 1–5 × weights 1–5. This is recorded effort, not a fitness or fatigue model."
          )
          if settings.preferences.zones == nil {
            Text("Configure a known maximum heart rate in Settings to see zones and training load.")
              .accessibilityIdentifier("load.configure").foregroundStyle(RunnerStyle.muted)
          } else if let load {
            distribution(load)
            Picker("Load grouping", selection: $weekly) {
              Text("Daily").tag(false)
              Text("Weekly").tag(true)
            }.pickerStyle(.segmented)
            let calendar = AppRuntime.calendar
            let interval = DateInterval(
              start: calendar.date(
                byAdding: .day, value: -27, to: calendar.startOfDay(for: AppRuntime.now))!,
              end: AppRuntime.now)
            let periods = ActivityStatistics(
              runs: completed, now: AppRuntime.now, calendar: calendar, metrics: snapshot.metrics
            ).buckets(in: interval, component: weekly ? .weekOfYear : .day)
            Chart(periods) { period in
              let bucket = load.bucket(in: period.interval, runs: completed)
              BarMark(
                x: .value("Date", period.interval.start),
                y: .value("Observed effort", bucket.observedEffort)
              ).foregroundStyle(bucket.incompleteCount > 0 ? .gray : RunnerStyle.blue)
            }.chartYAxisLabel("Observed effort").frame(height: 160)
            ForEach([7, 28], id: \.self) { days in
              let start = calendar.date(
                byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: AppRuntime.now))!
              let window = DateInterval(start: start, end: AppRuntime.now)
              let value = load.completeTotal(in: window, runs: completed)
              Text(
                value.map {
                  "Trailing \(days) days: \($0.formatted(.number.precision(.fractionLength(1)))) effort"
                }
                  ?? "Trailing \(days) days unavailable: a contributing run has less than 80% heart-rate coverage."
              ).accessibilityIdentifier("load.total.\(days)")
            }
            Text(
              "Gray bars contain incomplete recordings and show observed effort only. Below-Zone-1 time is separate and carries no load weight."
            ).font(.caption).foregroundStyle(RunnerStyle.muted)
          } else {
            ProgressView("Calculating recorded effort…")
          }
        }
      }
    }.task(id: TrainingLoadRequest(runs: completed, zones: settings.preferences.zones)) {
      load = nil
      if let zones = settings.preferences.zones {
        let result = await analytics.service.trainingLoad(runs: completed, zones: zones)
        guard !Task.isCancelled else { return }
        load = result
      }
    }
    .sheet(item: $drilldown) {
      RunExplorer(selection: $0, rows: rows, measurements: measurements, units: units)
    }
  }
  private var bests: some View {
    let ranked = BestEfforts.ranked(
      snapshot.efforts, distance: distance, excluded: settings.preferences.excludedEfforts)
    let annual = BestEfforts.ranked(
      snapshot.efforts, distance: distance, excluded: settings.preferences.excludedEfforts,
      year: effortYear,
      calendar: AppRuntime.calendar)
    return Surface {
      VStack(alignment: .leading, spacing: 14) {
        SectionTitle(
          title: "Estimated best efforts",
          subtitle:
            "Fastest elapsed efforts from validated distance intervals. Internal pauses count; long unexplained gaps are rejected."
        )
        Picker("Effort distance", selection: $distance) {
          ForEach(EffortDistance.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }.accessibilityIdentifier("bests.distance")
        if ranked.isEmpty {
          Text("No eligible recorded effort for this distance.").foregroundStyle(RunnerStyle.muted)
        }
        ForEach(Array(ranked.prefix(3).enumerated()), id: \.element.id) { index, effort in
          HStack {
            Button {
              drilldown = RunDrilldown(title: "\(distance.rawValue) effort", runIDs: [effort.runID])
            } label: {
              VStack(alignment: .leading, spacing: 4) {
                Text("#\(index + 1) · \(UnitSystem.duration(effort.seconds))").font(.headline)
                Text(effort.start.formatted(date: .abbreviated, time: .omitted)).font(.caption)
              }
            }.buttonStyle(.plain).accessibilityIdentifier("bests.rank.\(index + 1)")
            Spacer()
            Button("Exclude") { settings.exclude(effort) }.accessibilityLabel(
              "Exclude inaccurate \(distance.rawValue) effort from \(effort.start.formatted(date: .abbreviated, time: .omitted))"
            ).accessibilityIdentifier("bests.exclude.\(index + 1)")
          }
        }
        Picker("Best year", selection: $effortYear) {
          ForEach(
            Array(
              Set(snapshot.efforts.map { AppRuntime.calendar.component(.year, from: $0.start) })
                .union([AppRuntime.calendar.component(.year, from: AppRuntime.now)])
            ).sorted(by: >), id: \.self
          ) { year in
            Text(String(year)).tag(year)
          }
        }.accessibilityIdentifier("bests.year")
        Text(
          annual.first.map { "\(String(effortYear)) best: \(UnitSystem.duration($0.seconds))" }
            ?? "No eligible effort for the selected year."
        ).accessibilityIdentifier("bests.annual")
        if ranked.count > 1 {
          Chart(ranked.sorted { $0.start < $1.start }) { effort in
            LineMark(
              x: .value("Date", effort.start), y: .value("Elapsed minutes", effort.seconds / 60)
            ).foregroundStyle(RunnerStyle.blue)
            PointMark(
              x: .value("Date", effort.start), y: .value("Elapsed minutes", effort.seconds / 60)
            ).foregroundStyle(RunnerStyle.blue)
          }.chartYAxisLabel("Elapsed minutes").frame(height: 150)
        }
        DisclosureGroup("Effort history") {
          ForEach(ranked.sorted { $0.start > $1.start }) { effort in
            Button(
              "\(effort.start.formatted(date: .abbreviated, time: .omitted)) · \(UnitSystem.duration(effort.seconds))"
            ) { drilldown = RunDrilldown(title: "Estimated effort", runIDs: [effort.runID]) }
          }
        }
        if !settings.preferences.excludedEfforts.isEmpty {
          Button("Restore excluded efforts") { settings.restoreEfforts() }.accessibilityIdentifier(
            "bests.restore")
        }
        Text(
          "Workout distance and interpolation limit precision. Estimated efforts are not certified race results; excluding an effort does not delete its workout."
        ).font(.caption).foregroundStyle(RunnerStyle.muted)
      }
    }
  }
  private func distribution(_ load: TrainingLoad) -> some View {
    let distributions = completed.compactMap { load.distributions[$0.id] }
    let totals = (0...5).map { index in distributions.reduce(0) { $0 + $1.seconds[index] } }
    return VStack(alignment: .leading, spacing: 10) {
      Text("Recorded intensity · all imported runs").font(.headline)
      if totals.reduce(0, +) > 0 {
        ForEach(0...5, id: \.self) { index in
          HStack {
            Text(index == 0 ? "Below Zone 1" : "Zone \(index)")
            Spacer()
            Text(UnitSystem.duration(totals[index])).monospacedDigit()
          }.accessibilityIdentifier("zones.total.\(index)")
        }
        let above = distributions.reduce(0) { $0 + $1.aboveMaximumSeconds }
        if above > 0 {
          Text(
            "\(UnitSystem.duration(above)) above your configured maximum; check sensor accuracy and zone settings."
          ).foregroundStyle(.orange).accessibilityIdentifier("zones.aboveMaximum")
        }
      } else {
        Text("No recorded heart-rate coverage.").accessibilityIdentifier("zones.unavailable")
      }
    }
  }
}
private struct TrainingLoadRequest: Equatable {
  let runs: [RunData]
  let zones: HeartRateZones?
}
