import Foundation
import RunCore
import SwiftData

@Model final class RecordedRun {
  @Attribute(.unique) var id: UUID
  var start: Date
  var importedAt: Date
  @Attribute(.externalStorage) var payload: Data
  var routeDeleted: Bool = false
  var reportData: Data?
  var reportInputHash: String?
  var lastAnalysisAttempt: Date?
  init(_ run: RunData) throws {
    id = run.id
    start = run.start
    importedAt = run.importedAt
    payload = try JSONEncoder().encode(run)
  }
  func update(_ incoming: RunData) throws {
    if let old = run, !RunRevision.hasSameAnalysisData(old, incoming) {
      reportData = nil
      reportInputHash = nil
      lastAnalysisAttempt = nil
    }
    payload = try JSONEncoder().encode(incoming)
    start = incoming.start
    importedAt = incoming.importedAt
  }
  var run: RunData? { try? JSONDecoder().decode(RunData.self, from: payload) }
  var report: AnalysisReport? {
    reportData.flatMap { try? JSONDecoder().decode(AnalysisReport.self, from: $0) }
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
  var measurement: DatedMeasurement { .init(value: value, measuredAt: date) }
}

@Model final class CloudSyncCheckpoint {
  @Attribute(.unique) var key: String
  // `hash` collides with NSObject.hash on SwiftData's Core Data backing object.
  // Keep the renaming identifier so existing checkpoint values migrate in place.
  @Attribute(originalName: "hash") var payloadDigest: String
  init(key: String, payloadDigest: String) { self.key = key; self.payloadDigest = payloadDigest }
}
@Model final class DeletedHealthRecord {
  @Attribute(.unique) var key: String
  var id: UUID
  var kind: String
  init(id: UUID, kind: String) { self.id = id; self.kind = kind; key = "\(kind):\(id.uuidString)" }
}
