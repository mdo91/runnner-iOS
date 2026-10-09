import Foundation
import RunCore
import SwiftUI

@MainActor final class AnalyticsStore: ObservableObject {
  @Published private(set) var snapshot = RunAnalyticsSnapshot.empty
  @Published private(set) var loading = true
  @Published private(set) var unreadableCount = 0
  let service: any RunAnalyticsServicing
  private var generation = 0
  init(service: any RunAnalyticsServicing = CachedRunAnalyticsService()) { self.service = service }
  func refresh(payloads: [Data]) async {
    generation += 1
    let current = generation
    let result = await service.snapshot(payloads: payloads)
    guard current == generation else { return }
    snapshot = result
    unreadableCount = payloads.count - result.runs.count
    loading = false
  }
}
