import RunCore
import SwiftUI
import WatchKit

final class ExtensionDelegate: NSObject, WKExtensionDelegate {
  func handleActiveWorkoutRecovery() {
    Task { @MainActor in await WorkoutRecorder.shared.recover() }
  }
}
@main struct RunnerWatchApp: App {
  @WKExtensionDelegateAdaptor(ExtensionDelegate.self) var delegate
  @StateObject private var recorder = WorkoutRecorder.shared
  var body: some Scene { WindowGroup { WatchRunView().environmentObject(recorder) } }
}
struct WatchRunView: View {
  @EnvironmentObject var recorder: WorkoutRecorder
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        Label("RUNNER", systemImage: "figure.run").font(.caption.weight(.bold)).foregroundStyle(
          .blue)
        if recorder.phase == .ready || recorder.phase == .saved {
          Text(recorder.phase == .saved ? "Run saved" : "Ready to run?").font(.title2.bold())
          Toggle("Indoor run", isOn: $recorder.indoor)
          Button {
            Task { await recorder.start() }
          } label: {
            Label("Start run", systemImage: "play.fill").frame(maxWidth: .infinity)
          }.tint(.blue).buttonStyle(.borderedProminent)
        } else if recorder.phase == .starting {
          ProgressView("Starting…")
        } else {
          if let live = recorder.snapshot {
            Text(UnitSystem.duration(live.elapsed)).font(
              .system(.largeTitle, design: .rounded, weight: .semibold)
            ).monospacedDigit().minimumScaleFactor(0.6)
            Text("\(recorder.units.distance(live.distance)) \(recorder.units.distanceUnit)").font(
              .title2.bold()
            ).foregroundStyle(.blue)
            HStack {
              Label(
                live.heartRate.map { String(Int($0.rounded())) } ?? "—", systemImage: "heart.fill")
              Spacer()
              Text(
                recorder.units.pace(live.distance > 0 ? live.elapsed / live.distance * 1000 : nil))
            }.font(.title3.monospacedDigit())
            Text("bpm · average pace /\(recorder.units.distanceUnit)").font(.caption2)
              .foregroundStyle(.secondary)
          }
          if let cue = recorder.cue { Text(cue).font(.footnote).foregroundStyle(.orange) }
          if let insight = recorder.aiInsight {
            Text(insight).font(.footnote).foregroundStyle(.secondary)
          }
          if recorder.phase == .running || recorder.phase == .paused {
            Button(recorder.phase == .paused ? "Resume" : "Pause") { recorder.pauseOrResume() }
              .tint(.blue)
            Button("End run", role: .destructive) { recorder.end() }
          }
          if recorder.phase == .review {
            Button("Save to Health") { Task { await recorder.save() } }.tint(.blue).buttonStyle(
              .borderedProminent)
          }
          if recorder.phase == .saving { ProgressView("Saving…") }
        }
        if let message = recorder.message {
          Text(message).font(.footnote).foregroundStyle(.secondary)
        }
      }.frame(maxWidth: .infinity, alignment: .leading)
    }.containerBackground(.black, for: .navigation)
  }
}
