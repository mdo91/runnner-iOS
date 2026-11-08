import RunCore
import SwiftUI

struct DashboardConnectScreen: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var account: AccountManager
  @StateObject private var connection: DashboardConnectionModel

  init(service: any DashboardLinkServicing) {
    _connection = StateObject(wrappedValue: DashboardConnectionModel(service: service, now: { AppRuntime.now }))
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Text(
            "DashboardConnectScreen.Copy.openTheRunnerDashboardInYourBrowserThenEnter.text".localized
          )
          if let url = connection.dashboardURL { Link("Common.Copy.openDashboard.text".localized, destination: url) }
          TextField("Common.Copy.dashboardCode.text".localized, text: $connection.code)
            .textInputAutocapitalization(.characters).autocorrectionDisabled()
            .font(.title3.monospaced()).accessibilityLabel("Common.Copy.tenCharacterDashboardCode.text".localized).accessibilityIdentifier("dashboard.code")
            .disabled(connection.isWorking)
          Button("Common.Copy.reviewBrowser.text".localized) { Task { await connection.review() } }
            .disabled(!connection.canReview).accessibilityIdentifier("dashboard.review")
        }
        if let browser = connection.browser {
          Section("Common.Copy.approveDashboardAccess.text".localized) {
            Text(browser.agent).font(.footnote).textSelection(.enabled)
            Text(
              "DashboardConnectScreen.Format.codeExpires.text".localized(String(describing: browser.expiresAt.formatted(date: .abbreviated, time: .shortened)))
            )
            .font(.footnote).foregroundStyle(.secondary)
            Text(
              "DashboardConnectScreen.Copy.approveOnlyTheBrowserWhereYouRequestedThisCode.text".localized
            )
            .font(.footnote)
            Button("Common.Copy.approveThisBrowser.text".localized) { Task { await connection.approve() } }
              .disabled(connection.isWorking).buttonStyle(RunnerPrimaryButtonStyle()).accessibilityIdentifier("dashboard.approve")
          }
        }
        if connection.isWorking { ProgressView().accessibilityLabel("Common.Copy.connectingDashboard.text".localized) }
        if let message = connection.message { Text(message).foregroundStyle(.orange).accessibilityIdentifier("dashboard.message") }
      }.scrollContentBackground(.hidden).background(RunnerStyle.background).navigationTitle("Common.Copy.connectDashboard.text".localized).toolbar {
        ToolbarItem(placement: .topBarTrailing) { Button("Common.Copy.done.text".localized) { dismiss() } }
      }
    }
    .onChange(of: account.userID, initial: true) { _, userID in connection.selectAccount(userID) }
    .onChange(of: connection.state) { _, state in if state == .approved { dismiss() } }
    .onDisappear { connection.reset() }
  }
}
