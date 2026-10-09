import Foundation
import RunCore
import SwiftUI

@MainActor final class AnalyticsStore: ObservableObject {
  @Published private(set) var snapshot = RunAnalyticsSnapshot.empty
  @Published private(set) var loading = true
  @Published private(set) var unreadableCount = 0
  @Published private(set) var revision = 0
  let service: any RunAnalyticsServicing
  private var generation = 0
  private var readyPayloads: [Data]?
  init(service: any RunAnalyticsServicing = CachedRunAnalyticsService()) { self.service = service }
  func isCurrent(payloads: [Data]) -> Bool {
    !loading && readyPayloads == payloads
  }
  func refresh(payloads: [Data]) async {
    generation += 1
    let current = generation
    loading = true
    let result = await service.snapshot(payloads: payloads)
    guard current == generation, !Task.isCancelled else { return }
    snapshot = result
    unreadableCount = payloads.count - result.runs.count
    readyPayloads = payloads
    loading = false
    revision += 1
  }
}
