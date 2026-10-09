import Charts
import RunCore
import SwiftUI

struct ActivityScreen: View {
  var rows: [RecordedRun]

  var body: some View {
    ActivityContent(runs: rows.compactMap(\.run))
  }
}

private struct ActivityContent: View {
  // Decode stored workouts outside the interactive view so chart taps and clock
  // updates do not repeatedly decode the entire history, including GPS payloads.
  var runs: [RunData]
  @Environment(\.dynamicTypeSize) private var typeSize
  @State private var range: ActivityRange = .month
  @State private var metric: ActivityMetric = .runs
  @State private var selectedDate: Date?

  private enum ActivityMetric: String, CaseIterable {
    case runs = "Runs"
    case kilometers = "Kilometers"
  }

  var body: some View {
    TimelineView(.periodic(from: .now, by: 60)) { timeline in
      let statistics = ActivityStatistics(runs: runs, now: timeline.date)
      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          SectionTitle(
            title: "Every run adds up",
            subtitle: "Your running volume and progress over time.")
          activityChart(statistics)
          SectionTitle(
            title: "Performance",
            subtitle: "Current periods are totals so far. Previous periods show their full totals.")
          performanceCard(
            "Current month", interval: statistics.period(.month), statistics: statistics)
          performanceCard(
            "Last month", interval: statistics.period(.month, previous: true),
            statistics: statistics)
          performanceCard(
            "Current week", interval: statistics.period(.weekOfYear), statistics: statistics)
          performanceCard(
            "Last week", interval: statistics.period(.weekOfYear, previous: true),
            statistics: statistics)
          SectionTitle(
            title: "Improvements",
            subtitle:
              "Compare the same elapsed portion of each period. Shorter months cap both comparison windows."
          )
          comparisonCard("Monthly progress", comparison: statistics.comparison(.month))
          comparisonCard("Weekly progress", comparison: statistics.comparison(.weekOfYear))
          Text(
            "Based on imported, completed runs and their start dates. Weeks follow your calendar settings. Distance is shown in kilometers; average pace uses total moving time divided by measured distance. Different routes and effort can affect pace."
          )
          .font(.footnote).foregroundStyle(RunnerStyle.muted)
        }.padding(20)
      }
    }
    .background(RunnerStyle.background).navigationTitle("Activity")
    .onChange(of: range) { _, _ in selectedDate = nil }
    .onChange(of: metric) { _, _ in selectedDate = nil }
  }

  private func activityChart(_ statistics: ActivityStatistics) -> some View {
    let buckets = statistics.buckets(for: range)
    let total = statistics.summary(
      in: range.interval(now: statistics.now, calendar: statistics.calendar))
    let selected = selectedDate.flatMap { date in
      buckets.first { date >= $0.interval.start && date < $0.interval.end }
    }
    let maximum = max(1, buckets.compactMap { chartValue($0.summary) }.max() ?? 0)
    return Surface {
      VStack(alignment: .leading, spacing: 18) {
        if typeSize.isAccessibilitySize {
          Picker("Time period", selection: $range) {
            ForEach(ActivityRange.allCases, id: \.self) { Text($0.title).tag($0) }
          }.pickerStyle(.menu)
          Picker("Chart metric", selection: $metric) {
            ForEach(ActivityMetric.allCases, id: \.self) { Text($0.rawValue).tag($0) }
          }.pickerStyle(.menu)
        } else {
          Picker("Time period", selection: $range) {
            ForEach(ActivityRange.allCases, id: \.self) { Text($0.title).tag($0) }
          }.pickerStyle(.segmented)
          Picker("Chart metric", selection: $metric) {
            ForEach(ActivityMetric.allCases, id: \.self) { Text($0.rawValue).tag($0) }
          }.pickerStyle(.segmented)
        }
        VStack(alignment: .leading, spacing: 6) {
          Text(rangeTitle).font(.headline).foregroundStyle(RunnerStyle.muted)
          Text(metric == .runs ? "\(total.runCount) runs" : "\(distance(total)) km")
            .font(.system(.largeTitle, design: .rounded, weight: .semibold)).monospacedDigit()
          Text(
            dateRange(
              range.interval(now: statistics.now, calendar: statistics.calendar), throughNow: true)
          )
          .font(.subheadline).foregroundStyle(RunnerStyle.muted)
        }.accessibilityElement(children: .combine)
        Chart {
          ForEach(buckets) { bucket in
            if let value = chartValue(bucket.summary) {
              BarMark(
                x: .value("Date", bucket.interval.start, unit: range.bucketComponent),
                y: .value(metric.rawValue, value)
              )
              .foregroundStyle(RunnerStyle.blue.gradient).cornerRadius(4)
              .opacity(selected == nil || selected?.id == bucket.id ? 1 : 0.35)
              .accessibilityLabel(bucketLabel(bucket))
              .accessibilityValue(
                metric == .runs
                  ? "\(bucket.summary.runCount) runs" : "\(distance(bucket.summary)) kilometers")
            }
          }
          if let selected {
            RuleMark(
              x: .value("Selected date", selected.interval.start, unit: range.bucketComponent)
            )
            .foregroundStyle(RunnerStyle.muted).lineStyle(StrokeStyle(dash: [4]))
            .accessibilityHidden(true)
          }
        }
        .chartXScale(domain: buckets.first!.interval.start...buckets.last!.interval.end)
        .chartYScale(domain: 0...(maximum * 1.15))
        .chartXAxis {
          AxisMarks(values: .stride(by: range.bucketComponent, count: range == .month ? 5 : 1)) {
            _ in
            AxisGridLine()
            AxisValueLabel(
              format: range == .month ? .dateTime.day() : .dateTime.month(.abbreviated))
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
        .chartYAxisLabel(metric == .runs ? "Runs" : "km")
        .chartXSelection(value: $selectedDate)
        .chartGesture { proxy in
          SpatialTapGesture().onEnded { value in
            proxy.selectXValue(at: value.location.x)
          }
        }
        .frame(height: 220)
        if let selected {
          Text(
            "\(bucketLabel(selected)): \(selected.summary.runCount) runs · \(distance(selected.summary)) km"
          )
          .font(.subheadline).monospacedDigit().accessibilityAddTraits(.updatesFrequently)
        } else {
          Text(
            range == .month
              ? "Daily totals · Tap the chart to explore"
              : "Monthly totals · Tap the chart to explore"
          )
          .font(.caption).foregroundStyle(RunnerStyle.muted)
        }
        if total.runCount == 0 {
          Label(
            "No runs in this period. Imported runs will appear here.", systemImage: "figure.run"
          )
          .font(.subheadline).foregroundStyle(RunnerStyle.muted)
        }
        if total.missingDistanceCount > 0 {
          Text(
            "Distance is unavailable for \(total.missingDistanceCount) runs. Distance totals include only measured kilometers; those runs still count toward Runs."
          )
          .font(.footnote).foregroundStyle(RunnerStyle.muted)
        }
      }
    }
  }

  private func performanceCard(
    _ title: String, interval: DateInterval, statistics: ActivityStatistics
  ) -> some View {
    let summary = statistics.summary(in: interval)
    return Surface {
      VStack(alignment: .leading, spacing: 18) {
        SectionTitle(
          title: title, subtitle: dateRange(interval, throughNow: interval.end == statistics.now))
        MetricPair {
          Stat(title: "Runs", value: "\(summary.runCount)", unit: "completed", symbol: "figure.run")
          Stat(
            title: "Distance", value: distance(summary), unit: "km",
            symbol: "point.topleft.down.to.point.bottomright.curvepath")
        }
        MetricPair {
          Stat(
            title: "Moving time", value: UnitSystem.duration(summary.movingSeconds),
            unit: summary.movingSeconds >= 3600 ? "h:mm:ss" : "m:ss", symbol: "stopwatch")
          Stat(
            title: "Average pace", value: UnitSystem.metric.pace(summary.averagePaceSecondsPerKm),
            unit: "min/km", symbol: "speedometer")
        }
        if summary.missingDistanceCount > 0 {
          Text(
            "\(summary.missingDistanceCount) runs have no distance. Distance and pace use available measurements."
          )
          .font(.footnote).foregroundStyle(RunnerStyle.muted)
        }
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

  private func chartValue(_ summary: ActivitySummary) -> Double? {
    metric == .runs ? Double(summary.runCount) : summary.distanceMeters.map { $0 / 1000 }
  }

  private func distance(_ summary: ActivitySummary) -> String {
    UnitSystem.metric.distance(summary.distanceMeters)
  }

  private func bucketLabel(_ bucket: ActivityBucket) -> String {
    range == .month
      ? bucket.interval.start.formatted(.dateTime.month(.abbreviated).day())
      : bucket.interval.start.formatted(.dateTime.month(.wide).year())
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
      : "\(UnitSystem.metric.distance(abs(change))) km \(change > 0 ? "more" : "less")"
  }
}
