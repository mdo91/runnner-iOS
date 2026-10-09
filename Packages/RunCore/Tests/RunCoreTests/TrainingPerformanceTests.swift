import XCTest

@testable import RunCore

final class TrainingPerformanceTests: XCTestCase {
  let start = Date(timeIntervalSince1970: 1_700_000_000)
  func fixture() -> RunData {
    var run = RunData(
      start: start, end: start.addingTimeInterval(300), duration: 300, distanceMeters: 1000,
      source: "Test")
    run.distances = (0..<20).map { i in
      TimedValue(
        start: start.addingTimeInterval(Double(i) * 15),
        end: start.addingTimeInterval(Double(i + 1) * 15), value: 50)
    }
    return run
  }
  func testZonesBoundariesBelowAndAboveMaximumAndPauses() {
    let zones = HeartRateZones(maximum: 200)
    XCTAssertEqual(zones.boundaries, [100, 120, 140, 160, 180])
    XCTAssertTrue(zones.isValid)
    var invalid = zones
    invalid.boundaries[2] = 110
    XCTAssertFalse(invalid.isValid)
    var run = fixture()
    run.heartRate = [90, 100, 120, 140, 160, 180, 201].enumerated().map { i, bpm in
      TimedValue(start: start.addingTimeInterval(Double(i) * 30), value: Double(bpm))
    }
    run.pauses = [Pause(start: start.addingTimeInterval(30), end: start.addingTimeInterval(45))]
    let distribution = ZoneDistribution.make(run: run, zones: zones)!
    XCTAssertEqual(distribution.seconds, [30, 15, 30, 30, 30, 60])
    XCTAssertEqual(distribution.aboveMaximumSeconds, 30)
    XCTAssertEqual(distribution.effort, 9.75, accuracy: 0.001)
    XCTAssertEqual(distribution.coverage, 195 / 285, accuracy: 0.001)
  }
  func testInvalidHeartRateEndsCoverageWithoutBecomingMeasuredZero() {
    var run = fixture()
    run.end = start.addingTimeInterval(60)
    run.duration = 60
    run.heartRate = [
      TimedValue(start: start, value: 150),
      TimedValue(start: start.addingTimeInterval(10), value: 0),
      TimedValue(start: start.addingTimeInterval(30), value: 150),
    ]
    let zones = HeartRateZones(maximum: 200)
    let distribution = ZoneDistribution.make(run: run, zones: zones)!
    XCTAssertEqual(distribution.seconds[3], 40)
    XCTAssertEqual(distribution.seconds[0], 0)
    XCTAssertEqual(distribution.coverage, 2.0 / 3, accuracy: 0.001)
    XCTAssertNil(
      TrainingLoad(runs: [run], zones: zones).completeTotal(
        in: DateInterval(start: start, end: run.end), runs: [run]))
  }
  func testLoadRequiresEveryRunToMeetCoverageThreshold() {
    var full = fixture()
    full.heartRate = (0..<10).map {
      TimedValue(start: start.addingTimeInterval(Double($0) * 30), value: 150)
    }
    var missing = fixture()
    missing.id = UUID()
    let interval = DateInterval(start: start, end: full.end)
    let load = TrainingLoad(runs: [full, missing], zones: HeartRateZones(maximum: 200))
    XCTAssertEqual(load.completeTotal(in: interval, runs: [full]), 15)
    XCTAssertNil(load.completeTotal(in: interval, runs: [full, missing]))
    XCTAssertEqual(load.bucket(in: interval, runs: [full, missing]).incompleteCount, 1)
    full.heartRate.removeLast(2)
    XCTAssertEqual(
      TrainingLoad(runs: [full], zones: HeartRateZones(maximum: 200)).completeTotal(
        in: interval, runs: [full]), 12)
  }
  func testBestEffortsInterpolateAndIncludeInternalPause() {
    var run = fixture()
    let efforts = BestEfforts.make(run: run)
    XCTAssertEqual(efforts.first { $0.distance == .m400 }!.seconds, 120, accuracy: 0.001)
    XCTAssertEqual(efforts.first { $0.distance == .km1 }!.seconds, 300, accuracy: 0.001)
    // Shift the second half by an explicitly recorded pause.
    for i in 10..<run.distances.count {
      run.distances[i].start.addTimeInterval(90)
      run.distances[i].end.addTimeInterval(90)
    }
    run.end.addTimeInterval(90)
    run.pauses = [Pause(start: start.addingTimeInterval(150), end: start.addingTimeInterval(240))]
    XCTAssertEqual(BestEfforts.make(run: run).first { $0.distance == .km1 }!.seconds, 390)
    XCTAssertEqual(BestEfforts.make(run: run).first { $0.distance == .m400 }!.seconds, 120)
    run.pauses = []
    XCTAssertNil(BestEfforts.make(run: run).first { $0.distance == .km1 })
  }
  func testEffortExclusionReRanksWithoutDeletingWorkoutsAndAnnualSelection() {
    let first = fixture()
    var second = fixture()
    second.id = UUID()
    second.end.addTimeInterval(30)
    for i in second.distances.indices {
      second.distances[i].start = start.addingTimeInterval(Double(i) * 16.5)
      second.distances[i].end = start.addingTimeInterval(Double(i + 1) * 16.5)
    }
    let efforts = BestEfforts.make(run: first) + BestEfforts.make(run: second)
    let ranked = BestEfforts.ranked(efforts, distance: .km1, excluded: [])
    XCTAssertEqual(ranked.first?.runID, first.id)
    XCTAssertEqual(
      BestEfforts.ranked(efforts, distance: .km1, excluded: [ranked[0].id]).first?.runID, second.id)
    XCTAssertTrue(BestEfforts.ranked(efforts, distance: .km1, excluded: [], year: 1990).isEmpty)
  }
  func testBestEffortSearchIncludesPausesInsideDistanceSamples() throws {
    var run = RunData(
      start: start, end: start.addingTimeInterval(380), duration: 290, distanceMeters: 1000,
      source: "Test")
    var cursor = 0.0
    for index in 0..<10 {
      let seconds = index == 4 ? 110.0 : 30.0
      run.distances.append(
        TimedValue(
          start: start.addingTimeInterval(cursor),
          end: start.addingTimeInterval(cursor + seconds), value: 100))
      cursor += seconds
    }
    run.pauses = [Pause(start: start.addingTimeInterval(130), end: start.addingTimeInterval(220))]
    let effort = try XCTUnwrap(BestEfforts.make(run: run).first { $0.distance == .m400 })
    XCTAssertEqual(effort.seconds, 115, accuracy: 0.001)
    XCTAssertTrue(effort.end <= run.pauses[0].start || effort.start >= run.pauses[0].end)
    XCTAssertEqual(
      BestEfforts.make(run: run).first { $0.distance == .km1 }?.seconds, 380)
  }
  func testGoalIncludesPreexistingRunsAndPreferencesRoundTrip() throws {
    let run = fixture()
    let goal = TrainingGoal(metric: .distance, period: .month, target: 10000)
    XCTAssertEqual(goal.progress(in: ActivityStatistics(runs: [run], now: run.end)), 1000)
    var preferences = AnalyticsPreferences()
    preferences.goals = [goal]
    preferences.zones = HeartRateZones(maximum: 190)
    preferences.excludedEfforts = ["effort"]
    XCTAssertEqual(
      try JSONDecoder().decode(AnalyticsPreferences.self, from: JSONEncoder().encode(preferences)),
      preferences)
  }
  func testSmallLoopsRejectOppositeDirectionDespiteAllPointsBeingClose() {
    func loop(clockwise: Bool, phase: Double = 0) -> RunData {
      var run = fixture()
      run.id = UUID()
      run.distanceMeters = 2 * .pi * 20
      run.route = (0...100).map { i in
        let angle = phase + (clockwise ? 1.0 : -1.0) * Double(i) / 100 * 2 * .pi
        return RoutePoint(
          timestamp: start.addingTimeInterval(Double(i) * 3),
          latitude: 41 + 20 / 111195 * cos(angle),
          longitude: 29 + 20 / (111195 * cos(41 * .pi / 180)) * sin(angle),
          horizontalAccuracy: 5, verticalAccuracy: 5)
      }
      return run
    }
    let first = loop(clockwise: true)
    let second = loop(clockwise: true, phase: .pi / 2)
    let opposite = loop(clockwise: false)
    let matches = RepeatedRoutes.match(runs: [first, second, opposite])
    XCTAssertEqual(matches.count, 2)
    XCTAssertEqual(matches.first { $0.runID == first.id }?.relatedRunIDs, [second.id])
  }
  func testRepeatedRouteRejectsOppositeDirectionAndFarRoutes() {
    func route(reversed: Bool = false, offset: Double = 0) -> RunData {
      var run = fixture()
      run.route = (0...100).map { i in
        let step = reversed ? 100 - i : i
        return RoutePoint(
          timestamp: start.addingTimeInterval(Double(i) * 3),
          latitude: 41 + Double(step) * 0.00009 + offset, longitude: 29, horizontalAccuracy: 5,
          verticalAccuracy: 5)
      }
      return run
    }
    let first = route()
    var second = route()
    second.id = UUID()
    var reverse = route(reversed: true)
    reverse.id = UUID()
    var far = route(offset: 0.002)
    far.id = UUID()
    var indoor = second
    indoor.id = UUID()
    indoor.indoor = true
    let matches = RepeatedRoutes.match(runs: [first, second, reverse, far, indoor])
    XCTAssertEqual(matches.count, 2)
    XCTAssertEqual(matches.first { $0.runID == first.id }?.relatedRunIDs, [second.id])
  }
}
