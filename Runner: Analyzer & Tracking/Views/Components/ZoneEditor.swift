import RunCore
import SwiftUI

struct ZoneEditor: View {
  @EnvironmentObject private var settings: TrainingSettings
  @Environment(\.dismiss) private var dismiss
  @FocusState private var editing: Bool
  @State private var maximum = 0.0
  @State private var boundaries = Array(repeating: 0.0, count: 5)
  private var zones: HeartRateZones {
    var value = HeartRateZones(maximum: maximum)
    value.boundaries = boundaries
    return value
  }
  var body: some View {
    Form {
      Section("Known maximum heart rate") {
        TextField("Maximum bpm", value: $maximum, format: .number).keyboardType(.decimalPad)
          .accessibilityIdentifier("zones.maximum").focused($editing)
        Button("Generate boundaries") { boundaries = HeartRateZones(maximum: maximum).boundaries }
          .accessibilityIdentifier("zones.generate")
        Text("Use a known maximum. Runner does not infer it from your age or a single workout.")
          .font(.footnote)
      }
      Section("Lower boundaries · bpm") {
        ForEach(0..<5, id: \.self) { index in
          HStack {
            Text("Zone \(index + 1)")
            TextField("bpm", value: $boundaries[index], format: .number).keyboardType(.decimalPad)
              .accessibilityIdentifier("zones.boundary.\(index)").focused($editing)
          }
        }
        if !zones.isValid {
          Text(
            "Use a maximum from 80–240 bpm and five increasing boundaries below it, at least 1 bpm apart."
          ).foregroundStyle(.red).accessibilityIdentifier("zones.error")
        }
      }
      Section {
        Button("Save zones") {
          settings.save(zones: zones)
          dismiss()
        }.disabled(!zones.isValid).accessibilityIdentifier("zones.save")
        Button("Remove zone settings", role: .destructive) {
          settings.save(zones: nil)
          dismiss()
        }
      }
    }.navigationTitle("Heart-rate zones").scrollDismissesKeyboard(.interactively).toolbar {
      ToolbarItemGroup(placement: .keyboard) {
        Spacer()
        Button("Done") { editing = false }.accessibilityIdentifier("zones.keyboardDone")
      }
    }.onAppear {
      if let zones = settings.preferences.zones {
        maximum = zones.maximum
        boundaries = zones.boundaries
      }
    }
  }
}
