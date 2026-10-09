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
        VStack(alignment: .leading, spacing: 22) {
          SectionTitle(
            title: "Every run adds up",
            subtitle: "Your running volume and progress over time.")
          activityChart(statistics)
          GoalsSection(statistics: statistics, units: units)
          TrainingCalendar(statistics: statistics, metric: metric, units: units) { drilldown = $0 }
          SectionTitle(
            title: "Performance",
            subtitle: "Current periods are totals so far. Previous periods show their full totals.")
          Surface {
            VStack(alignment: .leading, spacing: 18) {
              compactPerformance(
                "Current month", interval: statistics.period(.month), statistics: statistics)
              Divider()
              compactPerformance(
                "Last month", interval: statistics.period(.month, previous: true),
                statistics: statistics)
            }
          }
          Surface {
            VStack(alignment: .leading, spacing: 18) {
              compactPerformance(
                "Current week", interval: statistics.period(.weekOfYear), statistics: statistics)
              Divider()
              compactPerformance(
                "Last week", interval: statistics.period(.weekOfYear, previous: true),
                statistics: statistics)
            }
          }
          SectionTitle(
            title: "Improvements",
            subtitle:
              "Compare the same elapsed portion of each period. Shorter months cap both comparison windows."
          )
          comparisonCard("Monthly progress", comparison: statistics.comparison(.month))
          comparisonCard("Weekly progress", comparison: statistics.comparison(.weekOfYear))
          Text(
            "Based on imported, completed runs and their start dates. Weeks follow your calendar settings. Distance follows your unit preference; average pace uses total moving time divided by measured distance. Different routes and effort can affect pace."
          )
          .font(.footnote).foregroundStyle(RunnerStyle.muted)
        }.padding(20).frame(maxWidth: 960).frame(maxWidth: .infinity)
      }.scrollEdgeEffectHidden(true, for: .bottom)
    }
    .background(RunnerStyle.background).navigationTitle("Activity")
    .sheet(isPresented: $dates) {
      CustomDates(
        start: customInterval?.start
          ?? AppRuntime.calendar.dateInterval(of: .month, for: AppRuntime.now)!.start,
        end: customInterval?.end ?? AppRuntime.now
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
          Picker("Time period", selection: $range) {
            ForEach(ActivityRange.allCases, id: \.self) { Text($0.title).tag($0) }
          }.pickerStyle(.menu)
          Picker("Chart metric", selection: $metric) {
            ForEach(ActivityMetric.allCases, id: \.self) {
              Text($0 == .movingTime ? "Time" : $0 == .elevation ? "Elevation" : $0.rawValue).tag(
                $0
              ).accessibilityLabel($0.rawValue)
            }
          }.pickerStyle(.menu)
        } else {
          Picker("Time period", selection: $range) {
            ForEach(ActivityRange.allCases, id: \.self) { Text($0.title).tag($0) }
          }.pickerStyle(.segmented)
          Picker("Chart metric", selection: $metric) {
            ForEach(ActivityMetric.allCases, id: \.self) {
              Text($0 == .movingTime ? "Time" : $0 == .elevation ? "Elevation" : $0.rawValue).tag(
                $0
              ).accessibilityLabel($0.rawValue)
            }
          }.pickerStyle(.segmented)
        }
        HStack {
          Button("Custom dates") { dates = true }.accessibilityIdentifier("activity.customDates")
          if customInterval != nil {
            Button("Use preset") {
              customInterval = nil
              selectedDate = nil
            }
          }
        }.buttonStyle(.bordered)
        VStack(alignment: .leading, spacing: 6) {
          Text(customInterval == nil ? rangeTitle : "Custom dates").font(.headline).foregroundStyle(
            RunnerStyle.muted)
          Text(metric.formatted(total, units: units))
            .accessibilityIdentifier("activity.total")
            .font(.system(.largeTitle, design: .rounded, weight: .semibold)).monospacedDigit()
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
                  x: .value("Date", bucket.interval.start, unit: component),
                  y: .value(metric.rawValue, value)
                )
                .foregroundStyle(RunnerStyle.blue.gradient).cornerRadius(4)
                .opacity(selected == nil || selected?.id == bucket.id ? 1 : 0.35)
                .accessibilityLabel(bucketLabel(bucket))
                .accessibilityValue(
                  metric.formatted(bucket.summary, units: units))
              }
            }
            if let selected {
              RuleMark(
                x: .value("Selected date", selected.interval.start, unit: component)
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
          Button("View runs") {
            drilldown = RunDrilldown(
              title: bucketLabel(selected), runIDs: statistics.runIDs(in: selected.interval))
          }.accessibilityIdentifier("activity.viewRuns")
        } else if total.runCount > 0 {
          Text(
            "Select a chart bucket to explore its totals and runs."
          )
          .font(.caption).foregroundStyle(RunnerStyle.muted)
        }
        if total.runCount == 0 {
          Label(
            "No runs in this period. Imported runs will appear here.", systemImage: "figure.run"
          )
          .font(.subheadline).foregroundStyle(RunnerStyle.muted)
        }
        if metric.missingCount(total) > 0 {
          Text(
            "\(metric.missingCount(total)) runs have no \(metric.rawValue.lowercased()) measurement. Totals include available data."
          ).font(.footnote).foregroundStyle(RunnerStyle.muted)
        }
        if total.runCount > 0 {
          Button("Explore chart data") { bucketList = true }.accessibilityIdentifier(
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
        }.navigationTitle("Chart data").toolbar {
          ToolbarItem(placement: .confirmationAction) { Button("Done") { bucketList = false } }
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
      LazyVGrid(
        columns: [
          GridItem(
            .adaptive(minimum: typeSize.isAccessibilitySize ? 220 : 140), alignment: .leading)
        ], alignment: .leading, spacing: 16
      ) {
        Stat(title: "Runs", value: "\(summary.runCount)", unit: "completed", symbol: "figure.run")
        Stat(
          title: "Distance", value: distance(summary), unit: units.distanceUnit,
          symbol: "point.topleft.down.to.point.bottomright.curvepath")
        Stat(
          title: "Moving time", value: summary.movingTimeSeconds.map(UnitSystem.duration) ?? "—",
          unit: "h:mm:ss / m:ss", symbol: "stopwatch")
        Stat(
          title: "Average pace", value: units.pace(summary.averagePaceSecondsPerKm),
          unit: "min/\(units.distanceUnit)", symbol: "speedometer")
      }
      if summary.missingDistanceCount > 0 {
        Text(
          "\(summary.missingDistanceCount) runs have no distance. Totals use available measurements."
        ).font(.footnote).foregroundStyle(.secondary)
      }
    }
  }

  private func comparisonCard(_ title: String, comparison: ActivityComparison) -> some View {
    Surface {
      VStack(alignment: .leading, spacing: 14) {
        SectionTitle(title: title)
        Text(
          "\(comparisonRange(comparison.currentInterval)) vs \(comparisonRange(comparison.previousInterval))"
        )
        .font(.caption).foregroundStyle(RunnerStyle.muted)
        if comparison.current.runCount == 0 && comparison.previous.runCount == 0 {
          Text("Complete a run in these periods to start comparing your progress.")
            .foregroundStyle(RunnerStyle.muted)
        } else {
          changeRow(runChange(comparison.runCountChange), symbol: "figure.run")
          if let distanceChange = comparison.distanceChangeMeters {
            changeRow(distanceChangeText(distanceChange), symbol: "arrow.left.and.right")
          } else {
            changeRow(
              "Distance comparison unavailable: some runs have no distance.", symbol: "info.circle")
          }
          if let pace = comparison.paceImprovementPercent {
            let text =
              abs(pace) < 0.05
              ? "Average pace unchanged"
              : "\(abs(pace).formatted(.number.precision(.fractionLength(1))))% \(pace > 0 ? "faster" : "slower") average pace"
            changeRow(text, symbol: "speedometer")
          } else {
            changeRow(
              "Pace comparison needs measured distance and moving time for runs in both periods.",
              symbol: "speedometer")
          }
          if comparison.previous.runCount == 0 {
            Text("No runs in the previous comparison window yet.")
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
    case .month: return "Current month"
    case .threeMonths: return "Last 3 months · including this month"
    case .sixMonths: return "Last 6 months · including this month"
    case .year: return "Current year"
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
      "\(interval.start.formatted(date: .abbreviated, time: .omitted)) – \(end.formatted(date: .abbreviated, time: .omitted))\(throughNow ? " · so far" : "")"
  }

  private func comparisonRange(_ interval: DateInterval) -> String {
    "\(interval.start.formatted(.dateTime.month(.abbreviated).day())) – \(interval.end.formatted(.dateTime.month(.abbreviated).day().hour().minute()))"
  }

  private func runChange(_ change: Int) -> String {
    change == 0
      ? "Same number of runs"
      : "\(abs(change)) \(abs(change) == 1 ? "run" : "runs") \(change > 0 ? "more" : "fewer")"
  }

  private func distanceChangeText(_ change: Double) -> String {
    abs(change) < 5
      ? "Distance unchanged"
      : "\(units.distance(abs(change))) \(units.distanceUnit) \(change > 0 ? "more" : "less")"
  }
}
