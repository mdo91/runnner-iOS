import ImageIO
import RunCore
import SwiftUI
import UniformTypeIdentifiers
import XCTest

@MainActor final class RunPhotoTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 1_700_000_000)
  private func makeRun(distance: Double? = 5010, duration: Double = 2082) -> RunData {
    RunData(start: start, end: start.addingTimeInterval(duration + 90), duration: duration,
      distanceMeters: distance, source: "Photo test",
      pauses: [Pause(start: start.addingTimeInterval(60), end: start.addingTimeInterval(150))])
  }
  private func image(_ size: CGSize = CGSize(width: 900, height: 1200)) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    return UIGraphicsImageRenderer(size: size, format: format).image { context in
      UIColor.red.setFill(); context.fill(CGRect(origin: .zero, size: size))
      UIColor.blue.setFill()
      context.fill(CGRect(x: 0, y: size.height / 2, width: size.width, height: size.height / 2))
    }
  }
  private func gps(_ lat: Double, _ lon: Double, _ seconds: Double, accuracy: Double = 5) -> RoutePoint {
    RoutePoint(timestamp: start.addingTimeInterval(seconds), latitude: lat,
      longitude: lon, horizontalAccuracy: accuracy)
  }
  func testMetricsUseMovingTimeAndUnitPreferences() {
    let stats = RunPhotoStats(run: makeRun(), units: .metric)
    XCTAssertEqual(stats.distance, "5.01 km")
    XCTAssertEqual(stats.pace, "6:56/km")
    XCTAssertEqual(stats.time, "34m 42s")
    let imperial = RunPhotoStats(run: makeRun(distance: 1609.344, duration: 600), units: .imperial)
    XCTAssertEqual(imperial.distance, "1.00 mi")
    XCTAssertEqual(imperial.pace, "10:00/mi")
    XCTAssertEqual(RunPhotoStats(run: makeRun(distance: nil), units: .metric).distance, "—")
    XCTAssertEqual(RunPhotoStats(run: makeRun(distance: 0), units: .metric).pace, "—")
    XCTAssertEqual(RunPhotoStats.duration(3842), "1h 04m 02s")
    XCTAssertEqual(RunPhotoStats.duration(59.8), "1m 00s")
    XCTAssertEqual(RunPhotoStats.duration(.nan), "—")
  }
  func testProjectionPreservesGapsAndFiltersInvalidPoints() {
    var input = makeRun()
    input.route = [gps(41, 29, 0), gps(41.0001, 29, 5), gps(41.0002, 29, 10, accuracy: 100),
      gps(41.0003, 29, 15), gps(41.0004, 29, 20),
      gps(41.0005, 29, 70), gps(41.0006, 29, 80)]
    let route = RunPhotoRoute(run: input)
    XCTAssertEqual(route.segments.map(\.count), [2, 2])
    XCTAssertGreaterThan(route.segments[0][0].y, route.segments[0][1].y)
    XCTAssertEqual(route.segments[0][0].x, 0.5, accuracy: 0.0001)
    var moves = 0
    route.path.applyWithBlock { if $0.pointee.type == .moveToPoint { moves += 1 } }
    XCTAssertEqual(moves, 2, "Recording gaps must start new subpaths")
  }
  func testProjectionHandlesDatelineDuplicateAndDegenerateCoordinates() {
    var input = makeRun()
    input.pauses = []
    input.route = [gps(0, 179.9999, 0), gps(0, 179.9999, 5), gps(0, -179.9999, 10)]
    let route = RunPhotoRoute(run: input)
    XCTAssertEqual(route.segments.map(\.count), [2])
    XCTAssertLessThan(route.segments[0][0].x, route.segments[0][1].x)
    XCTAssertEqual(route.segments[0][0].y, 0.5, accuracy: 0.0001)
    XCTAssertEqual(route.segments[0][1].x - route.segments[0][0].x, 0.9, accuracy: 0.0001)
    input.route = [gps(41, 29, 0), gps(41, 29, 5)]
    XCTAssertTrue(RunPhotoRoute(run: input).isEmpty)
    input.route = [gps(.nan, 29, 0), gps(41, 29, 5)]
    XCTAssertTrue(RunPhotoRoute(run: input).isEmpty)
  }
  func testOverlayBoundsAndFormatChanges() {
    var composition = RunPhotoComposition()
    composition.image = image(CGSize(width: 2400, height: 1))
    composition.resetLayout()
    for format in RunPhotoFormat.allCases {
      composition.format = format
      composition.stats = RunPhotoTransform(center: CGPoint(x: -5, y: 8), scale: 100)
      composition.constrainOverlays()
      let canvas = composition.canvasSize
      let value = composition.stats
      let half = CGSize(width: 260 * value.scale / 2, height: 264 * value.scale / 2)
      XCTAssertGreaterThanOrEqual(value.center.x * canvas.width - half.width, 0)
      XCTAssertLessThanOrEqual(value.center.y * canvas.height + half.height, canvas.height)
      XCTAssertGreaterThan(value.scale, 0)
    }
    composition.format = .story
    composition.stats = RunPhotoTransform(center: CGPoint(x: 0.4, y: 0.4), scale: 0.4)
    let before = composition.stats
    composition.format = .square
    composition.constrainOverlays()
    XCTAssertEqual(before, composition.stats)
  }
  func testCropAlwaysCoversCanvasAndPanReachesEdges() {
    let canvas = CGSize(width: 360, height: 640)
    let photo = CGSize(width: 2000, height: 1000)
    for zoom: CGFloat in [1, 2, 4] {
      for offset: CGFloat in [-10, -1, 0, 1, 10] {
        let crop = RunPhotoCrop(zoom: zoom, offset: CGPoint(x: offset, y: offset))
        let frame = crop.imageFrame(image: photo, canvas: canvas)
        XCTAssertLessThanOrEqual(frame.minX, 0)
        XCTAssertLessThanOrEqual(frame.minY, 0)
        XCTAssertGreaterThanOrEqual(frame.maxX, canvas.width)
        XCTAssertGreaterThanOrEqual(frame.maxY, canvas.height)
      }
    }
    XCTAssertEqual(RunPhotoCrop(offset: CGPoint(x: 1, y: 0)).imageFrame(image: photo, canvas: canvas).minX, 0)
  }
  func testExportDimensionsColorMetadataAndOrientation() throws {
    var composition = RunPhotoComposition()
    composition.image = image()
    composition.resetLayout()
    let stats = RunPhotoStats(run: makeRun(), units: .metric)
    let route = RunPhotoRoute(run: makeRun())
    for format in RunPhotoFormat.allCases {
      composition.format = format
      composition.constrainOverlays()
      let data = try RunPhotoIO.render(composition, stats: stats, route: route)
      let attachment = XCTAttachment(data: data, uniformTypeIdentifier: UTType.jpeg.identifier)
      attachment.name = "run-photo-\(format.rawValue).jpg"
      attachment.lifetime = .keepAlways
      add(attachment)
      let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
      let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
      XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, Int(composition.outputSize.width))
      XCTAssertEqual(properties[kCGImagePropertyPixelHeight] as? Int, Int(composition.outputSize.height))
      XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
      let cgImage = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
      let pixels = rgba(cgImage)
      let x = cgImage.width / 2
      let top = (cgImage.width * (cgImage.height / 10) + x) * 4
      let bottom = (cgImage.width * (cgImage.height * 9 / 10) + cgImage.width * 9 / 10) * 4
      XCTAssertGreaterThan(pixels[top], 200, "Top stays red")
      XCTAssertGreaterThan(pixels[bottom + 2], 200, "Bottom stays blue")
      let yellow = stride(from: 0, to: pixels.count, by: 4).filter {
        pixels[$0] > 160 && pixels[$0] < 245 && pixels[$0 + 1] > 230 && pixels[$0 + 2] < 70
      }.count
      XCTAssertGreaterThan(yellow, 100, "Runner wordmark uses sporty yellow")
    }
  }
  func testDecodeNormalizesOrientationAndDownsamples() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).jpg")
    defer { try? FileManager.default.removeItem(at: url) }
    let cg = try XCTUnwrap(image(CGSize(width: 5000, height: 1000)).cgImage)
    let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, cg, [kCGImagePropertyOrientation: 6] as CFDictionary)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    let decoded = try RunPhotoIO.decode(url)
    XCTAssertEqual(decoded.imageOrientation, .up)
    XCTAssertLessThanOrEqual(max(decoded.size.width, decoded.size.height), 4096)
    XCTAssertGreaterThan(decoded.size.height, decoded.size.width)
    XCTAssertEqual(decoded.size.height / decoded.size.width, 5, accuracy: 0.01)
  }
  func testExportIgnoresSelectionAndIncludesRouteOnlyWhenEnabled() throws {
    var input = makeRun()
    input.route = [gps(41, 29, 0), gps(41.0001, 29.0001, 5), gps(41.0002, 29, 10)]
    let route = RunPhotoRoute(run: input)
    let stats = RunPhotoStats(run: input, units: .metric)
    var composition = RunPhotoComposition()
    composition.image = image()
    composition.resetLayout()
    let plain = try RunPhotoIO.render(composition, stats: stats, route: route)
    composition.selection = .photo
    XCTAssertEqual(plain, try RunPhotoIO.render(composition, stats: stats, route: route))
    composition.showsRoute = true
    let withRoute = try RunPhotoIO.render(composition, stats: stats, route: route)
    XCTAssertNotEqual(plain, withRoute)
    composition.selection = .route
    XCTAssertEqual(withRoute, try RunPhotoIO.render(composition, stats: stats, route: route))
    let attachment = XCTAttachment(data: withRoute, uniformTypeIdentifier: UTType.jpeg.identifier)
    attachment.name = "run-photo-route.jpg"
    attachment.lifetime = .keepAlways
    add(attachment)
  }
  func testShareFileLivesUntilCleanupAndUnreadableInputFails() throws {
    let data = Data([1, 2, 3])
    let url = try RunPhotoIO.shareFile(data)
    XCTAssertEqual(try Data(contentsOf: url), data)
    XCTAssertThrowsError(try RunPhotoIO.decode(url))
    RunPhotoIO.removeShareFile(url)
    XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
  }
  private func rgba(_ image: CGImage) -> [UInt8] {
    var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
    pixels.withUnsafeMutableBytes { buffer in
      let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
        bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
      context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    return pixels
  }
}
