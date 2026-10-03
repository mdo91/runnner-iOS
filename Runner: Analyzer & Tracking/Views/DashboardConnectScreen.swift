import SwiftUI

struct DashboardConnectScreen: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var historySync: HistorySyncManager
  @State private var code = ""
  @State private var browser: DashboardBrowser?
  @State private var reviewedCode = ""
  @State private var working = false
  @State private var message: String?
  private var normalized: String { code.uppercased().filter { "0123456789ABCDEF".contains($0) } }
  var body: some View {
    NavigationStack {
      Form {
        Section {
          Text("Open the Runner dashboard in your browser, then enter its 10-character sign-in code here.")
          if let url = historySync.dashboardURL { Link("Open dashboard",destination:url) }
          TextField("Dashboard code",text:$code).textInputAutocapitalization(.characters)
            .autocorrectionDisabled().font(.title3.monospaced()).accessibilityLabel("Ten-character dashboard code")
            .onChange(of:code) { _, _ in browser = nil; message = nil }
          Button("Review browser") {
            Task {
              working = true
              defer { working = false }
              do {
                let requested = normalized
                let response = try await historySync.previewBrowser(code:requested)
                guard requested == normalized else { return }
                reviewedCode = requested; browser = response
              } catch { message = "This code is invalid or expired. Request a new code in the browser." }
            }
          }.disabled(normalized.count != 10 || working)
        }
        if let browser {
          Section("Approve dashboard access") {
            Text(browser.agent).font(.footnote).textSelection(.enabled)
            Text("Approve only the browser where you requested this code. It can view all history and routes you have chosen to upload, for up to 12 hours. The session expires after 30 minutes without activity.").font(.footnote)
            Button("Approve this browser") {
              Task {
                working = true
                defer { working = false }
                do {
                  try await historySync.approveBrowser(code:reviewedCode)
                  dismiss()
                } catch { message = "Approval could not finish. Check your connection or request a new code." }
              }
            }.disabled(working).tint(RunnerStyle.blue)
          }
        }
        if working { ProgressView() }
        if let message { Text(message).foregroundStyle(.orange) }
      }.navigationTitle("Connect dashboard").toolbar {
        ToolbarItem(placement:.topBarTrailing) { Button("Done") { dismiss() } }
      }
    }
  }
}
