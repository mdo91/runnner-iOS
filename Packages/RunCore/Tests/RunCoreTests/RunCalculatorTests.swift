import XCTest

@testable import RunCore

final class RunCalculatorTests: XCTestCase {
  let start = Date(timeIntervalSince1970: 1_700_000_000)
  func makeRun(distance: Double? = 5000, seconds: Double = 1500) -> RunData {
    RunData(
      start: start, end: start.addingTimeInterval(seconds), duration: seconds,
      distanceMeters: distance, source: "Test Watch")
  }
  func testMeasuredPaceAndUnits() {
    let m = RunCalculator.metrics(makeRun())
    XCTAssertEqual(m.averagePaceSecondsPerKm, 300)
    XCTAssertEqual(UnitSystem.metric.pace(m.averagePaceSecondsPerKm), "5:00")
    XCTAssertEqual(UnitSystem.imperial.pace(m.averagePaceSecondsPerKm), "8:03")
    XCTAssertEqual(UnitSystem.imperial.distance(1609.344), "1.00")
    XCTAssertEqual(UnitSystem.duration(3661), "1:01:01")
  }
  func testUnavailableIsNotZero() {
    let m = RunCalculator.metrics(makeRun(distance: nil))
    XCTAssertNil(m.distanceMeters)
    XCTAssertNil(m.averagePaceSecondsPerKm)
    XCTAssertNil(m.averageHeartRate)
    XCTAssertNil(m.elevationGainMeters)
    XCTAssertEqual(m.heartRateCoverage, 0)
    XCTAssertEqual(RunCalculator.metrics(makeRun(distance: 0)).distanceMeters, 0)
    XCTAssertNil(RunCalculator.metrics(makeRun(distance: 0)).averagePaceSecondsPerKm)
    XCTAssertTrue(RunCalculator.splits(makeRun()).isEmpty)
  }
  func testOverlappingPausesMergeAndSparseHeartRateDoesNotFillGaps() {
    let pauses = [
      Pause(start: start.addingTimeInterval(10), end: start.addingTimeInterval(30)),
      Pause(start: start.addingTimeInterval(20), end: start.addingTimeInterval(40)),
    ]
    XCTAssertEqual(
      RunCalculator.activeSeconds(from: start, to: start.addingTimeInterval(60), pauses: pauses), 30
    )
    let hr = RunCalculator.heartRate(
      [TimedValue(start: start, value: 140)], from: start, to: start.addingTimeInterval(120),
      pauses: [])
    XCTAssertEqual(hr.average, 140)
    XCTAssertEqual(hr.coverage, 0.25)
  }
  func testSplitsIncludePauseAndPartialKilometer() {
    var r = makeRun(distance: 2500, seconds: 810)
    r.pauses = [Pause(start: start.addingTimeInterval(300), end: start.addingTimeInterval(360))]
    r.duration = 750
    r.distances = [
      TimedValue(start: start, end: start.addingTimeInterval(300), value: 1000),
      TimedValue(
        start: start.addingTimeInterval(360), end: start.addingTimeInterval(660), value: 1000),
      TimedValue(start: start.addingTimeInterval(660), end: r.end, value: 500),
    ]
    let splits = RunCalculator.splits(r)
    XCTAssertEqual(splits.map(\.movingSeconds), [300, 300, 150])
    XCTAssertEqual(splits.map(\.distanceMeters), [1000, 1000, 500])
    XCTAssertEqual(RunCalculator.metrics(r).averagePaceSecondsPerKm, 300)
  }
  func testGPSGapsInvalidPointsAndPausesBreakPolyline() {
    var r = makeRun(seconds: 120)
    r.route = [0, 5, 40, 45, 50, 55].enumerated().map { i, t in
      RoutePoint(
        timestamp: start.addingTimeInterval(Double(t)), latitude: 41 + Double(i) * 0.00005,
        longitude: 29, horizontalAccuracy: i == 4 ? 100 : 5)
    }
    XCTAssertEqual(RunCalculator.routeSegments(r).map(\.count), [2, 2])
    r.pauses = [Pause(start: start.addingTimeInterval(42), end: start.addingTimeInterval(48))]
    XCTAssertEqual(RunCalculator.routeSegments(r).map(\.count), [2])
  }
  func testNoTargetsMeansNoInventedCoaching() {
    XCTAssertNil(CoachingTargets().cue(heartRate: 180, pace: 300))
    XCTAssertNotNil(CoachingTargets(upperHeartRate: 170).cue(heartRate: 180, pace: nil))
  }
  func testJSONContainsNullsAndNoCoordinatesOrSource() throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    var r = makeRun()
    r.route = [RoutePoint(timestamp: start, latitude: 41, longitude: 29)]
    let payload = try encoder.encode(AnalysisRequest(run: r, history: []))
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: Any])
    let metrics = try XCTUnwrap(object["metrics"] as? [String: Any])
    XCTAssertTrue(metrics["averageHeartRate"] is NSNull)
    let string = String(decoding: payload, as: UTF8.self)
    XCTAssertFalse(string.contains("latitude"))
    XCTAssertFalse(string.contains("Test Watch"))
  }
}
