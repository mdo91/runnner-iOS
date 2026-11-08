import RunCore
import SwiftUI

struct OnboardingView: View {
  @EnvironmentObject private var health: HealthKitManager
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var page = 0
  @State private var connecting = false
  let onComplete: () -> Void
  private let pages = ["Welcome", "Health", "Insights", "Progress", "Share", "Privacy"]
  private var section: String { pages[page] }
  private var key: String { "OnboardingView.\(section)Page" }

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text("RUNNER").font(.system(.headline, design: .rounded).weight(.black))
          .tracking(3).foregroundStyle(RunnerStyle.accent)
        Spacer()
        Button("Common.Button.skip.text".localized, action: onComplete)
          .accessibilityIdentifier("onboarding.skip")
      }.padding(.horizontal, 24).padding(.top, 16)
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          Image("Onboarding\(section)").resizable().scaledToFit()
            .frame(maxWidth: .infinity).frame(height: 260).accessibilityHidden(true)
          Text("\(key).title.text".localized)
            .font(.system(.largeTitle, design: .rounded).weight(.heavy))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader).accessibilityIdentifier("onboarding.title")
          Text("\(key).body.text".localized).font(.body)
            .foregroundStyle(RunnerStyle.muted).fixedSize(horizontal: false, vertical: true)
          if page == pages.count - 1 {
            Link("Common.Link.privacy.text".localized, destination: ReleaseLinks.privacy)
            Link("Common.Link.terms.text".localized, destination: ReleaseLinks.terms)
          }
        }.padding(24)
      }
      VStack(spacing: 14) {
        HStack(spacing: 7) {
          ForEach(pages.indices, id: \.self) { index in
            Capsule().fill(index == page ? RunnerStyle.accent : RunnerStyle.muted.opacity(0.3))
              .frame(width: index == page ? 28 : 7, height: 7)
          }
        }.accessibilityElement(children: .ignore)
          .accessibilityLabel("OnboardingView.Progress.accessibility.text".localized(page + 1, pages.count))
        if page == pages.count - 1 {
          Button {
            connecting = true
            Task { await health.requestAccess(); connecting = false; onComplete() }
          } label: {
            HStack {
              if connecting { ProgressView().tint(.black) }
              Text("OnboardingView.HealthButton.title.text".localized)
            }.frame(maxWidth: .infinity)
          }.buttonStyle(RunnerPrimaryButtonStyle()).disabled(connecting)
            .accessibilityIdentifier("onboarding.connectHealth")
          Button("Common.Button.notNow.text".localized, action: onComplete).disabled(connecting)
            .accessibilityIdentifier("onboarding.notNow")
        } else {
          Button("Common.Button.continue.text".localized) { move(1) }
            .buttonStyle(RunnerPrimaryButtonStyle()).accessibilityIdentifier("onboarding.next")
        }
        if page > 0 {
          Button("Common.Button.back.text".localized) { move(-1) }
            .disabled(connecting).accessibilityIdentifier("onboarding.back")
        }
      }.padding(.horizontal, 24).padding(.bottom, 16)
    }.background(RunnerStyle.background).foregroundStyle(.white).tint(RunnerStyle.accent)
      .interactiveDismissDisabled()
  }

  private func move(_ offset: Int) {
    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { page += offset }
  }
}

struct ReleaseRootView: View {
  @AppStorage("onboarding.completedVersion") private var completedVersion = 0
  private var fixtureBypass: Bool { AppRuntime.isFixture && AppRuntime.scenario != "onboarding" }
  var body: some View {
    if completedVersion >= 1 || fixtureBypass {
      ContentView()
    } else {
      OnboardingView { completedVersion = 1 }
    }
  }
}
