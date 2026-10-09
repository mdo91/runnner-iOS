import FirebaseAppCheck
import FirebaseCore
import SwiftData
import SwiftUI

@main struct RunnerAnalyzerTrackingApp: App {
  @StateObject private var health = HealthKitManager()
  @StateObject private var account: AccountManager
  @StateObject private var analysis = AnalysisManager()
  @StateObject private var live = PhoneWorkoutManager()
  @StateObject private var historySync = HistorySyncManager()
  private let container: ModelContainer
  init() {
    if !AppRuntime.isFixture,
      Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil
    {
      AppCheck.setAppCheckProviderFactory(AttestationFactory())
      FirebaseApp.configure()
    }
    let account = AccountManager()
    if AppRuntime.isFixture {
      account.signedIn = true
      account.userID = "fixture-account"
      account.consent = false
    }
    _account = StateObject(wrappedValue: account)
    do {
      #if DEBUG
        if PreviewFixtures.enabled {
          container = try ModelContainer(
            for: RecordedRun.self, HealthCheckpoint.self, HealthMeasurement.self,
            CloudSyncCheckpoint.self, DeletedHealthRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
          try PreviewFixtures.install(in: container.mainContext)
        } else {
          container = try Self.localContainer()
        }
      #else
        container = try Self.localContainer()
      #endif
    } catch { fatalError("Unable to open local workout storage: \(error.localizedDescription)") }
  }
  private static func localContainer() throws -> ModelContainer {
    let directory = URL.applicationSupportDirectory.appendingPathComponent(
      "RunnerHealth", isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true,
      attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
    var url = directory
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try url.setResourceValues(values)
    return try ModelContainer(
      for: RecordedRun.self, HealthCheckpoint.self, HealthMeasurement.self,
      CloudSyncCheckpoint.self, DeletedHealthRecord.self,
      configurations: ModelConfiguration(
        url: directory.appendingPathComponent("runs.store"), cloudKitDatabase: .none))
  }
  var body: some Scene {
    WindowGroup {
      ContentView().environmentObject(health).environmentObject(account).environmentObject(analysis)
        .environmentObject(live).environmentObject(historySync)
        .defaultAppStorage(AppRuntime.defaults)
        .environment(\.calendar, AppRuntime.calendar)
        .environment(\.timeZone, AppRuntime.calendar.timeZone)
        .preferredColorScheme(AppRuntime.appearance)
        .modifier(FixtureTextSize())
        .task {
          #if DEBUG
            if PreviewFixtures.enabled { return }
          #endif
          health.configure(container.mainContext)
          live.configure(health.healthStore)
          await health.sync()
        }
    }.modelContainer(container)
  }
}

private struct FixtureTextSize: ViewModifier {
  @Environment(\.dynamicTypeSize) private var size
  func body(content: Content) -> some View {
    content.environment(\.dynamicTypeSize, AppRuntime.largeText ? .accessibility3 : size)
  }
}
