import Foundation

/// A bounded chart representation for history sync. Raw HealthKit samples never leave the phone.
public struct CloudSeriesPoint: Codable, Sendable {
  public var t: Double
  public var heartRate, paceSecondsPerKm, powerWatts, strideMeters,
    groundContactMilliseconds, verticalOscillationMeters: Double?
  enum CodingKeys: String, CodingKey {
    case t, heartRate, paceSecondsPerKm, powerWatts, strideMeters,
      groundContactMilliseconds, verticalOscillationMeters
  }
  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(t, forKey: .t)
    try c.encode(heartRate, forKey: .heartRate)
    try c.encode(paceSecondsPerKm, forKey: .paceSecondsPerKm)
    try c.encode(powerWatts, forKey: .powerWatts)
    try c.encode(strideMeters, forKey: .strideMeters)
    try c.encode(groundContactMilliseconds, forKey: .groundContactMilliseconds)
    try c.encode(verticalOscillationMeters, forKey: .verticalOscillationMeters)
  }
}
public struct CloudRoutePoint: Codable, Sendable {
  public var t, latitude, longitude, altitude: Double
  public var segment: Int
  public var paceSecondsPerKm, heartRate: Double?
  enum CodingKeys: String, CodingKey { case t, latitude, longitude, altitude, segment, paceSecondsPerKm, heartRate }
  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(t, forKey: .t)
    try c.encode(latitude, forKey: .latitude)
    try c.encode(longitude, forKey: .longitude)
    try c.encode(altitude, forKey: .altitude)
    try c.encode(segment, forKey: .segment)
    try c.encode(paceSecondsPerKm, forKey: .paceSecondsPerKm)
    try c.encode(heartRate, forKey: .heartRate)
  }
}
public struct CloudRun: Encodable, Sendable {
  public var id: UUID
  public var start, end: Date
  public var source: String
  public var indoor: Bool
  public var metrics: MeasuredMetrics
  public var splits: [Split]
  public var series: [CloudSeriesPoint]
  public var route: [CloudRoutePoint]?
  public var report: AnalysisReport?
  public var routeDeleted: Bool
  public init(_ run: RunData, gpsConsent: Bool, report: AnalysisReport? = nil, routeDeleted: Bool = false) {
    id = run.id; start = run.start; end = run.end
    source = String(run.source.prefix(100)); indoor = run.indoor
    metrics = RunCalculator.metrics(run); splits = Array(RunCalculator.splits(run).prefix(500))
    self.report = report?.metrics == metrics ? report : nil
    self.routeDeleted = routeDeleted && gpsConsent
    let elapsed = max(0, run.end.timeIntervalSince(run.start))
    let bin = max(30, ceil(elapsed / 1500))
    let count = min(1500, Int(ceil(elapsed / bin)))
    func mean(_ values: [TimedValue], from: Date, to: Date, upper: Double) -> Double? {
      let eligible = values.filter { sample in sample.start >= from && sample.start < to && sample.value.isFinite && sample.value >= 0 && sample.value <= upper && !run.pauses.contains(where: { sample.start >= $0.start && sample.start < $0.end }) }
      return eligible.isEmpty ? nil : eligible.reduce(0) { $0 + $1.value } / Double(eligible.count)
    }
    series = (0..<count).map { index in
      let from = run.start.addingTimeInterval(Double(index) * bin)
      let to = min(run.end, from.addingTimeInterval(bin))
      let speed = mean(run.dynamics["HKQuantityTypeIdentifierRunningSpeed"] ?? [], from: from, to: to, upper: 12)
      let hr = RunCalculator.heartRate(run.heartRate, from: from, to: to, pauses: run.pauses).average
      return CloudSeriesPoint(t: min(elapsed, Double(index) * bin + to.timeIntervalSince(from)/2),
        heartRate: hr, paceSecondsPerKm: speed.flatMap { $0 > 0 && 1000/$0 <= 7200 ? 1000/$0 : nil },
        powerWatts: mean(run.dynamics["HKQuantityTypeIdentifierRunningPower"] ?? [], from: from, to: to, upper: 3000),
        strideMeters: mean(run.dynamics["HKQuantityTypeIdentifierRunningStrideLength"] ?? [], from: from, to: to, upper: 5),
        groundContactMilliseconds: mean(run.dynamics["HKQuantityTypeIdentifierRunningGroundContactTime"] ?? [], from: from, to: to, upper: 2).map { $0 * 1000 },
        verticalOscillationMeters: mean(run.dynamics["HKQuantityTypeIdentifierRunningVerticalOscillation"] ?? [], from: from, to: to, upper: 1))
    }
    route = nil
    if gpsConsent {
      let segments = RunCalculator.routeSegments(run).filter { $0.allSatisfy { abs($0.latitude) <= 85 && $0.altitude.isFinite && (-1000...10000).contains($0.altitude) } }
      let total = segments.reduce(0) { $0 + $1.count }
      let step = max(1, Int(ceil(Double(total) / 2500)))
      var points: [CloudRoutePoint] = []
      for (segment, values) in segments.prefix(250).enumerated() {
        for index in values.indices where index % step == 0 || index == values.count-1 {
          let p = values[index], t = p.timestamp.timeIntervalSince(run.start)
          let speed = p.speed.flatMap { $0 > 0 && $0 <= 12 && 1000/$0 <= 7200 ? 1000/$0 : nil }
          let hr = RunCalculator.heartRate(run.heartRate, from: p.timestamp, to: min(run.end,p.timestamp.addingTimeInterval(1)), pauses: run.pauses).average
          points.append(CloudRoutePoint(t:t,latitude:p.latitude,longitude:p.longitude,altitude:p.altitude,segment:segment,paceSecondsPerKm:speed,heartRate:hr))
        }
      }
      route = Array(points.prefix(3000))
    }
  }
  enum CodingKeys: String, CodingKey { case id, start, end, source, indoor, metrics, splits, series, route, report, routeDeleted }
  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(id, forKey: .id); try c.encode(start, forKey: .start); try c.encode(end, forKey: .end)
    try c.encode(source, forKey: .source); try c.encode(indoor, forKey: .indoor)
    try c.encode(metrics, forKey: .metrics); try c.encode(splits, forKey: .splits)
    try c.encode(series, forKey: .series); try c.encode(route, forKey: .route)
    try c.encode(report, forKey: .report); try c.encode(routeDeleted, forKey: .routeDeleted)
  }
}
public struct CloudMeasurement: Encodable, Sendable {
  public var id: UUID
  public var kind: String
  public var value: Double
  public var measuredAt: Date
  public init(id: UUID, kind: String, value: Double, measuredAt: Date) {
    self.id = id; self.kind = kind; self.value = value; self.measuredAt = measuredAt
  }
}
