import CryptoKit
import FirebaseAuth
import Foundation
import RunCore
import SwiftData

struct HistoryPreferences: Codable {
  var enabled: Bool
  var gpsEnabled: Bool
  var privacyRevision: Int
  var consentVersion: String
  var updatedAt: String?
}
private struct HistoryPreferenceInput: Codable {
  var consentVersion = "2026-10-03-history-v1"
  var enabled: Bool
  var gpsEnabled: Bool
}
private struct HistoryBatch: Encodable {
  let schemaVersion = 1
  let consentVersion = "2026-10-03-history-v1"
  var privacyRevision: Int
  var runs: [CloudRun] = []
  var measurements: [CloudMeasurement] = []
  var deletedRunIDs: [UUID] = []
  var deletedMeasurementIDs: [UUID] = []
}
struct DashboardBrowser: Decodable { var agent: String; var expiresAt: String }
@MainActor final class HistorySyncManager: ObservableObject {
  @Published private(set) var enabled = false
  @Published private(set) var gpsEnabled = false
  @Published private(set) var isSyncing = false
  @Published private(set) var changingConsent = false
  @Published var message: String?
  @Published private(set) var revision = 0
  @Published private(set) var changeCounter = 0
  private var uid: String?
  private var retryNeeded = false
  private var consentGeneration = 0
  var dashboardURL: URL? { APIClient.baseURL?.appendingPathComponent("dashboard") }
  private func key(_ name: String, _ uid: String) -> String { "cloudHistory.\(uid).\(name)" }
  func selectAccount(_ userID: String?) {
    guard uid != userID else { return }
    uid = userID
    consentGeneration += 1
    enabled = userID.map { UserDefaults.standard.bool(forKey: key("enabled",$0)) } ?? false
    gpsEnabled = enabled && (userID.map { UserDefaults.standard.bool(forKey: key("gps",$0)) } ?? false)
    message = nil
    changeCounter += 1
  }
  private func persist(_ prefs: HistoryPreferences, uid: String) {
    guard self.uid == uid else { return }
    let changed = enabled != prefs.enabled || gpsEnabled != prefs.gpsEnabled || revision != prefs.privacyRevision
    enabled = prefs.enabled; gpsEnabled = prefs.gpsEnabled; revision = prefs.privacyRevision
    UserDefaults.standard.set(enabled,forKey:key("enabled",uid))
    UserDefaults.standard.set(gpsEnabled,forKey:key("gps",uid))
    if changed { changeCounter += 1 }
  }
  func configure(enabled: Bool, gps: Bool) async {
    guard let uid, Auth.auth().currentUser?.uid == uid, !changingConsent else { return }
    consentGeneration += 1
    changingConsent = true
    defer { changingConsent = false }
    let previousEnabled = self.enabled, previousGPS = gpsEnabled
    let withdrawal = !enabled || (previousGPS && !gps)
    let input = HistoryPreferenceInput(enabled: enabled, gpsEnabled: enabled && gps)
    if !enabled || !gps {
      self.enabled = enabled; self.gpsEnabled = enabled && gps
      UserDefaults.standard.set(enabled,forKey:key("enabled",uid))
      UserDefaults.standard.set(enabled && gps,forKey:key("gps",uid))
    }
    do {
      let payload = try APIClient.encode(input)
      // Persist a withdrawal until the server confirms removal, even if the app closes offline.
      if withdrawal { UserDefaults.standard.set(payload,forKey:key("pendingPrivacy",uid)) }
      let data = try await APIClient.request(path:"v1/history/preferences",method:"PUT",body:payload,expectedUID:uid)
      let prefs = try JSONDecoder().decode(HistoryPreferences.self,from:data)
      guard self.uid == uid else { return }
      UserDefaults.standard.removeObject(forKey:key("pendingPrivacy",uid))
      persist(prefs,uid:uid)
      message = prefs.enabled ? (prefs.gpsEnabled ? "History and routes sync is enabled." : "History sync is enabled. Uploaded GPS coordinates have been removed.") : "History sync is off. Uploaded GPS coordinates have been removed; numerical history remains until you delete it."
    } catch {
      guard self.uid == uid else { return }
      // Never silently retry an unconfirmed opt-in. Withdrawals are retried on the next sync.
      if !withdrawal {
        self.enabled = previousEnabled; self.gpsEnabled = previousGPS
        UserDefaults.standard.set(previousEnabled,forKey:key("enabled",uid))
        UserDefaults.standard.set(previousGPS,forKey:key("gps",uid))
      }
      message = withdrawal ? "Sharing is paused on this phone. Connect to the internet to finish the privacy change and remove uploaded GPS coordinates." : "Consent could not be saved. Please retry when connected."
    }
  }
  func sync(context: ModelContext, account: AccountManager) async {
    #if DEBUG
      if PreviewFixtures.enabled { return }
    #endif
    selectAccount(account.userID)
    guard !changingConsent else { return }
    let generation = consentGeneration
    guard let uid, account.signedIn, Auth.auth().currentUser?.uid == uid else { return }
    guard !isSyncing else { retryNeeded = true; return }
    isSyncing = true
    defer {
      isSyncing = false
      if retryNeeded { retryNeeded = false; Task { await sync(context:context,account:account) } }
    }
    do {
      if let pending = UserDefaults.standard.data(forKey:key("pendingPrivacy",uid)) {
        let input = try JSONDecoder().decode(HistoryPreferenceInput.self,from:pending)
        // Only retry withdrawals automatically; opt-ins must complete from the consent control.
        guard !input.enabled || !input.gpsEnabled else { return }
        let data = try await APIClient.request(path:"v1/history/preferences",method:"PUT",body:pending,expectedUID:uid)
        guard consentGeneration == generation, self.uid == uid, !changingConsent else { return }
        UserDefaults.standard.removeObject(forKey:key("pendingPrivacy",uid))
        persist(try JSONDecoder().decode(HistoryPreferences.self,from:data),uid:uid)
      }
      guard enabled, !changingConsent else { return }
      let data = try await APIClient.request(path:"v1/history/preferences",method:"GET",expectedUID:uid)
      let server = try JSONDecoder().decode(HistoryPreferences.self,from:data)
      guard consentGeneration == generation, self.uid == uid, enabled, !changingConsent else { return }
      // A separate opt-in on this phone is still required before uploading its GPS data.
      let gps = gpsEnabled && server.gpsEnabled
      persist(HistoryPreferences(enabled:server.enabled,gpsEnabled:gps,privacyRevision:server.privacyRevision,consentVersion:server.consentVersion,updatedAt:server.updatedAt),uid:uid)
      guard server.enabled else { message = "History sync is paused. Saved dashboard history remains available."; return }
      let checkpoints = try context.fetch(FetchDescriptor<CloudSyncCheckpoint>())
      var hashes = Dictionary(uniqueKeysWithValues:checkpoints.map { ($0.key,$0.payloadDigest) })
      let tombstones = try context.fetch(FetchDescriptor<DeletedHealthRecord>())
      var pendingDeletes = tombstones.filter { hashes[key("delete-"+$0.key,uid)] != "\(server.privacyRevision):deleted" }
      while !pendingDeletes.isEmpty {
        guard allowed(uid:uid,account:account,gps:gps) else { return }
        let page = Array(pendingDeletes.prefix(100))
        var batch = HistoryBatch(privacyRevision:server.privacyRevision)
        batch.deletedRunIDs = page.filter { $0.kind == "run" }.map(\.id)
        batch.deletedMeasurementIDs = page.filter { $0.kind == "measurement" }.map(\.id)
        _ = try await send(batch,uid:uid)
        guard allowed(uid:uid,account:account,gps:gps) else { return }
        for row in page { try checkpoint(key:key("delete-"+row.key,uid),hash:"\(server.privacyRevision):deleted",context:context,hashes:&hashes) }
        pendingDeletes.removeFirst(page.count)
      }
      let rows = try context.fetch(FetchDescriptor<RecordedRun>(sortBy:[SortDescriptor(\.start,order:.reverse)]))
      var count = 0
      for row in rows {
        guard allowed(uid:uid,account:account,gps:gps) else { return }
        guard let run = row.run else { continue }
        let report = row.report, deleted = row.routeDeleted
        let payload = await Task.detached(priority:.utility) { CloudRun(run,gpsConsent:gps,report:report,routeDeleted:deleted) }.value
        let hash = "\(server.privacyRevision):\(try hashValue(payload))", checkpointKey = key("run-"+row.id.uuidString,uid)
        if hashes[checkpointKey] != hash {
          var batch = HistoryBatch(privacyRevision:server.privacyRevision); batch.runs = [payload]
          _ = try await send(batch,uid:uid)
          guard allowed(uid:uid,account:account,gps:gps) else { return }
          try checkpoint(key:checkpointKey,hash:hash,context:context,hashes:&hashes)
        }
        count += 1; message = "Synced \(count) of \(rows.count) runs."
      }
      let values = try context.fetch(FetchDescriptor<HealthMeasurement>())
      var batch = HistoryBatch(privacyRevision:server.privacyRevision), saved: [(String,String)] = []
      for value in values {
        let kind = value.kind == "HKQuantityTypeIdentifierVO2Max" ? "vo2Max" : "recoveryBpm"
        guard value.value.isFinite, (-100...150).contains(value.value), kind != "vo2Max" || value.value > 0 else { continue }
        let payload = CloudMeasurement(id:value.id,kind:kind,value:value.value,measuredAt:value.date)
        let hash = "\(server.privacyRevision):\(try hashValue(payload))", checkpointKey = key("measurement-"+value.id.uuidString,uid)
        guard hashes[checkpointKey] != hash else { continue }
        batch.measurements.append(payload);saved.append((checkpointKey,hash))
        if batch.measurements.count == 100 {
          guard allowed(uid:uid,account:account,gps:gps) else { return }
          _ = try await send(batch,uid:uid)
          guard allowed(uid:uid,account:account,gps:gps) else { return }
          for (key,hash) in saved { try checkpoint(key:key,hash:hash,context:context,hashes:&hashes) }
          batch.measurements = [];saved = []
        }
      }
      if !batch.measurements.isEmpty {
        guard allowed(uid:uid,account:account,gps:gps) else { return }
        _ = try await send(batch,uid:uid)
        guard allowed(uid:uid,account:account,gps:gps) else { return }
        for (key,hash) in saved { try checkpoint(key:key,hash:hash,context:context,hashes:&hashes) }
      }
      message = "\(rows.count) runs synced. Last checked \(Date().formatted(date:.omitted,time:.shortened))."
    } catch {
      if self.uid == uid { message = "History sync paused. Saved runs remain available. Reconnect and tap Sync now to retry. If consent changed on another device, this phone will follow it on retry." }
    }
  }
  private func allowed(uid: String, account: AccountManager, gps: Bool) -> Bool {
    self.uid == uid && account.userID == uid && account.signedIn && enabled && !changingConsent && (!gps || gpsEnabled)
  }
  private func send(_ batch: HistoryBatch, uid: String) async throws -> Data {
    try await APIClient.request(path:"v1/history/sync",method:"POST",body:APIClient.encode(batch),expectedUID:uid)
  }
  private func hashValue<T: Encodable>(_ value: T) throws -> String {
    SHA256.hash(data:try APIClient.encode(value)).map { String(format:"%02x",$0) }.joined()
  }
  private func checkpoint(key: String, hash: String, context: ModelContext, hashes: inout [String:String]) throws {
    let descriptor = FetchDescriptor<CloudSyncCheckpoint>(predicate:#Predicate { $0.key == key })
    if let row = try context.fetch(descriptor).first { row.payloadDigest = hash }
    else { context.insert(CloudSyncCheckpoint(key:key,payloadDigest:hash)) }
    try context.save();hashes[key] = hash
  }
  func pauseOnDevice() {
    guard let uid else { return }
    consentGeneration += 1
    enabled = false; gpsEnabled = false
    UserDefaults.standard.set(false,forKey:key("enabled",uid))
    UserDefaults.standard.set(false,forKey:key("gps",uid))
    changeCounter += 1
  }
  func clear(context: ModelContext) async {
    guard let uid else { return }
    await configure(enabled:false,gps:false)
    do {
      _ = try await APIClient.request(path:"v1/history",method:"DELETE",expectedUID:uid)
      for row in try context.fetch(FetchDescriptor<CloudSyncCheckpoint>()) where row.key.hasPrefix("cloudHistory.\(uid).") { context.delete(row) }
      try context.save();message = "Your uploaded history and routes have been deleted. Local Health workouts remain."
    } catch { message = "Cloud history could not be deleted. Please reconnect and retry." }
  }
  func previewBrowser(code: String) async throws -> DashboardBrowser {
    guard let uid else { throw APIClient.APIError.authentication }
    let data = try await APIClient.request(path:"v1/dashboard/link/\(code)",method:"GET",expectedUID:uid)
    return try JSONDecoder().decode(DashboardBrowser.self,from:data)
  }
  func approveBrowser(code: String) async throws {
    guard let uid else { throw APIClient.APIError.authentication }
    _ = try await APIClient.request(path:"v1/dashboard/approve",method:"POST",body:APIClient.encode(["code":code]),expectedUID:uid)
  }
}
