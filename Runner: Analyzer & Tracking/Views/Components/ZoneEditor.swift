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
      Section("ZoneEditor.Copy.knownMaximumHeartRate.text".localized) {
        TextField("Common.Copy.maximumBpm.text".localized, value: $maximum, format: .number).keyboardType(.decimalPad)
          .accessibilityIdentifier("zones.maximum").focused($editing)
        Button("Common.Copy.generateBoundaries.text".localized) { boundaries = HeartRateZones(maximum: maximum).boundaries }
          .accessibilityIdentifier("zones.generate")
        Text("ZoneEditor.Copy.useAKnownMaximumRunnerDoesNotInferIt.text".localized)
          .font(.footnote)
      }
      Section("ZoneEditor.Copy.lowerBoundariesBpm.text".localized) {
        ForEach(0..<5, id: \.self) { index in
          HStack {
            Text("ZoneEditor.Format.zone.text".localized(String(describing: index + 1)))
            TextField("Common.Copy.bpm.text".localized, value: $boundaries[index], format: .number).keyboardType(.decimalPad)
              .accessibilityIdentifier("zones.boundary.\(index)").focused($editing)
          }
        }
        if !zones.isValid {
          Text(
            "ZoneEditor.Copy.useAMaximumFrom80240BpmAndFive.text".localized
          ).foregroundStyle(.red).accessibilityIdentifier("zones.error")
        }
      }
      Section {
        Button("Common.Copy.saveZones.text".localized) {
          settings.save(zones: zones)
          dismiss()
        }.disabled(!zones.isValid).accessibilityIdentifier("zones.save")
        Button("Common.Copy.removeZoneSettings.text".localized, role: .destructive) {
          settings.save(zones: nil)
          dismiss()
        }
      }
    }.scrollContentBackground(.hidden).background(RunnerStyle.background).navigationTitle("Common.Copy.heartRateZones.text".localized).scrollDismissesKeyboard(.interactively).toolbar {
      ToolbarItemGroup(placement: .keyboard) {
        Spacer()
        Button("Common.Copy.done.text".localized) { editing = false }.accessibilityIdentifier("zones.keyboardDone")
      }
    }.onAppear {
      if let zones = settings.preferences.zones {
        maximum = zones.maximum
        boundaries = zones.boundaries
      }
    }
  }
}
