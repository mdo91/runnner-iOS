import Charts
import RunCore
import SwiftUI

struct ActivityScreen: View {
  var rows: [RecordedRun]
  var measurements: [HealthMeasurement]
  var units: UnitSystem
  @EnvironmentObject private var analytics: AnalyticsStore

  var body: some View {
    ActivityContent(
      snapshot: analytics.snapshot, rows: rows, measurements: measurements, units: units)
  }
}

private struct ActivityContent: View {
  var snapshot: RunAnalyticsSnapshot
  var rows: [RecordedRun]
  var measurements: [HealthMeasurement]
  var units: UnitSystem
  @Environment(\.dynamicTypeSize) private var typeSize
  @State private var range: ActivityRange = .month
  @State private var metric: ActivityMetric = .runs
  @State private var selectedDate: Date?

  @State private var customInterval: DateInterval?
  @State private var dates = false
  @State private var bucketList = false
  @State private var drilldown: RunDrilldown?

  var body: some View {
    TimelineView(.periodic(from: .now, by: 60)) { timeline in
      let statistics = ActivityStatistics(
        runs: snapshot.runs, now: AppRuntime.isFixture ? AppRuntime.now : timeline.date,
        calendar: AppRuntime.calendar, metrics: snapshot.metrics)
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          SectionTitle(
            title: "ActivityScreen.Copy.everyRunAddsUp.text".localized,
            subtitle: "ActivityScreen.Copy.yourRunningVolumeAndProgressOverTime.text".localized)
          activityChart(statistics)
          GoalsSection(statistics: statistics, units: units)
          TrainingCalendar(statistics: statistics, metric: metric, units: units) { drilldown = $0 }
          SectionTitle(
            title: "Common.Copy.performance.text".localized,
            subtitle: "ActivityScreen.Copy.currentPeriodsAreTotalsSoFarPreviousPeriodsShow.text".localized)
          DashboardGrid {
            Surface {
              VStack(alignment: .leading, spacing: 18) {
                compactPerformance(
                  "Common.Copy.currentMonth.text".localized, interval: statistics.period(.month), statistics: statistics)
                Divider()
                compactPerformance(
                  "Common.Copy.lastMonth.text".localized, interval: statistics.period(.month, previous: true),
                  statistics: statistics)
              }
            }
            Surface {
              VStack(alignment: .leading, spacing: 18) {
                compactPerformance(
                  "Common.Copy.currentWeek.text".localized, interval: statistics.period(.weekOfYear), statistics: statistics)
                Divider()
                compactPerformance(
                  "Common.Copy.lastWeek.text".localized, interval: statistics.period(.weekOfYear, previous: true),
                  statistics: statistics)
              }
            }
          }
          SectionTitle(
            title: "Common.Copy.improvements.text".localized,
            subtitle:
              "ActivityScreen.Copy.compareTheSameElapsedPortionOfEachPeriodShorter.text".localized
          )
          DashboardGrid {
            comparisonCard("Common.Copy.monthlyProgress.text".localized, comparison: statistics.comparison(.month))
            comparisonCard("Common.Copy.weeklyProgress.text".localized, comparison: statistics.comparison(.weekOfYear))
          }
          Text(
            "ActivityScreen.Copy.basedOnImportedCompletedRunsAndTheirStartDates.text".localized
          )
          .font(.footnote).foregroundStyle(RunnerStyle.muted)
        }.padding(20).frame(maxWidth: 1200).frame(maxWidth: .infinity)
      }
    }
    .background(RunnerStyle.background).navigationTitle("Common.Copy.activity.text".localized)
    .sheet(isPresented: $dates) {
      CustomDates(
        start: customInterval?.start
          ?? AppRuntime.calendar.dateInterval(of: .month, for: AppRuntime.now)!.start,
        end: customInterval.map { ActivityDateRange.inclusiveEnd(of: $0) } ?? AppRuntime.now
      ) {
        customInterval = $0
        selectedDate = nil
      }
    }
    .sheet(item: $drilldown) { selection in
      RunExplorer(selection: selection, rows: rows, measurements: measurements, units: units)
    }
    .onChange(of: range) { _, _ in
      customInterval = nil
      selectedDate = nil
    }
    .onChange(of: metric) { _, _ in selectedDate = nil }
  }

  private func activityChart(_ statistics: ActivityStatistics) -> some View {
    let interval =
      customInterval ?? range.interval(now: statistics.now, calendar: statistics.calendar)
    let component =
      customInterval == nil ? range.bucketComponent : statistics.customBucketComponent(in: interval)
    let buckets = statistics.buckets(in: interval, component: component)
    let total = statistics.summary(in: interval)
    let selected = selectedDate.flatMap { date in
      buckets.first { date >= $0.interval.start && date < $0.interval.end }
    }
    let maximum = max(1, buckets.compactMap { metric.value($0.summary, units: units) }.max() ?? 0)
    return Surface {
      VStack(alignment: .leading, spacing: 18) {
        if typeSize.isAccessibilitySize {
          Picker("Common.Copy.timePeriod.text".localized, selection: $range) {
            ForEach(ActivityRange.allCases, id: \.self) { Text($0.title).tag($0) }
          }.pickerStyle(.menu)
          Picker("Common.Copy.chartMetric.text".localized, selection: $metric) {
            ForEach(ActivityMetric.allCases, id: \.self) {
              Text($0 == .movingTime ? "Common.Copy.time.text".localized : $0 == .elevation ? "Common.Copy.elevation.text".localized : $0.title).tag(
                $0
              ).accessibilityLabel($0.title)
            }
          }.pickerStyle(.menu)
        } else {
          Picker("Common.Copy.timePeriod.text".localized, selection: $range) {
            ForEach(ActivityRange.allCases, id: \.self) { Text($0.title).tag($0) }
          }.pickerStyle(.segmented)
          Picker("Common.Copy.chartMetric.text".localized, selection: $metric) {
            ForEach(ActivityMetric.allCases, id: \.self) {
              Text($0 == .movingTime ? "Common.Copy.time.text".localized : $0 == .elevation ? "Common.Copy.elevation.text".localized : $0.title).tag(
                $0
              ).accessibilityLabel($0.title)
            }
          }.pickerStyle(.segmented)
        }
        HStack {
          Button("Common.Copy.customDates.text".localized) { dates = true }.accessibilityIdentifier("activity.customDates")
          if customInterval != nil {
            Button("Common.Copy.usePreset.text".localized) {
              customInterval = nil
              selectedDate = nil
            }
          }
        }.buttonStyle(RunnerSecondaryButtonStyle())
        VStack(alignment: .leading, spacing: 6) {
          Text(customInterval == nil ? rangeTitle : "Common.Copy.customDates.text".localized).font(.headline).foregroundStyle(
            RunnerStyle.muted)
          Text(metric.formatted(total, units: units))
            .accessibilityIdentifier("activity.total")
            .font(RunnerStyle.metricFont(.largeTitle)).monospacedDigit().foregroundStyle(
              RunnerStyle.accent)
          Text(
            dateRange(interval, throughNow: interval.end == statistics.now)
          )
          .font(.subheadline).foregroundStyle(RunnerStyle.muted)
        }
        if total.runCount > 0, metric.value(total, units: units) != nil, let first = buckets.first,
          let last = buckets.last
        {
          Chart {
            ForEach(buckets) { bucket in
              if let value = metric.value(bucket.summary, units: units) {
                BarMark(
                  x: .value("Common.Copy.date.text".localized, bucket.interval.start, unit: component),
                  y: .value(metric.title, value)
                )
                .foregroundStyle(RunnerStyle.accent).cornerRadius(4)
                .opacity(selected == nil || selected?.id == bucket.id ? 1 : 0.35)
                .accessibilityLabel(bucketLabel(bucket))
                .accessibilityValue(
                  metric.formatted(bucket.summary, units: units))
              }
            }
            if let selected {
              RuleMark(
                x: .value("Common.Copy.selectedDate.text".localized, selected.interval.start, unit: component)
              )
              .foregroundStyle(RunnerStyle.muted).lineStyle(StrokeStyle(dash: [4]))
              .accessibilityHidden(true)
            }
          }
          .chartXScale(domain: first.interval.start...last.interval.end)
          .chartYScale(domain: 0...(maximum * 1.15))
          .chartXAxis {
            AxisMarks(
              values: .stride(
                by: component, count: component == .day ? max(1, buckets.count / 6) : 1)
            ) {
              _ in
              AxisGridLine()
              AxisValueLabel(
                format: component == .month
                  ? .dateTime.month(.abbreviated) : .dateTime.month(.abbreviated).day())
            }
          }
          .chartYAxis {
            if metric == .runs {
              AxisMarks(values: .stride(by: max(1, ceil(maximum / 4)))) {
                AxisGridLine()
                AxisValueLabel(format: Decimal.FormatStyle.number.precision(.fractionLength(0)))
              }
            } else {
              AxisMarks(position: .leading)
            }
          }
          .chartYAxisLabel(metric.unit(units))
          .chartXSelection(value: $selectedDate)
          .chartGesture { proxy in
            SpatialTapGesture().onEnded { value in
              proxy.selectXValue(at: value.location.x)
            }
          }
          .frame(height: 220)
        }
        if let selected {
          Text(
            "\(bucketLabel(selected)): \(metric.formatted(selected.summary, units: units))"
          )
          .font(.subheadline).monospacedDigit().accessibilityAddTraits(.updatesFrequently)
          .accessibilityIdentifier("activity.selection")
          Button("Common.Copy.viewRuns.text".localized) {
            drilldown = RunDrilldown(
              title: bucketLabel(selected), runIDs: statistics.runIDs(in: selected.interval))
          }.buttonStyle(RunnerSecondaryButtonStyle()).accessibilityIdentifier("activity.viewRuns")
        } else if total.runCount > 0 {
          Text(
            "ActivityScreen.Copy.selectAChartBucketToExploreItsTotalsAnd.text".localized
          )
          .font(.caption).foregroundStyle(RunnerStyle.muted)
        }
        if total.runCount == 0 {
          Label(
            "ActivityScreen.Copy.noRunsInThisPeriodImportedRunsWillAppear.text".localized, systemImage: "figure.run"
          )
          .font(.subheadline).foregroundStyle(RunnerStyle.muted)
        }
        if metric.missingCount(total) > 0 {
          Text(
            "ActivityScreen.Format.runsHaveNoMeasurementTotalsIncludeAvailableData.text".localized(String(describing: metric.missingCount(total)), String(describing: metric.title.lowercased()))
          ).font(.footnote).foregroundStyle(RunnerStyle.muted)
        }
        if total.runCount > 0 {
          Button("Common.Copy.exploreChartData.text".localized) { bucketList = true }
            .buttonStyle(RunnerSecondaryButtonStyle()).accessibilityIdentifier(
            "activity.chartData")
        }
      }
    }.sheet(isPresented: $bucketList) {
      NavigationStack {
        List(buckets) { bucket in
          Button {
            selectedDate = bucket.interval.start
            bucketList = false
          } label: {
            Text("\(bucketLabel(bucket)) · \(metric.formatted(bucket.summary, units: units))")
          }
          .accessibilityIdentifier(
            "activity.bucket.\(statistics.calendar.component(.day, from: bucket.interval.start))")
        }.navigationTitle("Common.Copy.chartData.text".localized).toolbar {
          ToolbarItem(placement: .confirmationAction) { Button("Common.Copy.done.text".localized) { bucketList = false } }
        }
      }
    }
  }

  private func compactPerformance(
    _ title: String, interval: DateInterval, statistics: ActivityStatistics
  ) -> some View {
    let summary = statistics.summary(in: interval)
    return VStack(alignment: .leading, spacing: 12) {
      SectionTitle(
        title: title, subtitle: dateRange(interval, throughNow: interval.end == statistics.now))
      MetricGrid {
        MetricTile(
          title: "Common.Copy.runs.text".localized, value: "\(summary.runCount)", unit: "completed", symbol: "figure.run")
        MetricTile(
          title: "Common.Copy.distance.text".localized, value: distance(summary), unit: units.distanceUnit,
          symbol: "point.topleft.down.to.point.bottomright.curvepath")
        MetricTile(
          title: "Common.Copy.movingTime.text".localized, value: summary.movingTimeSeconds.map(UnitSystem.duration) ?? "—",
          unit: "h:mm:ss / m:ss", symbol: "stopwatch")
        MetricTile(
          title: "Common.Copy.averagePace.text".localized, value: units.pace(summary.averagePaceSecondsPerKm),
          unit: "ActivityScreen.Format.min.text".localized(String(describing: units.distanceUnit)), symbol: "speedometer")
      }
      if summary.missingDistanceCount > 0 {
        Text(
          "ActivityScreen.Format.runsHaveNoDistanceTotalsUseAvailableMeasurements.text".localized(String(describing: summary.missingDistanceCount))
        ).font(.footnote).foregroundStyle(.secondary)
      }
    }
  }

  private func comparisonCard(_ title: String, comparison: ActivityComparison) -> some View {
    Surface {
      VStack(alignment: .leading, spacing: 14) {
        SectionTitle(title: title)
        Text(
          "ActivityScreen.Format.vs.text".localized(String(describing: comparisonRange(comparison.currentInterval)), String(describing: comparisonRange(comparison.previousInterval)))
        )
        .font(.caption).foregroundStyle(RunnerStyle.muted)
        if comparison.current.runCount == 0 && comparison.previous.runCount == 0 {
          Text("ActivityScreen.Copy.completeARunInThesePeriodsToStartComparing.text".localized)
            .foregroundStyle(RunnerStyle.muted)
        } else {
          changeRow(runChange(comparison.runCountChange), symbol: "figure.run")
          if let distanceChange = comparison.distanceChangeMeters {
            changeRow(distanceChangeText(distanceChange), symbol: "arrow.left.and.right")
          } else {
            changeRow(
              "ActivityScreen.Copy.distanceComparisonUnavailableSomeRunsHaveNoDistance.text".localized, symbol: "info.circle")
          }
          if let pace = comparison.paceImprovementPercent {
            let text =
              abs(pace) < 0.05
              ? "Common.Copy.averagePaceUnchanged.text".localized
              : "ActivityScreen.Format.averagePace.text".localized(String(describing: abs(pace).formatted(.number.precision(.fractionLength(1)))), String(describing: pace > 0 ? "Common.Copy.faster.text".localized : "Common.Copy.slower.text".localized))
            changeRow(text, symbol: "speedometer")
          } else {
            changeRow(
              "ActivityScreen.Copy.paceComparisonNeedsMeasuredDistanceAndMovingTimeFor.text".localized,
              symbol: "speedometer")
          }
          if comparison.previous.runCount == 0 {
            Text("ActivityScreen.Copy.noRunsInThePreviousComparisonWindowYet.text".localized)
              .font(.footnote).foregroundStyle(RunnerStyle.muted)
          }
        }
      }
    }
  }

  private func changeRow(_ text: String, symbol: String) -> some View {
    Label(text, systemImage: symbol).font(.subheadline)
      .fixedSize(horizontal: false, vertical: true)
  }

  private var rangeTitle: String {
    switch range {
    case .month: return "Common.Copy.currentMonth.text".localized
    case .threeMonths: return "ActivityScreen.Copy.last3MonthsIncludingThisMonth.text".localized
    case .sixMonths: return "ActivityScreen.Copy.last6MonthsIncludingThisMonth.text".localized
    case .year: return "Common.Copy.currentYear.text".localized
    }
  }

  private func distance(_ summary: ActivitySummary) -> String {
    units.distance(summary.distanceMeters)
  }

  private func bucketLabel(_ bucket: ActivityBucket) -> String {
    bucket.interval.start.formatted(.dateTime.month(.abbreviated).day().year())
  }

  private func dateRange(_ interval: DateInterval, throughNow: Bool) -> String {
    let end = throughNow ? interval.end : max(interval.start, interval.end.addingTimeInterval(-1))
    return
      "\(interval.start.formatted(date: .abbreviated, time: .omitted)) – \(end.formatted(date: .abbreviated, time: .omitted))\(throughNow ? "Common.Copy.soFar.text".localized : "")"
  }

  private func comparisonRange(_ interval: DateInterval) -> String {
    "\(interval.start.formatted(.dateTime.month(.abbreviated).day())) – \(interval.end.formatted(.dateTime.month(.abbreviated).day().hour().minute()))"
  }

  private func runChange(_ change: Int) -> String {
    change == 0
      ? "ActivityScreen.Copy.sameNumberOfRuns.text".localized
      : "\(abs(change)) \(abs(change) == 1 ? "run" : "runs") \(change > 0 ? "Common.Copy.more.text".localized : "Common.Copy.fewer.text".localized)"
  }

  private func distanceChangeText(_ change: Double) -> String {
    abs(change) < 5
      ? "Common.Copy.distanceUnchanged.text".localized
      : "\(units.distance(abs(change))) \(units.distanceUnit) \(change > 0 ? "Common.Copy.more.text".localized : "Common.Copy.less.text".localized)"
  }
}
