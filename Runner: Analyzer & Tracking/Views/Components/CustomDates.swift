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
        DatePicker("From", selection: $start, in: ...AppRuntime.now, displayedComponents: .date)
          .accessibilityIdentifier("activity.from")
        DatePicker("Through", selection: $end, in: ...AppRuntime.now, displayedComponents: .date)
          .accessibilityIdentifier("activity.through")
        if interval == nil {
          Text("End date must be on or after the start date.").foregroundStyle(.red)
        }
        Text("Daily totals through 31 days, weekly through 180 days, monthly for longer ranges.")
          .font(.footnote)
      }.navigationTitle("Custom dates").toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Apply") {
            guard let interval else { return }
            apply(interval)
            dismiss()
          }.disabled(interval == nil).accessibilityIdentifier("activity.applyDates")
        }
      }
    }
  }
}
