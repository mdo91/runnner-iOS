import Foundation

public protocol RunAnalyticsServicing: Sendable {
  func snapshot(payloads: [Data]) async -> RunAnalyticsSnapshot
  func trainingLoad(runs: [RunData], zones: HeartRateZones) async -> TrainingLoad
  func series(run: RunData) async -> [RunSeriesMetric: RunSeries]
}

/// A bounded per-run chart cache; a large history never eagerly allocates every chart.
public actor CachedRunAnalyticsService: RunAnalyticsServicing {
  private var charts: [UUID: (run: RunData, series: [RunSeriesMetric: RunSeries])] = [:]
  private var order: [UUID] = []
  private var decoded: [Data: RunData] = [:]
  private var calculated: [Data: MeasuredMetrics] = [:]
  private var previousPayloads: [Data]?
  private var previousSnapshot = RunAnalyticsSnapshot.empty
  public init() {}
  public func snapshot(payloads: [Data]) -> RunAnalyticsSnapshot {
    if previousPayloads == payloads { return previousSnapshot }
    let decoder = JSONDecoder()
    var next: [Data: RunData] = [:]
    let runs = payloads.compactMap { data -> RunData? in
      let value = decoded[data] ?? (try? decoder.decode(RunData.self, from: data))
      next[data] = value
      return value
    }
    decoded = next
    let revisions = Dictionary(uniqueKeysWithValues: runs.map { ($0.id, $0.importedAt) })
    charts = charts.filter { revisions[$0.key] == $0.value.run.importedAt }
    order = order.filter { charts[$0] != nil }
    var nextMetrics: [Data: MeasuredMetrics] = [:]
    for data in payloads {
      if let run = decoded[data] {
        nextMetrics[data] = calculated[data] ?? RunCalculator.metrics(run)
      }
    }
    calculated = nextMetrics
    let metrics = Dictionary(
      uniqueKeysWithValues: payloads.compactMap { data -> (UUID, MeasuredMetrics)? in
        guard let run = decoded[data], let value = calculated[data] else { return nil }
        return (run.id, value)
      })
    previousPayloads = payloads
    previousSnapshot = RunAnalyticsSnapshot(runs: runs, metrics: metrics)
    return previousSnapshot
  }
  public func trainingLoad(runs: [RunData], zones: HeartRateZones) -> TrainingLoad {
    TrainingLoad(runs: runs, zones: zones)
  }
  public func series(run: RunData) -> [RunSeriesMetric: RunSeries] {
    if let cached = charts[run.id], RunRevision.hasSameAnalysisData(cached.run, run) {
      return cached.series
    }
    let result = Dictionary(
      uniqueKeysWithValues: RunSeriesMetric.allCases.map {
        ($0, RecordedSeries.make(run, metric: $0))
      })
    charts[run.id] = (run, result)
    order.removeAll { $0 == run.id }
    order.append(run.id)
    while order.count > 8 { charts.removeValue(forKey: order.removeFirst()) }
    return result
  }
}
