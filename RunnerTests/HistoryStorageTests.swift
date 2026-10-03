import RunCore
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
      id = run.id;start = run.start;importedAt = run.importedAt
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
    init(id: UUID,kind: String,value: Double,date: Date) { self.id = id;self.kind = kind;self.value = value;self.date = date }
  }
}
@MainActor final class HistoryStorageTests: XCTestCase {
  func testExistingHealthDatabaseMigratesWithoutLosingWorkouts() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("runner-migration-\(UUID().uuidString)",isDirectory:true)
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
    defer { try? FileManager.default.removeItem(at:directory) }
    let url = directory.appendingPathComponent("runs.store")
    let start = Date(timeIntervalSince1970:1_780_000_000)
    let run = RunData(start:start,end:start.addingTimeInterval(1500),duration:1500,distanceMeters:5000,source:"Synthetic migration fixture")
    try autoreleasepool {
      let previous = try ModelContainer(for:PreviousHealthSchema.RecordedRun.self,PreviousHealthSchema.HealthCheckpoint.self,PreviousHealthSchema.HealthMeasurement.self,configurations:ModelConfiguration(url:url,cloudKitDatabase:.none))
      previous.mainContext.insert(try PreviousHealthSchema.RecordedRun(run))
      previous.mainContext.insert(PreviousHealthSchema.HealthCheckpoint(key:"workouts"))
      try previous.mainContext.save()
    }
    let current = try ModelContainer(for:RecordedRun.self,HealthCheckpoint.self,HealthMeasurement.self,CloudSyncCheckpoint.self,DeletedHealthRecord.self,configurations:ModelConfiguration(url:url,cloudKitDatabase:.none))
    let saved = try XCTUnwrap(current.mainContext.fetch(FetchDescriptor<RecordedRun>()).first)
    XCTAssertEqual(saved.id,run.id)
    XCTAssertEqual(saved.run,run)
    XCTAssertFalse(saved.routeDeleted)
    XCTAssertEqual(try current.mainContext.fetch(FetchDescriptor<HealthCheckpoint>()).first?.key,"workouts")
    XCTAssertTrue(try current.mainContext.fetch(FetchDescriptor<CloudSyncCheckpoint>()).isEmpty)
    XCTAssertTrue(try current.mainContext.fetch(FetchDescriptor<DeletedHealthRecord>()).isEmpty)
  }
}
