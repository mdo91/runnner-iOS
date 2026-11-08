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
          title: "Common.Copy.goalsAndConsistency.text".localized,
          subtitle: "GoalsSection.Copy.recurringTargetsCompletedRunsInTheCurrentCalendarPeriod.text".localized)
        if settings.preferences.goals.isEmpty {
          Text("GoalsSection.Copy.setATargetToTrackYourRunningRoutine.text".localized).font(.headline).foregroundStyle(
            .primary)
        }
        ForEach(settings.preferences.goals) { goal in
          let amount = goal.progress(in: statistics)
          Button {
            editing = goal
            editor = true
          } label: {
            VStack(alignment: .leading, spacing: 8) {
              Text(goal.title()).font(.headline)
              Text(
                "\(format(amount, metric: goal.metric)) / \(format(goal.target, metric: goal.metric))"
              ).monospacedDigit().accessibilityIdentifier("goal.progress.\(goal.id.uuidString)")
              if let amount {
                ProgressView(value: min(1, amount / goal.target)).tint(RunnerStyle.accent)
              }
              if goal.metric.missingCount(
                statistics.summary(in: statistics.period(goal.period.component))) > 0
              {
                Text("GoalsSection.Copy.progressIncludesAvailableMeasurementsSomeRunsHaveMissingData.text".localized).font(
                  .caption)
              }
            }
          }.buttonStyle(.plain).accessibilityIdentifier("goal.edit.\(goal.id.uuidString)")
        }
        Button("Common.Copy.addGoal.text".localized) {
          editing = nil
          editor = true
        }.buttonStyle(RunnerSecondaryButtonStyle()).accessibilityIdentifier("goal.add")
        let days = statistics.buckets(in: statistics.period(.month), component: .day).filter {
          $0.summary.runCount > 0
        }.count
        Text("GoalsSection.Count.activeDays.text".localized(days)).font(.headline).foregroundStyle(.primary)
          .accessibilityIdentifier(
            "goals.consistency")
      }
    }.sheet(isPresented: $editor) { GoalEditor(goal: editing, units: units) }
  }
  private func format(_ value: Double?, metric: ActivityMetric) -> String {
    guard let value else { return "—" }
    switch metric {
    case .runs: return "GoalsSection.Format.runs.text".localized(String(describing: value.formatted(.number.precision(.fractionLength(0)))))
    case .distance: return "\(units.distance(value)) \(units.distanceUnit)"
    case .movingTime: return UnitSystem.duration(value)
    case .elevation: return "\(units.elevation(value)) \(units.elevationUnit)"
    }
  }
}
