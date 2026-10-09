import SwiftUI

struct CustomDates: View {
  @Environment(\.dismiss) private var dismiss
  @State var start: Date
  @State var end: Date
  var apply: (DateInterval) -> Void
  var body: some View {
    NavigationStack {
      Form {
        DatePicker("From", selection: $start, in: ...AppRuntime.now, displayedComponents: .date)
          .accessibilityIdentifier("activity.from")
        DatePicker("Through", selection: $end, in: ...AppRuntime.now, displayedComponents: .date)
          .accessibilityIdentifier("activity.through")
        if end < start {
          Text("End date must be on or after the start date.").foregroundStyle(.red)
        }
        Text("Daily totals through 31 days, weekly through 180 days, monthly for longer ranges.")
          .font(.footnote)
      }.navigationTitle("Custom dates").toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Apply") {
            let calendar = AppRuntime.calendar
            let first = calendar.startOfDay(for: start)
            let until = min(
              AppRuntime.now,
              calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end))!)
            apply(DateInterval(start: first, end: until))
            dismiss()
          }.disabled(end < start).accessibilityIdentifier("activity.applyDates")
        }
      }
    }
  }
}
