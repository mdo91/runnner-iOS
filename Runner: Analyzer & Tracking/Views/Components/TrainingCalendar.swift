import RunCore
import SwiftUI

struct TrainingCalendar: View {
  var statistics: ActivityStatistics
  var metric: ActivityMetric
  var units: UnitSystem
  var select: (RunDrilldown) -> Void
  @State private var month = AppRuntime.now
  private var calendar: Calendar { statistics.calendar }
  private var dateStyle: Date.FormatStyle {
    Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone)
  }
  var body: some View {
    let interval = calendar.dateInterval(of: .month, for: month)!
    let days = calendar.range(of: .day, in: .month, for: month)!
    let offset =
      (calendar.component(.weekday, from: interval.start) - calendar.firstWeekday + 7) % 7
    let summaries = days.map { day -> ActivitySummary in
      statistics.summary(
        in: calendar.dateInterval(
          of: .day, for: calendar.date(byAdding: .day, value: day - 1, to: interval.start)!)!)
    }
    let maximum = max(1, summaries.compactMap { metric.value($0, units: units) }.max() ?? 0)
    Surface {
      VStack(alignment: .leading, spacing: 14) {
        SectionTitle(
          title: "Training calendar",
          subtitle:
            "Intensity shows \(metric.rawValue.lowercased()). Select a day to review its runs.")
        HStack {
          Button {
            move(-1)
          } label: {
            Image(systemName: "chevron.left")
          }.accessibilityLabel("Previous month").accessibilityIdentifier("calendar.previous")
          Spacer()
          Text(interval.start.formatted(dateStyle.month(.wide).year())).font(.headline)
            .accessibilityIdentifier("calendar.month")
          Spacer()
          Button {
            move(1)
          } label: {
            Image(systemName: "chevron.right")
          }.accessibilityLabel("Next month").accessibilityIdentifier("calendar.next")
            .disabled(interval.end > statistics.now)
        }
        LazyVGrid(
          columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 8
        ) {
          ForEach(0..<7, id: \.self) { index in
            Text(
              calendar.veryShortStandaloneWeekdaySymbols[(calendar.firstWeekday - 1 + index) % 7]
            ).font(.caption).accessibilityHidden(true).id("weekday.\(index)")
          }
          ForEach(0..<offset, id: \.self) { index in
            Color.clear.frame(minHeight: 44).accessibilityHidden(true).id("spacer.\(index)")
          }
          ForEach(Array(days), id: \.self) { day in
            let date = calendar.date(byAdding: .day, value: day - 1, to: interval.start)!
            let window = calendar.dateInterval(of: .day, for: date)!
            let summary = summaries[day - 1]
            Button {
              select(
                RunDrilldown(
                  title: date.formatted(dateStyle.month(.abbreviated).day().year()),
                  runIDs: statistics.runIDs(in: window)))
            } label: {
              VStack(spacing: 2) {
                Text("\(day)").font(.subheadline.monospacedDigit())
                Circle().fill(summary.runCount > 0 ? RunnerStyle.blue : .clear).frame(
                  width: 5, height: 5)
              }.frame(maxWidth: .infinity, minHeight: 44)
                .background(
                  RunnerStyle.blue.opacity(
                    summary.runCount == 0
                      ? 0.03 : 0.12 + 0.22 * (metric.value(summary, units: units) ?? 0) / maximum),
                  in: RoundedRectangle(cornerRadius: 8))
            }.buttonStyle(.plain).disabled(date > statistics.now)
              .accessibilityLabel(
                "\(date.formatted(dateStyle.weekday(.wide).month(.wide).day().year())), \(summary.runCount) runs, \(metric.formatted(summary, units: units))"
              )
              .accessibilityIdentifier("calendar.day.\(day)")
              .id("day.\(day)")
          }
        }
      }
    }
  }
  private func move(_ months: Int) {
    month = calendar.date(byAdding: .month, value: months, to: month) ?? month
  }
}
