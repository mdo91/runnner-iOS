import RunCore
import SwiftUI

struct CustomDates: View {
  @Environment(\.dismiss) private var dismiss
  @State var start: Date
  @State var end: Date
  var apply: (DateInterval) -> Void
  private var interval: DateInterval? {
    ActivityDateRange.interval(
      from: start, through: end, now: AppRuntime.now, calendar: AppRuntime.calendar)
  }
  var body: some View {
    NavigationStack {
      Form {
        DatePicker("Common.Copy.from.text".localized, selection: $start, in: ...AppRuntime.now, displayedComponents: .date)
          .accessibilityIdentifier("activity.from")
        DatePicker("Common.Copy.through.text".localized, selection: $end, in: ...AppRuntime.now, displayedComponents: .date)
          .accessibilityIdentifier("activity.through")
        if interval == nil {
          Text("CustomDates.Copy.endDateMustBeOnOrAfterTheStart.text".localized).foregroundStyle(.red)
        }
        Text("CustomDates.Copy.dailyTotalsThrough31DaysWeeklyThrough180Days.text".localized)
          .font(.footnote)
      }.scrollContentBackground(.hidden).background(RunnerStyle.background).navigationTitle("Common.Copy.customDates.text".localized).toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Common.Copy.cancel.text".localized) { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Common.Copy.apply.text".localized) {
            guard let interval else { return }
            apply(interval)
            dismiss()
          }.disabled(interval == nil).accessibilityIdentifier("activity.applyDates")
        }
      }
    }
  }
}
