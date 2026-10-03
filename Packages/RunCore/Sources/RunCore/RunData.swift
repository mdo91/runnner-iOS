import Foundation

public struct TimedValue: Codable, Sendable, Equatable {
  public var start: Date
  public var end: Date
  public var value: Double
  public init(start: Date, end: Date? = nil, value: Double) {
    self.start = start
    self.end = end ?? start
    self.value = value
  }
}
public struct Pause: Codable, Sendable, Equatable {
  public var start: Date
  public var end: Date
  public init(start: Date, end: Date) {
    self.start = start
    self.end = end
  }
}
public struct RoutePoint: Codable, Sendable, Equatable {
  public var timestamp: Date
  public var latitude: Double
  public var longitude: Double
  public var altitude: Double
  public var horizontalAccuracy: Double
  public var verticalAccuracy: Double
  public var speed: Double?
  public var segment: Int
  public init(
    timestamp: Date, latitude: Double, longitude: Double, altitude: Double = 0,
    horizontalAccuracy: Double = 5, verticalAccuracy: Double = -1, speed: Double? = nil,
    segment: Int = 0
  ) {
    self.timestamp = timestamp
    self.latitude = latitude
    self.longitude = longitude
    self.altitude = altitude
    self.horizontalAccuracy = horizontalAccuracy
    self.verticalAccuracy = verticalAccuracy
    self.speed = speed
    self.segment = segment
  }
}
public struct RunData: Codable, Sendable, Identifiable, Equatable {
  public var id: UUID
  public var start: Date
  public var end: Date
  public var duration: Double
  public var distanceMeters: Double?
  public var activeEnergyKcal: Double?
  public var source: String
  public var sourceBundle: String
  public var indoor: Bool
  public var heartRate: [TimedValue]
  public var distances: [TimedValue]
  public var pauses: [Pause]
  public var route: [RoutePoint]
  public var dynamics: [String: [TimedValue]]
  public var importedAt: Date
  public init(
    id: UUID = UUID(), start: Date, end: Date, duration: Double, distanceMeters: Double?,
    activeEnergyKcal: Double? = nil, source: String, sourceBundle: String = "",
    indoor: Bool = false, heartRate: [TimedValue] = [], distances: [TimedValue] = [],
    pauses: [Pause] = [], route: [RoutePoint] = [], dynamics: [String: [TimedValue]] = [:],
    importedAt: Date = Date()
  ) {
    self.id = id
    self.start = start
    self.end = end
    self.duration = duration
    self.distanceMeters = distanceMeters
    self.activeEnergyKcal = activeEnergyKcal
    self.source = source
    self.sourceBundle = sourceBundle
    self.indoor = indoor
    self.heartRate = heartRate
    self.distances = distances
    self.pauses = pauses
    self.route = route
    self.dynamics = dynamics
    self.importedAt = importedAt
  }
}
public struct Split: Codable, Sendable, Identifiable, Equatable {
  public var index: Int
  public var distanceMeters: Double
  public var movingSeconds: Double
  public var averageHeartRate: Double?
  public var id: Int { index }
  public var pace: Double { movingSeconds / distanceMeters * 1000 }
}
public struct MeasuredMetrics: Codable, Sendable, Equatable {
  public var distanceMeters: Double?
  public var elapsedSeconds: Double
  public var movingSeconds: Double
  public var averagePaceSecondsPerKm: Double?
  public var averageHeartRate: Double?
  public var maxHeartRate: Double?
  public var activeEnergyKcal: Double?
  public var elevationGainMeters: Double?
  public var pacingCoefficientOfVariation: Double?
  public var heartRateCoverage: Double
}
public enum UnitSystem: String, Codable, CaseIterable, Sendable {
  case metric, imperial
  public var distanceUnit: String { self == .metric ? "km" : "mi" }
  public var metersPerUnit: Double { self == .metric ? 1000 : 1609.344 }
  public func distance(_ meters: Double?) -> String {
    meters.map { String(format: "%.2f", $0 / metersPerUnit) } ?? "—"
  }
  public func pace(_ secondsPerKm: Double?) -> String {
    guard let pace = secondsPerKm, pace.isFinite, pace > 0 else { return "—" }
    let value = Int((pace * metersPerUnit / 1000).rounded())
    return String(format: "%d:%02d", value / 60, value % 60)
  }
  public static func duration(_ seconds: Double) -> String {
    let value = max(0, Int(seconds.rounded()))
    return value >= 3600
      ? String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
      : String(format: "%d:%02d", value / 60, value % 60)
  }
}

extension MeasuredMetrics {
  enum CodingKeys: String, CodingKey {
    case distanceMeters, elapsedSeconds, movingSeconds, averagePaceSecondsPerKm, averageHeartRate,
      maxHeartRate, activeEnergyKcal, elevationGainMeters, pacingCoefficientOfVariation,
      heartRateCoverage
  }
  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(distanceMeters, forKey: .distanceMeters)
    try c.encode(elapsedSeconds, forKey: .elapsedSeconds)
    try c.encode(movingSeconds, forKey: .movingSeconds)
    try c.encode(averagePaceSecondsPerKm, forKey: .averagePaceSecondsPerKm)
    try c.encode(averageHeartRate, forKey: .averageHeartRate)
    try c.encode(maxHeartRate, forKey: .maxHeartRate)
    try c.encode(activeEnergyKcal, forKey: .activeEnergyKcal)
    try c.encode(elevationGainMeters, forKey: .elevationGainMeters)
    try c.encode(pacingCoefficientOfVariation, forKey: .pacingCoefficientOfVariation)
    try c.encode(heartRateCoverage, forKey: .heartRateCoverage)
  }
}
extension Split {
  enum CodingKeys: String, CodingKey { case index, distanceMeters, movingSeconds, averageHeartRate }
  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(index, forKey: .index)
    try c.encode(distanceMeters, forKey: .distanceMeters)
    try c.encode(movingSeconds, forKey: .movingSeconds)
    try c.encode(averageHeartRate, forKey: .averageHeartRate)
  }
}
