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
    VStack(alignment: .leading, spacing: 12) {
      bests
      Surface {
        VStack(alignment: .leading, spacing: 14) {
          SectionTitle(
            title: "PerformanceInsights.Copy.intensityAndObservedTrainingLoad.text".localized,
            subtitle:
              "PerformanceInsights.Copy.minutesInZones15Weights15This.text".localized
          )
          if settings.preferences.zones == nil {
            Text("PerformanceInsights.Copy.configureAKnownMaximumHeartRateInSettingsTo.text".localized)
              .accessibilityIdentifier("load.configure").foregroundStyle(RunnerStyle.muted)
          } else if let load {
            distribution(load)
            Picker("Common.Copy.loadGrouping.text".localized, selection: $weekly) {
              Text("Common.Copy.daily.text".localized).tag(false)
              Text("Common.Copy.weekly.text".localized).tag(true)
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
                x: .value("Common.Copy.date.text".localized, period.interval.start),
                y: .value("Common.Copy.observedEffort.text".localized, bucket.observedEffort)
              ).foregroundStyle(bucket.incompleteCount > 0 ? .gray : RunnerStyle.accent)
            }.chartYAxisLabel("Common.Copy.observedEffort.text".localized).frame(height: 160)
            ForEach([7, 28], id: \.self) { days in
              let start = calendar.date(
                byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: AppRuntime.now))!
              let window = DateInterval(start: start, end: AppRuntime.now)
              let value = load.completeTotal(in: window, runs: completed)
              Text(
                value.map {
                  "PerformanceInsights.Format.trailingDaysEffort.text".localized(String(describing: days), String(describing: $0.formatted(.number.precision(.fractionLength(1)))))
                }
                  ?? "PerformanceInsights.Format.trailingDaysUnavailableAContributingRunHasLess.text".localized(String(describing: days))
              ).accessibilityIdentifier("load.total.\(days)")
            }
            Text(
              "PerformanceInsights.Copy.grayBarsContainIncompleteRecordingsAndShowObservedEffort.text".localized
            ).font(.caption).foregroundStyle(RunnerStyle.muted)
          } else {
            ProgressView("Common.Copy.calculatingRecordedEffort.text".localized)
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
          title: "Common.Copy.estimatedBestEfforts.text".localized,
          subtitle:
            "PerformanceInsights.Copy.fastestElapsedEffortsFromValidatedDistanceIntervalsInternalPauses.text".localized
        )
        Picker("Common.Copy.effortDistance.text".localized, selection: $distance) {
          ForEach(EffortDistance.allCases, id: \.self) { Text($0.title).tag($0) }
        }.accessibilityIdentifier("bests.distance")
        if ranked.isEmpty {
          Text("PerformanceInsights.Copy.noEligibleRecordedEffortForThisDistance.text".localized).foregroundStyle(RunnerStyle.muted)
        }
        ForEach(Array(ranked.prefix(3).enumerated()), id: \.element.id) { index, effort in
          HStack {
            Button {
              drilldown = RunDrilldown(title: "PerformanceInsights.Format.effort.text".localized(String(describing: distance.title)), runIDs: [effort.runID])
            } label: {
              VStack(alignment: .leading, spacing: 4) {
                Text("#\(index + 1) · \(UnitSystem.duration(effort.seconds))").font(.headline)
                Text(effort.start.formatted(date: .abbreviated, time: .omitted)).font(.caption)
              }
            }.buttonStyle(.plain).accessibilityIdentifier("bests.rank.\(index + 1)")
            Spacer()
            Button("Common.Copy.exclude.text".localized) { settings.exclude(effort) }.accessibilityLabel(
              "PerformanceInsights.Format.excludeInaccurateEffortFrom.text".localized(String(describing: distance.title), String(describing: effort.start.formatted(date: .abbreviated, time: .omitted)))
            ).accessibilityIdentifier("bests.exclude.\(index + 1)")
          }
        }
        Picker("Common.Copy.bestYear.text".localized, selection: $effortYear) {
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
          annual.first.map { "PerformanceInsights.Format.best.text".localized(String(describing: String(effortYear)), String(describing: UnitSystem.duration($0.seconds))) }
            ?? "PerformanceInsights.Copy.noEligibleEffortForTheSelectedYear.text".localized
        ).accessibilityIdentifier("bests.annual")
        if ranked.count > 1 {
          Chart(ranked.sorted { $0.start < $1.start }) { effort in
            LineMark(
              x: .value("Common.Copy.date.text".localized, effort.start), y: .value("Common.Copy.elapsedMinutes.text".localized, effort.seconds / 60)
            ).foregroundStyle(RunnerStyle.accent)
            PointMark(
              x: .value("Common.Copy.date.text".localized, effort.start), y: .value("Common.Copy.elapsedMinutes.text".localized, effort.seconds / 60)
            ).foregroundStyle(RunnerStyle.accent)
          }.chartYAxisLabel("Common.Copy.elapsedMinutes.text".localized).frame(height: 150)
        }
        DisclosureGroup("Common.Copy.effortHistory.text".localized) {
          ForEach(ranked.sorted { $0.start > $1.start }) { effort in
            Button(
              "\(effort.start.formatted(date: .abbreviated, time: .omitted)) · \(UnitSystem.duration(effort.seconds))"
            ) { drilldown = RunDrilldown(title: "Common.Copy.estimatedEffort.text".localized, runIDs: [effort.runID]) }
          }
        }
        if !settings.preferences.excludedEfforts.isEmpty {
          Button("Common.Copy.restoreExcludedEfforts.text".localized) { settings.restoreEfforts() }.accessibilityIdentifier(
            "bests.restore")
        }
        Text(
          "PerformanceInsights.Copy.workoutDistanceAndInterpolationLimitPrecisionEstimatedEffortsAre.text".localized
        ).font(.caption).foregroundStyle(RunnerStyle.muted)
      }
    }
  }
  private func distribution(_ load: TrainingLoad) -> some View {
    let distributions = completed.compactMap { load.distributions[$0.id] }
    let totals = (0...5).map { index in distributions.reduce(0) { $0 + $1.seconds[index] } }
    return VStack(alignment: .leading, spacing: 10) {
      Text("PerformanceInsights.Copy.recordedIntensityAllImportedRuns.text".localized).font(.headline)
      if totals.reduce(0, +) > 0 {
        ForEach(0...5, id: \.self) { index in
          HStack {
            Text(index == 0 ? "Common.Copy.belowZone1.text".localized : "PerformanceInsights.Format.zone.text".localized(String(describing: index)))
            Spacer()
            Text(UnitSystem.duration(totals[index])).monospacedDigit()
          }.accessibilityIdentifier("zones.total.\(index)")
        }
        let above = distributions.reduce(0) { $0 + $1.aboveMaximumSeconds }
        if above > 0 {
          Text(
            "PerformanceInsights.Format.aboveYourConfiguredMaximumCheckSensorAccuracyAnd.text".localized(String(describing: UnitSystem.duration(above)))
          ).foregroundStyle(.orange).accessibilityIdentifier("zones.aboveMaximum")
        }
      } else {
        Text("PerformanceInsights.Copy.noRecordedHeartRateCoverage.text".localized).accessibilityIdentifier("zones.unavailable")
      }
    }
  }
}
private struct TrainingLoadRequest: Equatable {
  let runs: [RunData]
  let zones: HeartRateZones?
}
