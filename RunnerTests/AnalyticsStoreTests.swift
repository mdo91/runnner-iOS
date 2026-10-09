import RunCore
import XCTest

private actor ControlledAnalyticsService: RunAnalyticsServicing {
  let started: [XCTestExpectation]
  private var count = 0
  private var pending: [Int: (payloads: [Data], continuation: CheckedContinuation<RunAnalyticsSnapshot, Never>)] = [:]
  init(started: [XCTestExpectation]) { self.started = started }
  func snapshot(payloads: [Data]) async -> RunAnalyticsSnapshot {
    if payloads.isEmpty { return .empty }
    let index = count
    count += 1
    return await withCheckedContinuation { continuation in
      pending[index] = (payloads, continuation)
      started[index].fulfill()
    }
  }
  func resolve(_ index: Int) {
    guard let request = pending.removeValue(forKey: index) else { return }
    let runs = request.payloads.compactMap { try? JSONDecoder().decode(RunData.self, from: $0) }
    request.continuation.resume(returning: RunAnalyticsSnapshot(runs: runs))
  }
  func trainingLoad(runs: [RunData], zones: HeartRateZones) -> TrainingLoad {
    TrainingLoad(runs: runs, zones: zones)
  }
  func series(run: RunData) -> [RunSeriesMetric: RunSeries] { [:] }
}

@MainActor final class AnalyticsStoreTests: XCTestCase {
  private func payload() throws -> Data {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    return try JSONEncoder().encode(
      RunData(start: start, end: start.addingTimeInterval(300), duration: 300,
        distanceMeters: 1000, source: "Test"))
  }
  func testRefreshReadinessMatchesPayloadsBeforeAndDuringRefresh() async throws {
    let started = expectation(description: "Refresh began")
    let service = ControlledAnalyticsService(started: [started])
    let store = AnalyticsStore(service: service)
    await store.refresh(payloads: [])
    XCTAssertTrue(store.isCurrent(payloads: []))
    let revision = store.revision
    let next = try [payload()]
    // A rows update must be rejected even before its refresh task starts.
    XCTAssertFalse(store.isCurrent(payloads: next))
    let refresh = Task { await store.refresh(payloads: next) }
    await fulfillment(of: [started], timeout: 2)
    XCTAssertTrue(store.loading)
    XCTAssertFalse(store.isCurrent(payloads: next))
    XCTAssertFalse(store.isCurrent(payloads: []))
    await service.resolve(0)
    await refresh.value
    XCTAssertTrue(store.isCurrent(payloads: next))
    XCTAssertEqual(store.snapshot.runs.count, 1)
    XCTAssertEqual(store.revision, revision + 1)
  }
  func testOlderCompletionCannotReplaceCurrentRevision() async throws {
    let first = expectation(description: "First refresh began")
    let second = expectation(description: "Second refresh began")
    let service = ControlledAnalyticsService(started: [first, second])
    let store = AnalyticsStore(service: service)
    let older = try [payload()]
    let newer = try [payload()]
    let initial = Task { await store.refresh(payloads: older) }
    await fulfillment(of: [first], timeout: 2)
    let latest = Task { await store.refresh(payloads: newer) }
    await fulfillment(of: [second], timeout: 2)
    await service.resolve(1)
    await latest.value
    await service.resolve(0)
    await initial.value
    XCTAssertTrue(store.isCurrent(payloads: newer))
    XCTAssertFalse(store.isCurrent(payloads: older))
    XCTAssertEqual(store.revision, 1)
  }
}
