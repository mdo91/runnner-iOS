import RunCore
import SwiftUI

struct GoalsSection: View {
  var statistics: ActivityStatistics
  var units: UnitSystem
  @EnvironmentObject private var settings: TrainingSettings
  @State private var editor = false
  @State private var editing: TrainingGoal?
  var body: some View {
    Surface {
      VStack(alignment: .leading, spacing: 14) {
        SectionTitle(
          title: "Goals and consistency",
          subtitle: "Recurring targets · completed runs in the current calendar period")
        if settings.preferences.goals.isEmpty {
          Text("Set a target to track your running routine.").font(.headline).foregroundStyle(
            .primary)
        }
        ForEach(settings.preferences.goals) { goal in
          let amount = goal.progress(in: statistics)
          Button {
            editing = goal
            editor = true
          } label: {
            VStack(alignment: .leading, spacing: 8) {
              Text("\(goal.period.rawValue) \(goal.metric.rawValue.lowercased())").font(.headline)
              Text(
                "\(format(amount, metric: goal.metric)) / \(format(goal.target, metric: goal.metric))"
              ).monospacedDigit().accessibilityIdentifier("goal.progress.\(goal.id.uuidString)")
              if let amount {
                ProgressView(value: min(1, amount / goal.target)).tint(RunnerStyle.blue)
              }
              if goal.metric.missingCount(
                statistics.summary(in: statistics.period(goal.period.component))) > 0
              {
                Text("Progress includes available measurements; some runs have missing data.").font(
                  .caption)
              }
            }
          }.buttonStyle(.plain).accessibilityIdentifier("goal.edit.\(goal.id.uuidString)")
        }
        Button("Add goal") {
          editing = nil
          editor = true
        }.buttonStyle(.glass).accessibilityIdentifier("goal.add")
        let days = statistics.buckets(in: statistics.period(.month), component: .day).filter {
          $0.summary.runCount > 0
        }.count
        Text("\(days) active days this month").font(.headline).foregroundStyle(.primary)
          .accessibilityIdentifier(
            "goals.consistency")
      }
    }.sheet(isPresented: $editor) { GoalEditor(goal: editing, units: units) }
  }
  private func format(_ value: Double?, metric: ActivityMetric) -> String {
    guard let value else { return "—" }
    switch metric {
    case .runs: return "\(value.formatted(.number.precision(.fractionLength(0)))) runs"
    case .distance: return "\(units.distance(value)) \(units.distanceUnit)"
    case .movingTime: return UnitSystem.duration(value)
    case .elevation: return "\(units.elevation(value)) \(units.elevationUnit)"
    }
  }
}
