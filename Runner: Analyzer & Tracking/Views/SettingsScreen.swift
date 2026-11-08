import AuthenticationServices
import RunCore
import SwiftData
import SwiftUI

struct SettingsScreen: View {
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var context
  @EnvironmentObject private var health: HealthKitManager
  @EnvironmentObject private var account: AccountManager
  @EnvironmentObject private var historySync: HistorySyncManager
  @AppStorage("units") private var units = "metric"
  @State private var targetError: String?
  @State private var deleteAccount = false
  @EnvironmentObject private var training: TrainingSettings
  @State private var clearLocal = false
  @State private var clearCloud = false
  @State private var showOnboarding = false
  @State private var connectDashboard = false
  private let dashboardService: any DashboardLinkServicing = AppRuntime.dashboardService()
  var body: some View {
    NavigationStack {
      Form {
        Section {
          SettingsHeading("Common.Copy.appleHealth.text".localized)
          Text(
            "SettingsScreen.Copy.workoutsHeartRateGPSRoutesAndRunningMeasurementsAre.text".localized
          ).font(.subheadline)
          Button("Common.Copy.reviewHealthAccess.text".localized) { Task { await health.requestAccess() } }
          Text(
            "SettingsScreen.Copy.appleDoesNotRevealWhichReadPermissionsYouGranted.text".localized
          ).font(.caption).foregroundStyle(RunnerStyle.muted)
        }
        Section {
          SettingsHeading("Common.Copy.display.text".localized)
          Picker("Common.Copy.units.text".localized, selection: $units) {
            Text("Common.Copy.kilometers.text".localized).foregroundStyle(RunnerStyle.muted).tag("metric")
            Text("Common.Copy.miles.text".localized).foregroundStyle(RunnerStyle.muted).tag("imperial")
          }.pickerStyle(.inline)
        }
        Section {
          SettingsHeading("Common.Copy.privateByChoice.text".localized)
          if account.signedIn {
            Label("SettingsScreen.Copy.signedInWithApple.text".localized, systemImage: "checkmark.circle.fill").foregroundStyle(
              .green)
            Button("Common.Copy.signOut.text".localized) { account.signOut() }
          } else {
            SignInWithAppleButton(
              .signIn, onRequest: { account.prepare($0) },
              onCompletion: { result in Task { await account.finish(result) } }
            ).signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black).frame(height: 48)
              .disabled(
                !AccountManager.configured)
          }
          Toggle("SettingsScreen.Copy.iAm18OrOlder.text".localized, isOn: $account.adultConfirmed).onChange(
            of: account.adultConfirmed
          ) { _, value in
            AppRuntime.defaults.set(value, forKey: "adultConfirmed")
            if !value { account.setConsent(false) }
          }.accessibilityIdentifier("settings.adult")
          Toggle(
            "Common.Copy.allowAIAnalysis.text".localized,
            isOn: Binding(get: { account.consent }, set: { account.setConsent($0) })
          ).disabled(!account.signedIn || !account.adultConfirmed)
            .accessibilityIdentifier("settings.aiConsent")
          Text(
            "SettingsScreen.Copy.withYourPermissionRunnerSendsNumericalRunSummariesSplits.text".localized
          ).font(.footnote)
          Text(
            "SettingsScreen.Copy.theLatestRunIsAnalyzedAutomaticallyThenNewRuns.text".localized
          ).font(.footnote)
          Text(
            "SettingsScreen.Copy.upTo3CompletedRunAnalysesPerDayYour.text".localized
          ).font(.caption).foregroundStyle(RunnerStyle.muted)
          if let message = account.message { Text(message).font(.footnote) }
        } footer: {
          Text(
            "SettingsScreen.Copy.aIFeedbackIsAdultFitnessCoachingNotMedicalDiagnosis.text".localized
          ).foregroundStyle(RunnerStyle.muted)
        }
        Section {
          SettingsHeading("Common.Copy.cloudHistory.text".localized)
          Toggle(
            "Common.Copy.syncRunningHistory.text".localized,
            isOn: Binding(
              get: { historySync.enabled },
              set: { value in
                Task {
                  await historySync.configure(enabled: value, gps: value && historySync.gpsEnabled)
                }
              })
          ).disabled(!account.signedIn || historySync.changingConsent)
          Text(
            "SettingsScreen.Copy.withYourConsentRunnerStoresYourRunningHistoryMeasured.text".localized
          ).font(.footnote)
          Toggle(
            "SettingsScreen.Copy.alsoSyncPreciseGPSRoutes.text".localized,
            isOn: Binding(
              get: { historySync.gpsEnabled },
              set: { value in
                Task { await historySync.configure(enabled: historySync.enabled, gps: value) }
              })
          ).disabled(!account.signedIn || !historySync.enabled || historySync.changingConsent)
          Text(
            "SettingsScreen.Copy.gPSSharingIsASeparateChoiceRoutesRevealWhere.text".localized
          ).font(.footnote)
          if historySync.isSyncing || historySync.changingConsent { ProgressView() }
          if let message = historySync.message {
            Text(message).font(.caption).foregroundStyle(RunnerStyle.muted)
          }
          Button("Common.Copy.syncNow.text".localized) { Task { await historySync.sync(context: context, account: account) } }
            .disabled(
              !account.signedIn || !historySync.enabled || health.isSyncing || historySync.isSyncing
                || historySync.changingConsent)
          Button("Common.Copy.connectDashboard.text".localized) { connectDashboard = true }.disabled(!account.signedIn)
            .accessibilityIdentifier("settings.dashboard")
          if let url = dashboardService.dashboardURL { Link("Common.Copy.openDashboard.text".localized, destination: url) }
        } footer: {
          Text(
            "SettingsScreen.Copy.onlyRunsAvailableThroughAppleHealthOnThisPhone.text".localized
          ).foregroundStyle(RunnerStyle.muted)
        }
        Section {
          SettingsHeading("Common.Copy.yourData.text".localized)
          NavigationLink("Common.Copy.heartRateZones.text".localized) { ZoneEditor() }.accessibilityIdentifier(
            "settings.zones")
          Button("SettingsScreen.Copy.clearDataFromThisDevice.text".localized, role: .destructive) { clearLocal = true }.disabled(
            health.isSyncing || historySync.isSyncing)
          if account.signedIn {
            Button("Common.Copy.deleteUploadedHistory.text".localized, role: .destructive) { clearCloud = true }.disabled(
              historySync.changingConsent).accessibilityIdentifier("settings.deleteCloudHistory")
            Button("Common.Copy.deleteCloudAccount.text".localized, role: .destructive) { deleteAccount = true }
          }
        }
        Section {
          SettingsHeading("Common.Copy.aboutRunner.text".localized)
          Button("Common.Copy.showIntroduction.text".localized) { showOnboarding = true }
            .accessibilityIdentifier("settings.onboarding")
          Link("Common.Copy.appWebsite.text".localized, destination: ReleaseLinks.website)
          Link("Common.Copy.privacyPolicy.text".localized, destination: ReleaseLinks.privacy)
          Link("Common.Copy.support.text".localized, destination: ReleaseLinks.support)
          Link("Common.Copy.termsOfUse.text".localized, destination: ReleaseLinks.terms)
        }
        Section {
          Text("SettingsScreen.Copy.runner10BuiltForTheLongRun.text".localized).font(.caption).foregroundStyle(
            RunnerStyle.muted)
        }
      }.scrollContentBackground(.hidden).background(RunnerStyle.background)
        .navigationTitle("Common.Copy.settings.text".localized).navigationBarTitleDisplayMode(.inline).toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Common.Copy.done.text".localized) { dismiss() }.accessibilityIdentifier("settings.done")
        }
      }
    }
    .confirmationDialog(
      "SettingsScreen.Copy.clearLocalWorkoutsAndReports.text".localized, isPresented: $clearLocal, titleVisibility: .visible
    ) {
      Button("Common.Copy.clearLocalData.text".localized, role: .destructive) {
        do {
          account.setConsent(false)
          historySync.pauseOnDevice()
          try context.delete(model: RecordedRun.self)
          try context.delete(model: HealthMeasurement.self)
          try context.delete(model: HealthCheckpoint.self)
          try context.delete(model: CloudSyncCheckpoint.self)
          try context.delete(model: DeletedHealthRecord.self)
          try context.save()
          training.clear()
          health.didRequestAccess = false
          AppRuntime.defaults.set(false, forKey: "healthRequested")
        } catch { targetError = "SettingsScreen.Copy.localDataCouldNotBeCleared.text".localized }
      }
    } message: {
      Text(
        "SettingsScreen.Copy.thisDoesNotDeleteWorkoutsFromAppleHealthYou.text".localized
      )
    }
    .fullScreenCover(isPresented: $showOnboarding) { OnboardingView { showOnboarding = false } }
    .sheet(isPresented: $connectDashboard) { DashboardConnectScreen(service: dashboardService) }
    .confirmationDialog(
      "SettingsScreen.Copy.deleteUploadedHistoryAndRoutes.text".localized, isPresented: $clearCloud, titleVisibility: .visible
    ) {
      Button("Common.Copy.deleteUploadedHistory.text".localized, role: .destructive) {
        Task { await historySync.clear(context: context) }
      }.accessibilityIdentifier("settings.confirmDeleteCloudHistory")
    } message: {
      Text(
        "SettingsScreen.Copy.thisRemovesDashboardHistoryAndRoutesFromTheDatabase.text".localized
      )
    }
    .sheet(isPresented: $deleteAccount) {
      VStack(spacing: 24) {
        Text("SettingsScreen.Copy.deleteYourCloudAccount.text".localized).font(.title2.bold())
        Text(
          "SettingsScreen.Copy.yourSyncedHistoryGPSRoutesCloudAnalysesDashboardSessions.text".localized
        ).multilineTextAlignment(.center)
        SignInWithAppleButton(
          .continue, onRequest: { account.prepare($0, deleting: true) },
          onCompletion: { result in
            Task {
              await account.finish(result)
              if !account.signedIn { deleteAccount = false }
            }
          }
        ).signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black).frame(height: 50)
        if let message = account.message { Text(message).font(.footnote) }
        Button("Common.Copy.cancel.text".localized) { deleteAccount = false }
      }.padding(28).presentationDetents([.medium])
    }
  }

}

private struct SettingsHeading: View {
  let title: String
  init(_ title: String) { self.title = title }
  var body: some View {
    Text(title).font(.headline).foregroundStyle(Color(uiColor: .label))
      .fixedSize(horizontal: false, vertical: true)
      .accessibilityAddTraits(.isHeader).listRowSeparator(.hidden)
  }
}
