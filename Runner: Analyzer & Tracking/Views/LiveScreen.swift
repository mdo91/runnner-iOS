import RunCore
import SwiftUI

struct LiveScreen: View {
  @EnvironmentObject private var live: PhoneWorkoutManager
  @EnvironmentObject private var account: AccountManager
  var history: [RunData]
  var units: UnitSystem
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        if let snapshot = live.snapshot {
          TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let fresh = timeline.date.timeIntervalSince(snapshot.timestamp) < 20 && live.connected
            VStack(alignment: .leading, spacing: 22) {
              Label(
                fresh
                  ? (snapshot.paused ? "PAUSED" : "LIVE FROM APPLE WATCH") : "WATCH DISCONNECTED",
                systemImage: fresh ? "applewatch.radiowaves.left.and.right" : "wifi.slash"
              ).font(.caption.bold()).foregroundStyle(fresh ? RunnerStyle.blue : .orange)
              Text(UnitSystem.duration(snapshot.elapsed)).font(
                .system(size: 64, weight: .semibold, design: .rounded)
              ).minimumScaleFactor(0.5).monospacedDigit()
              Surface {
                MetricPair {
                  Stat(
                    title: "Distance", value: units.distance(snapshot.distance),
                    unit: units.distanceUnit, symbol: "figure.run")
                  Stat(
                    title: "Heart rate",
                    value: fresh
                      ? snapshot.heartRate.map { String(Int($0.rounded())) } ?? "—" : "—",
                    unit: "bpm", symbol: "heart")
                }
              }
              Surface {
                Stat(
                  title: "Average pace",
                  value: units.pace(
                    snapshot.distance > 0 ? snapshot.elapsed / snapshot.distance * 1000 : nil),
                  unit: "min / \(units.distanceUnit)", symbol: "speedometer")
              }
              if fresh, !snapshot.paused,
                let cue = live.targets.cue(
                  heartRate: snapshot.heartRate,
                  pace: snapshot.distance > 100 ? snapshot.elapsed / snapshot.distance * 1000 : nil)
              {
                Surface { Text(cue).font(.headline) }
              }
              if let report = live.insight, let expiry = report.expiresAt, expiry > timeline.date,
                fresh, !snapshot.paused
              {
                Surface {
                  VStack(alignment: .leading, spacing: 8) {
                    Text("Coach note").font(.headline)
                    Text(report.explanation.summary)
                    Text(
                      "AI · updated \(report.generatedAt.formatted(date:.omitted,time:.shortened))"
                    ).font(.caption).foregroundStyle(RunnerStyle.muted)
                  }
                }
              }
              Button(snapshot.paused ? "Resume run" : "Pause run") { live.pauseOrResume() }
                .buttonStyle(.borderedProminent).controlSize(.large).disabled(!fresh)
              Text(
                "End and save your run on Apple Watch. Recording and local coaching continue if your phone disconnects."
              ).font(.footnote).foregroundStyle(RunnerStyle.muted)
            }
          }
        } else {
          EmptyState(
            symbol: "applewatch", title: "Your run, in the moment",
            detail:
              "Start a run in Runner on Apple Watch to see live measurements here. Runs recorded in Apple’s Workout app are imported after they finish."
          )
          Button {
            Task { await live.startWatch() }
          } label: {
            Label("Open Runner on Watch", systemImage: "applewatch").frame(maxWidth: .infinity)
          }.buttonStyle(.borderedProminent).controlSize(.large)
        }
        if let message = live.message {
          Text(message).font(.footnote).foregroundStyle(RunnerStyle.muted)
        }
      }.padding(20)
    }.background(RunnerStyle.background).navigationTitle("Live")

  }
}
