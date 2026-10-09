import RunCore
import SQLite3
import SwiftData
import XCTest

// The previous on-disk model shapes, before cloud checkpoints and deletion markers were added.
private enum PreviousHealthSchema {
  @Model final class RecordedRun {
    @Attribute(.unique) var id: UUID
    var start: Date
    var importedAt: Date
    @Attribute(.externalStorage) var payload: Data
    var reportData: Data?
    var reportInputHash: String?
    var lastAnalysisAttempt: Date?
    init(_ run: RunData) throws {
      id = run.id
      start = run.start
      importedAt = run.importedAt
      payload = try JSONEncoder().encode(run)
    }
  }
  @Model final class HealthCheckpoint {
    @Attribute(.unique) var key: String
    var anchor: Data?
    init(key: String) { self.key = key }
  }
  @Model final class HealthMeasurement {
    @Attribute(.unique) var id: UUID
    var kind: String
    var value: Double
    var date: Date
    init(id: UUID, kind: String, value: Double, date: Date) {
      self.id = id
      self.kind = kind
      self.value = value
      self.date = date
    }
  }
}
private enum PreviousCloudSchema {
  @Model final class CloudSyncCheckpoint {
    @Attribute(.unique) var key: String
    var hash: String
    init(key: String, hash: String) {
      self.key = key
      self.hash = hash
    }
  }
}

@MainActor final class HistoryStorageTests: XCTestCase {
  func testSavedCloudCheckpointsCanBeFetchedAfterReopeningStore() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "runner-checkpoints-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("runs.store")
    try autoreleasepool {
      let container = try ModelContainer(
        for: CloudSyncCheckpoint.self,
        configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
      container.mainContext.insert(
        CloudSyncCheckpoint(key: "cloudHistory.user.run-1", payloadDigest: "4:payload-digest"))
      try container.mainContext.save()
    }
    let container = try ModelContainer(
      for: CloudSyncCheckpoint.self,
      configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
    let checkpoints = try container.mainContext.fetch(FetchDescriptor<CloudSyncCheckpoint>())
    XCTAssertEqual(checkpoints.count, 1)
    XCTAssertEqual(checkpoints.first?.payloadDigest, "4:payload-digest")
    checkpoints.first?.payloadDigest = "5:updated-digest"
    try container.mainContext.save()
    let freshContext = ModelContext(container)
    XCTAssertEqual(
      try freshContext.fetch(FetchDescriptor<CloudSyncCheckpoint>()).first?.payloadDigest,
      "5:updated-digest")
  }

  func testLegacyCloudCheckpointsMigrateWithoutLosingHealthData() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "runner-cloud-migration-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("runs.store")
    let start = Date(timeIntervalSince1970: 1_780_000_000)
    let run = RunData(
      start: start, end: start.addingTimeInterval(1500), duration: 1500, distanceMeters: 5000,
      source: "Migration fixture")
    let measurementID = UUID()
    let deletedID = UUID()
    try autoreleasepool {
      let previous = try ModelContainer(
        for: RecordedRun.self, HealthCheckpoint.self, HealthMeasurement.self,
        PreviousCloudSchema.CloudSyncCheckpoint.self, DeletedHealthRecord.self,
        configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
      previous.mainContext.insert(try RecordedRun(run))
      let anchor = HealthCheckpoint(key: "workouts")
      anchor.anchor = Data([1, 2, 3])
      previous.mainContext.insert(anchor)
      previous.mainContext.insert(
        HealthMeasurement(id: measurementID, kind: "VO2", value: 42, date: start))
      previous.mainContext.insert(DeletedHealthRecord(id: deletedID, kind: "run"))
      try previous.mainContext.save()
    }
    // The old model crashes while materializing `hash`, even when making a fixture.
    // Seed only this generated legacy table directly; production never edits SQLite.
    var database: OpaquePointer?
    XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
    defer { sqlite3_close(database) }
    let sql = """
      INSERT INTO ZCLOUDSYNCCHECKPOINT (Z_PK, Z_ENT, Z_OPT, ZKEY, ZHASH)
      VALUES (1, (SELECT Z_ENT FROM Z_PRIMARYKEY WHERE Z_NAME = 'CloudSyncCheckpoint'), 1, 'cloudHistory.user.run-1', '4:legacy-digest'),
             (2, (SELECT Z_ENT FROM Z_PRIMARYKEY WHERE Z_NAME = 'CloudSyncCheckpoint'), 1, 'cloudHistory.other.delete-run-1', '3:deleted');
      UPDATE Z_PRIMARYKEY SET Z_MAX = 2 WHERE Z_NAME = 'CloudSyncCheckpoint';
      """
    XCTAssertEqual(sqlite3_exec(database, sql, nil, nil, nil), SQLITE_OK)
    sqlite3_close(database)
    database = nil
    let current = try ModelContainer(
      for: RecordedRun.self, HealthCheckpoint.self, HealthMeasurement.self,
      CloudSyncCheckpoint.self, DeletedHealthRecord.self,
      configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
    let checkpoints = try current.mainContext.fetch(FetchDescriptor<CloudSyncCheckpoint>())
    XCTAssertEqual(
      Dictionary(uniqueKeysWithValues: checkpoints.map { ($0.key, $0.payloadDigest) }),
      [
        "cloudHistory.user.run-1": "4:legacy-digest",
        "cloudHistory.other.delete-run-1": "3:deleted",
      ])
    XCTAssertEqual(try current.mainContext.fetch(FetchDescriptor<RecordedRun>()).first?.run, run)
    XCTAssertEqual(
      try current.mainContext.fetch(FetchDescriptor<HealthCheckpoint>()).first?.anchor,
      Data([1, 2, 3]))
    XCTAssertEqual(
      try current.mainContext.fetch(FetchDescriptor<HealthMeasurement>()).first?.id, measurementID)
    XCTAssertEqual(
      try current.mainContext.fetch(FetchDescriptor<DeletedHealthRecord>()).first?.id, deletedID)
  }

  func testExistingHealthDatabaseMigratesWithoutLosingWorkouts() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "runner-migration-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("runs.store")
    let start = Date(timeIntervalSince1970: 1_780_000_000)
    let run = RunData(
      start: start, end: start.addingTimeInterval(1500), duration: 1500, distanceMeters: 5000,
      source: "Synthetic migration fixture")
    try autoreleasepool {
      let previous = try ModelContainer(
        for: PreviousHealthSchema.RecordedRun.self, PreviousHealthSchema.HealthCheckpoint.self,
        PreviousHealthSchema.HealthMeasurement.self,
        configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
      previous.mainContext.insert(try PreviousHealthSchema.RecordedRun(run))
      previous.mainContext.insert(PreviousHealthSchema.HealthCheckpoint(key: "workouts"))
      try previous.mainContext.save()
    }
    let current = try ModelContainer(
      for: RecordedRun.self, HealthCheckpoint.self, HealthMeasurement.self,
      CloudSyncCheckpoint.self, DeletedHealthRecord.self,
      configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
    let saved = try XCTUnwrap(current.mainContext.fetch(FetchDescriptor<RecordedRun>()).first)
    XCTAssertEqual(saved.id, run.id)
    XCTAssertEqual(saved.run, run)
    XCTAssertFalse(saved.routeDeleted)
    XCTAssertEqual(
      try current.mainContext.fetch(FetchDescriptor<HealthCheckpoint>()).first?.key, "workouts")
    XCTAssertTrue(try current.mainContext.fetch(FetchDescriptor<CloudSyncCheckpoint>()).isEmpty)
    XCTAssertTrue(try current.mainContext.fetch(FetchDescriptor<DeletedHealthRecord>()).isEmpty)
  }
}
