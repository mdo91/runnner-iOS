import SwiftUI

struct DashboardConnectScreen: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var account: AccountManager
  @StateObject private var connection: DashboardConnectionModel

  init(service: any DashboardLinkServicing) {
    _connection = StateObject(wrappedValue: DashboardConnectionModel(service: service))
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Text(
            "Open the Runner dashboard in your browser, then enter its 10-character sign-in code here."
          )
          if let url = connection.dashboardURL { Link("Open dashboard", destination: url) }
          TextField("Dashboard code", text: $connection.code)
            .textInputAutocapitalization(.characters).autocorrectionDisabled()
            .font(.title3.monospaced()).accessibilityLabel("Ten-character dashboard code")
            .disabled(connection.isWorking)
          Button("Review browser") { Task { await connection.review() } }
            .disabled(!connection.canReview)
        }
        if let browser = connection.browser {
          Section("Approve dashboard access") {
            Text(browser.agent).font(.footnote).textSelection(.enabled)
            Text(
              "Code expires \(browser.expiresAt.formatted(date: .abbreviated, time: .shortened))."
            )
            .font(.footnote).foregroundStyle(.secondary)
            Text(
              "Approve only the browser where you requested this code. It can view all history and routes you have chosen to upload, for up to 12 hours. The session expires after 30 minutes without activity."
            )
            .font(.footnote)
            Button("Approve this browser") { Task { await connection.approve() } }
              .disabled(connection.isWorking).tint(RunnerStyle.blue)
          }
        }
        if connection.isWorking { ProgressView().accessibilityLabel("Connecting dashboard") }
        if let message = connection.message { Text(message).foregroundStyle(.orange) }
      }.navigationTitle("Connect dashboard").toolbar {
        ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
      }
    }
    .onChange(of: account.userID, initial: true) { _, userID in connection.selectAccount(userID) }
    .onChange(of: connection.state) { _, state in if state == .approved { dismiss() } }
    .onDisappear { connection.reset() }
  }
}
