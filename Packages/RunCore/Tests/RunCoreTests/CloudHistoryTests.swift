import XCTest
@testable import RunCore

final class CloudHistoryTests: XCTestCase {
  let start = Date(timeIntervalSince1970:1_780_000_000)
  func makeRun() -> RunData {
    RunData(start:start,end:start.addingTimeInterval(120),duration:90,distanceMeters:400,source:"Apple Watch",
      heartRate:[TimedValue(start:start,value:140)],
      pauses:[Pause(start:start.addingTimeInterval(30),end:start.addingTimeInterval(60))],
      route:[0,5,65,70].enumerated().map { index,t in RoutePoint(timestamp:start.addingTimeInterval(Double(t)),latitude:41+Double(index)*0.00004,longitude:29,speed:3) },
      dynamics:["HKQuantityTypeIdentifierRunningPower":[TimedValue(start:start,value:200),TimedValue(start:start.addingTimeInterval(40),value:500)]])
  }
  func testMetricsMatchPhoneAndGPSRequiresSeparateConsent() throws {
    let run = makeRun(),privateRun = CloudRun(run,gpsConsent:false),sharedRun = CloudRun(run,gpsConsent:true)
    XCTAssertEqual(privateRun.metrics,RunCalculator.metrics(run))
    XCTAssertEqual(privateRun.splits,RunCalculator.splits(run))
    XCTAssertNil(privateRun.route)
    XCTAssertEqual(sharedRun.route?.count,4)
    XCTAssertEqual(sharedRun.route?.map(\.segment),[0,0,1,1])
    let data = try JSONEncoder().encode(privateRun)
    let raw = try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any])
    XCTAssertTrue(raw["route"] is NSNull)
    XCTAssertTrue(raw["report"] is NSNull)
    XCTAssertFalse(String(decoding:data,as:UTF8.self).contains("latitude"))
  }
  func testSparsePulseAndPausedSamplesRemainMissingInChart() {
    let summary = CloudRun(makeRun(),gpsConsent:false)
    XCTAssertEqual(summary.series.map(\.heartRate),[140,nil,nil,nil])
    XCTAssertEqual(summary.series.map(\.powerWatts),[200,nil,nil,nil])
    XCTAssertTrue(summary.series.allSatisfy { $0.paceSecondsPerKm == nil })
  }
  func testLongRunsKeepBoundedSeriesAndSegmentBreaks() {
    var run = makeRun();run.end = start.addingTimeInterval(604800);run.duration = 604770
    run.route = (0..<6000).map { i in RoutePoint(timestamp:start.addingTimeInterval(Double(i)*5),latitude:41+Double(i)*0.00001,longitude:29,segment:i<3000 ? 0:1) }
    let summary = CloudRun(run,gpsConsent:true)
    XCTAssertLessThanOrEqual(summary.series.count,1500)
    XCTAssertLessThanOrEqual(summary.route?.count ?? 0,3000)
    XCTAssertTrue(summary.route?.contains { $0.segment > 0 } == true)
    XCTAssertEqual(summary.route?.last?.t,29995)
  }
  func testDeletedRouteFlagRequiresGPSConsentAndChartNullsEncode() throws {
    let summary = CloudRun(makeRun(),gpsConsent:false,routeDeleted:true)
    XCTAssertFalse(summary.routeDeleted)
    let raw = try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(summary)) as? [String:Any])
    let series = try XCTUnwrap(raw["series"] as? [[String:Any]])
    XCTAssertTrue(series[0]["strideMeters"] is NSNull)
    XCTAssertTrue(series[1]["heartRate"] is NSNull)
  }
  func testSwiftWireFixtureForBackendContract() throws {
    guard let path = ProcessInfo.processInfo.environment["RUNNER_HISTORY_WIRE_FIXTURE"] else { return }
    let encoder = JSONEncoder();encoder.dateEncodingStrategy = .iso8601;encoder.outputFormatting = .sortedKeys
    try encoder.encode(CloudRun(makeRun(),gpsConsent:true)).write(to:URL(fileURLWithPath:path))
  }
}
