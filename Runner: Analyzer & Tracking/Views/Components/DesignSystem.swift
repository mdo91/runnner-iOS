import RunCore
import SwiftUI

enum RunnerStyle {
  static let background = Color(uiColor: .systemGroupedBackground)
  static let surface = Color(uiColor: .secondarySystemGroupedBackground)
  static let blue = Color.accentColor
  static let muted = Color(
    uiColor: UIColor { traits in
      traits.userInterfaceStyle == .dark
        ? UIColor(white: 0.72, alpha: 1) : UIColor(white: 0.30, alpha: 1)
    })
}
struct Surface<Content: View>: View {
  @ViewBuilder var content: Content
  var body: some View {
    content.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(
      RunnerStyle.surface, in: RoundedRectangle(cornerRadius: 20)
    ).overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.primary.opacity(0.05), lineWidth: 1))
  }
}
struct Stat: View {
  var title: String
  var value: String
  var unit: String
  var symbol: String
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label(title, systemImage: symbol).fixedSize(horizontal: false, vertical: true).font(
        .subheadline
      ).foregroundStyle(RunnerStyle.muted)
      Text(value).font(.system(.title2, design: .rounded, weight: .semibold)).monospacedDigit()
      Text(unit).fixedSize(horizontal: false, vertical: true).font(.caption).foregroundStyle(
        RunnerStyle.muted)
    }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .ignore)
      .accessibilityLabel("\(title), \(value) \(unit)")
  }
}
struct EmptyState: View {
  var symbol: String
  var title: String
  var detail: String
  var body: some View {
    VStack(spacing: 16) {
      Image(systemName: symbol).font(.system(size: 42, weight: .light)).foregroundStyle(
        RunnerStyle.blue
      ).accessibilityHidden(true)
      Text(title).font(.title2.bold())
      Text(detail).font(.body).foregroundStyle(RunnerStyle.muted).multilineTextAlignment(.center)
    }.frame(maxWidth: .infinity).padding(.vertical, 48).padding(.horizontal, 24)
  }
}
struct SectionTitle: View {
  var title: String
  var subtitle: String? = nil
  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(title).font(.title3.bold())
      if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(RunnerStyle.muted) }
    }
  }
}
struct RunListRow: View {
  @Environment(\.dynamicTypeSize) private var typeSize
  @EnvironmentObject private var analytics: AnalyticsStore
  var run: RunData
  var units: UnitSystem
  var body: some View {
    let m = analytics.snapshot.metrics[run.id] ?? RunCalculator.metrics(run)
    MetricPair {
      Image(systemName: run.indoor ? "figure.run.treadmill" : "figure.run").font(.title2)
        .foregroundStyle(RunnerStyle.blue).frame(width: 44, height: 48).background(
          RunnerStyle.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
      VStack(alignment: .leading, spacing: 5) {
        Text(run.start.formatted(date: .abbreviated, time: .omitted)).font(.headline)
        Text(
          "\(UnitSystem.duration(m.movingSeconds)) · \(units.pace(m.averagePaceSecondsPerKm)) /\(units.distanceUnit)"
        ).font(.subheadline).foregroundStyle(RunnerStyle.muted)
      }
      if !typeSize.isAccessibilitySize { Spacer() }
      VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 3) {
        Text(units.distance(m.distanceMeters)).font(.title3.bold().monospacedDigit())
        Text(units.distanceUnit).font(.caption).foregroundStyle(RunnerStyle.muted)
      }
    }.padding(.vertical, 8).contentShape(Rectangle()).accessibilityElement(children: .combine)
  }
}

struct MetricPair<Content: View>: View {
  @Environment(\.dynamicTypeSize) private var size
  @ViewBuilder var content: Content
  var body: some View {
    let layout =
      size.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 22))
      : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
    layout { content }
  }
}

struct ScreenLayout<Content: View>: View {
  @ViewBuilder var content: Content
  var body: some View {
    content.frame(maxWidth: 960, alignment: .leading).frame(maxWidth: .infinity)
  }
}
