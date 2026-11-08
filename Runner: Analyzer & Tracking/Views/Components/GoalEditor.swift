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
        Picker("Common.Copy.metric.text".localized, selection: $metric) {
          ForEach(ActivityMetric.allCases, id: \.self) { Text($0.title).tag($0) }
        }.accessibilityIdentifier("goal.metric")
        Picker("Common.Copy.repeat.text".localized, selection: $period) {
          ForEach(GoalPeriod.allCases, id: \.self) { Text($0.title).tag($0) }
        }.accessibilityIdentifier("goal.period")
        LabeledContent("GoalEditor.Format.target.text".localized(String(describing: metric.unit(units)))) {
          TextField("Common.Copy.target.text".localized, text: $targetText).keyboardType(.decimalPad)
            .focused($editing).submitLabel(.done).onSubmit { editing = false }.accessibilityLabel(
              "GoalEditor.Format.targetIn.text".localized(String(describing: metric.unit(units)))
            )
            .accessibilityIdentifier("goal.target")
        }
        Text(
          "GoalEditor.Copy.targetsRecurByCalendarPeriodAllEligibleRunsCount.text".localized
        ).font(.footnote)
        Section {
          Button {
            guard let target, valid else { return }
            var value = TrainingGoal(metric: metric, period: period, target: target * factor)
            if let goal { value.id = goal.id }
            settings.save(goal: value)
            dismiss()
          } label: {
            Text("Common.Copy.saveGoal.text".localized).frame(maxWidth: .infinity, minHeight: 44)
          }.buttonStyle(RunnerPrimaryButtonStyle()).disabled(!valid).accessibilityIdentifier("goal.save")
          if let goal {
            Button("Common.Copy.deleteGoal.text".localized, role: .destructive) {
              settings.delete(goal: goal)
              dismiss()
            }.accessibilityIdentifier("goal.delete")
          }
        }
      }.scrollContentBackground(.hidden).background(RunnerStyle.background).scrollDismissesKeyboard(.interactively)
        .navigationTitle(goal == nil ? "Common.Copy.newGoal.text".localized : "Common.Copy.editGoal.text".localized).toolbar {
          ToolbarItem(placement: .cancellationAction) { Button("Common.Copy.cancel.text".localized) { dismiss() } }
          ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Common.Copy.done.text".localized) { editing = false }.accessibilityIdentifier("goal.keyboardDone")
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
