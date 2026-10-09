import Foundation

public enum RunCalculator {
  public static func pauses(_ values: [Pause], from start: Date, to end: Date) -> [Pause] {
    var merged: [Pause] = []
    for pause in values.sorted(by: { $0.start < $1.start }) {
      let p = Pause(start: max(start, pause.start), end: min(end, pause.end))
      guard p.end > p.start else { continue }
      if let last = merged.last, p.start <= last.end {
        merged[merged.count - 1].end = max(last.end, p.end)
      } else {
        merged.append(p)
      }
    }
    return merged
  }
  public static func activeSeconds(from start: Date, to end: Date, pauses: [Pause]) -> Double {
    max(
      0,
      end.timeIntervalSince(start)
        - self.pauses(pauses, from: start, to: end).reduce(0) {
          $0 + $1.end.timeIntervalSince($1.start)
        })
  }
  public static func heartRate(
    _ samples: [TimedValue], from start: Date, to end: Date, pauses: [Pause]
  ) -> (average: Double?, coverage: Double, max: Double?) {
    let valid = samples.filter {
      $0.value.isFinite && (25...250).contains($0.value) && $0.start < end
        && $0.start >= start.addingTimeInterval(-30)
    }.sorted { $0.start < $1.start }
    var weighted = 0.0
    var covered = 0.0
    for (index, sample) in valid.enumerated() {
      // Never fill a sensor gap with an old pulse. A sample represents at most 30 seconds.
      let next = index + 1 < valid.count ? valid[index + 1].start : end
      let until = min(end, next, sample.start.addingTimeInterval(30))
      let seconds = activeSeconds(from: max(start, sample.start), to: until, pauses: pauses)
      weighted += sample.value * seconds
      covered += seconds
    }
    let active = activeSeconds(from: start, to: end, pauses: pauses)
    return (
      covered > 0 ? weighted / covered : nil, active > 0 ? min(1, covered / active) : 0,
      valid.filter { sample in
        sample.start >= start
          && !pauses.contains(where: { $0.start <= sample.start && sample.start < $0.end })
      }.map(\.value).max()
    )
  }
  public static func metrics(_ run: RunData) -> MeasuredMetrics {
    let elapsed = max(0, run.end.timeIntervalSince(run.start))
    let moving = min(elapsed, max(0, run.duration))
    let hr = heartRate(run.heartRate, from: run.start, to: run.end, pauses: run.pauses)
    let splits = splits(run).filter { $0.distanceMeters >= 999 }
    let paces = splits.map(\.pace)
    let mean = paces.isEmpty ? 0 : paces.reduce(0, +) / Double(paces.count)
    let cv =
      paces.count >= 3 && mean > 0
      ? sqrt(paces.reduce(0) { $0 + pow($1 - mean, 2) } / Double(paces.count)) / mean : nil
    var gain = 0.0
    var validAltitudePairs = 0
    for segment in routeSegments(run) {
      var previous: Double?
      for point in segment {
        guard point.altitude.isFinite, point.verticalAccuracy.isFinite, point.verticalAccuracy >= 0,
          point.verticalAccuracy <= 10
        else {
          previous = nil
          continue
        }
        if previous != nil { validAltitudePairs += 1 }
        if let last = previous, abs(point.altitude - last) >= 3 {
          gain += max(0, point.altitude - last)
          previous = point.altitude
        }
        if previous == nil { previous = point.altitude }
      }
    }
    let distance = run.distanceMeters.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
    return MeasuredMetrics(
      distanceMeters: distance, elapsedSeconds: elapsed, movingSeconds: moving,
      averagePaceSecondsPerKm: distance.flatMap { $0 > 0 && moving > 0 ? moving / $0 * 1000 : nil },
      averageHeartRate: hr.average,
      maxHeartRate: hr.max,
      activeEnergyKcal: run.activeEnergyKcal.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil },
      elevationGainMeters: validAltitudePairs > 0 ? gain : nil,
      pacingCoefficientOfVariation: cv, heartRateCoverage: hr.coverage)
  }
  public static func splits(_ run: RunData, length: Double = 1000) -> [Split] {
    guard length > 0, let total = run.distanceMeters, total > 0 else { return [] }
    let samples = run.distances.filter {
      $0.value.isFinite && $0.value > 0 && $0.end > $0.start && $0.start >= run.start
        && $0.end <= run.end
    }.sorted { $0.start < $1.start }
    let sum = samples.reduce(0) { $0 + $1.value }
    // Do not fabricate splits by dividing the workout total when distance samples are missing.
    guard !samples.isEmpty, abs(sum - total) / total <= 0.05 else { return [] }
    var result: [Split] = []
    var cumulative = 0.0
    var boundary = length
    var splitStart = run.start
    for sample in samples {
      let endDistance = cumulative + sample.value
      while boundary <= endDistance {
        let fraction = (boundary - cumulative) / sample.value
        let time = sample.start.addingTimeInterval(
          sample.end.timeIntervalSince(sample.start) * fraction)
        let seconds = activeSeconds(from: splitStart, to: time, pauses: run.pauses)
        let hr = heartRate(run.heartRate, from: splitStart, to: time, pauses: run.pauses)
        result.append(
          Split(
            index: result.count + 1, distanceMeters: length, movingSeconds: seconds,
            averageHeartRate: hr.average))
        splitStart = time
        boundary += length
      }
      cumulative = endDistance
    }
    let remainder = cumulative - Double(result.count) * length
    if remainder > 1 {
      result.append(
        Split(
          index: result.count + 1, distanceMeters: remainder,
          movingSeconds: activeSeconds(from: splitStart, to: run.end, pauses: run.pauses),
          averageHeartRate: heartRate(
            run.heartRate, from: splitStart, to: run.end, pauses: run.pauses
          ).average))
    }
    return result
  }
  public static func distance(_ a: RoutePoint, _ b: RoutePoint) -> Double {
    let rad = Double.pi / 180
    let lat1 = a.latitude * rad
    let lat2 = b.latitude * rad
    let h =
      pow(sin((lat2 - lat1) / 2), 2) + cos(lat1) * cos(lat2)
      * pow(sin((b.longitude - a.longitude) * rad / 2), 2)
    return 6_371_000 * 2 * atan2(sqrt(max(0, h)), sqrt(max(0, 1 - h)))
  }
  public static func routeSegments(_ run: RunData) -> [[RoutePoint]] {
    var segments: [[RoutePoint]] = []
    var current: [RoutePoint] = []
    for point in run.route.sorted(by: { $0.timestamp < $1.timestamp }) {
      let valid =
        point.latitude.isFinite && point.longitude.isFinite && abs(point.latitude) <= 90
        && abs(point.longitude) <= 180 && point.horizontalAccuracy >= 0
        && point.horizontalAccuracy <= 35 && point.timestamp >= run.start
        && point.timestamp <= run.end
      guard valid,
        !run.pauses.contains(where: { point.timestamp >= $0.start && point.timestamp < $0.end })
      else {
        if !current.isEmpty {
          segments.append(current)
          current = []
        }
        continue
      }
      if let previous = current.last {
        let dt = point.timestamp.timeIntervalSince(previous.timestamp)
        let crossedPause = run.pauses.contains {
          $0.start < point.timestamp && $0.end > previous.timestamp
        }
        if dt <= 0 { continue }
        if dt > 20 || point.segment != previous.segment || crossedPause
          || distance(previous, point) / dt > 12
        {
          segments.append(current)
          current = []
        }
      }
      current.append(point)
    }
    if !current.isEmpty { segments.append(current) }
    return segments.filter { $0.count >= 2 }
  }
}
