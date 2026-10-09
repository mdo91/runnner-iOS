import RunCore
import SwiftUI

struct GoalEditor: View {
  @EnvironmentObject private var settings: TrainingSettings
  @Environment(\.dismiss) private var dismiss
  @FocusState private var editing: Bool
  var goal: TrainingGoal?
  var units: UnitSystem
  @State private var metric: ActivityMetric = .distance
  @State private var period: GoalPeriod = .week
  @State private var targetText = "20"
  private var target: Double? {
    Double(
      targetText.trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: Locale.current.decimalSeparator ?? ".", with: "."))
  }
  private var factor: Double {
    metric == .distance
      ? units.metersPerUnit
      : metric == .movingTime ? 60 : metric == .elevation ? units.metersPerElevationUnit : 1
  }
  private var valid: Bool {
    guard let target else { return false }
    return target.isFinite && (target * factor).isFinite && target > 0
      && (metric != .runs || target.rounded() == target)
  }
  var body: some View {
    NavigationStack {
      Form {
        Picker("Metric", selection: $metric) {
          ForEach(ActivityMetric.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }.accessibilityIdentifier("goal.metric")
        Picker("Repeat", selection: $period) {
          ForEach(GoalPeriod.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }.accessibilityIdentifier("goal.period")
        LabeledContent("Target (\(metric.unit(units)))") {
          TextField("Target", text: $targetText).keyboardType(.decimalPad)
            .focused($editing).submitLabel(.done).onSubmit { editing = false }.accessibilityLabel(
              "Target in \(metric.unit(units))"
            )
            .accessibilityIdentifier("goal.target")
        }
        Text(
          "Targets recur by calendar period. All eligible runs count, including workouts imported before you created the goal."
        ).font(.footnote)
        Section {
          Button {
            guard let target, valid else { return }
            var value = TrainingGoal(metric: metric, period: period, target: target * factor)
            if let goal { value.id = goal.id }
            settings.save(goal: value)
            dismiss()
          } label: {
            Text("Save goal").frame(maxWidth: .infinity, minHeight: 44)
          }.buttonStyle(.glassProminent).disabled(!valid).accessibilityIdentifier("goal.save")
          if let goal {
            Button("Delete goal", role: .destructive) {
              settings.delete(goal: goal)
              dismiss()
            }.accessibilityIdentifier("goal.delete")
          }
        }
      }.scrollDismissesKeyboard(.interactively)
        .navigationTitle(goal == nil ? "New goal" : "Edit goal").toolbar {
          ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
          ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") { editing = false }.accessibilityIdentifier("goal.keyboardDone")
          }
        }.onAppear {
          if let goal {
            metric = goal.metric
            period = goal.period
            targetText = (goal.target / factor).formatted(
              .number.grouping(.never).precision(.fractionLength(0...6)))
          }
        }
    }
  }
}
