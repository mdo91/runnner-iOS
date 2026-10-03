import RunCore
import SwiftUI

enum RunnerStyle {
  static let background = Color(red: 0.045, green: 0.052, blue: 0.065)
  static let surface = Color(red: 0.085, green: 0.098, blue: 0.12)
  static let blue = Color(red: 0.22, green: 0.55, blue: 1)
  static let muted = Color(red: 0.65, green: 0.70, blue: 0.77)
}
struct Surface<Content: View>: View {
  @ViewBuilder var content: Content
  var body: some View {
    content.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(
      RunnerStyle.surface, in: RoundedRectangle(cornerRadius: 24)
    ).overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.045), lineWidth: 1))
  }
}
struct Stat: View {
  var title: String
  var value: String
  var unit: String
  var symbol: String
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label(title, systemImage: symbol).font(.subheadline).foregroundStyle(RunnerStyle.muted)
      Text(value).font(.system(.title, design: .rounded, weight: .semibold)).monospacedDigit()
      Text(unit).font(.caption).foregroundStyle(RunnerStyle.muted)
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
  var run: RunData
  var units: UnitSystem
  var body: some View {
    let m = RunCalculator.metrics(run)
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
    }.padding(.vertical, 8).accessibilityElement(children: .combine)
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
