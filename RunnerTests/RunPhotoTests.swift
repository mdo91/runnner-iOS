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
      let half = CGSize(width: composition.statsSize.width * value.scale / 2,
        height: composition.statsSize.height * value.scale / 2)
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

  func testEveryRouteColorExportsExactPixelsAndPreservesPlacement() throws {
    var run = makeRun()
    run.pauses = []
    run.route = [gps(0, 29, 0), gps(0, 29.0001, 5), gps(0, 29.0002, 10)]
    let route = RunPhotoRoute(run: run)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let background = UIGraphicsImageRenderer(size: CGSize(width: 1080, height: 1080), format: format)
      .image { context in
        UIColor(white: 0.5, alpha: 1).setFill()
        context.fill(CGRect(x: 0, y: 0, width: 1080, height: 1080))
      }
    var composition = RunPhotoComposition()
    XCTAssertEqual(composition.routeColor, .white)
    XCTAssertEqual(RunPhotoRouteColor.runnerYellow.rgb, 0xD7FF00)
    composition.image = background
    composition.resetLayout()
    composition.showsRoute = true
    composition.route = RunPhotoTransform(center: CGPoint(x: 0.5, y: 0.25), scale: 1)
    let routeTransform = composition.route, statsTransform = composition.stats
    for color in RunPhotoRouteColor.allCases {
      composition.routeColor = color
      let data = try RunPhotoIO.render(composition, stats: RunPhotoStats(run: run, units: .metric), route: route)
      let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
      let cg = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
      let pixels = rgba(cg)
      let index = (270 * cg.width + 540) * 4
      for (channel, expected) in [Int((color.rgb >> 16) & 255), Int((color.rgb >> 8) & 255),
        Int(color.rgb & 255)].enumerated() {
        XCTAssertEqual(Int(pixels[index + channel]), expected, accuracy: 12,
          "\(color.label) route uses its sRGB preset in exported pixels")
      }
      XCTAssertEqual(composition.route, routeTransform)
      XCTAssertEqual(composition.stats, statsTransform)
      composition.selection = .route
      XCTAssertEqual(data, try RunPhotoIO.render(composition, stats: RunPhotoStats(run: run, units: .metric), route: route))
      let attachment = XCTAttachment(data: data, uniformTypeIdentifier: UTType.jpeg.identifier)
      attachment.name = "route-color-\(color.rawValue).jpg"
      attachment.lifetime = .keepAlways
      add(attachment)
    }
    composition.routeColor = .runnerYellow
    composition.showsRoute = false
    composition.image = image()
    composition.resetLayout()
    XCTAssertEqual(composition.routeColor, .runnerYellow)
    composition.showsRoute = true
    XCTAssertEqual(composition.routeColor, .runnerYellow)
  }

  func testEveryFontAndAlignmentRendersMetricsWithinMeasuredBounds() throws {
    let background = UIGraphicsImageRenderer(size: CGSize(width: 360, height: 480)).image { context in
      UIColor.black.setFill(); context.fill(CGRect(x: 0, y: 0, width: 360, height: 480))
    }
    // Include missing values and long moving-time/imperial strings in every style.
    let inputs: [(RunData, UnitSystem)] = [(makeRun(), .metric),
      (makeRun(distance: 42195, duration: 3842), .imperial), (makeRun(distance: nil), .metric)]
    for style in RunPhotoFontStyle.allCases {
      let layout = style.layout
      XCTAssertGreaterThanOrEqual(layout.labelHeight, layout.labelFont.lineHeight)
      XCTAssertGreaterThanOrEqual(layout.valueHeight, layout.valueFont.lineHeight)
      for alignment in RunPhotoAlignment.allCases {
        for (run, units) in inputs {
          var composition = RunPhotoComposition()
          composition.image = background
          composition.fontStyle = style
          composition.alignment = alignment
          composition.stats = RunPhotoTransform(center: CGPoint(x: 0.5, y: 0.5), scale: 1)
          let data = try RunPhotoIO.render(composition, stats: RunPhotoStats(run: run, units: units),
            route: RunPhotoRoute(run: run))
          let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
          let cg = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
          let pixels = rgba(cg)
          let top = Int((480 - layout.size.height) / 2)
          let labelPixels = (max(0, top)..<Int(CGFloat(top) + layout.labelHeight + 1)).flatMap { y in
            (0..<360).filter { x in
              let index = (y * 360 + x) * 4
              return pixels[index] > 210 && pixels[index + 1] > 210 && pixels[index + 2] > 210
            }
          }
          let width = ("Distance" as NSString).size(withAttributes: [.font: layout.labelFont]).width
          let expected: CGFloat
          switch alignment {
          case .leading: expected = 50
          case .center: expected = (360 - width) / 2
          case .trailing: expected = 310 - width
          }
          XCTAssertEqual(CGFloat(try XCTUnwrap(labelPixels.min())), expected, accuracy: 4,
            "\(style) \(alignment) label follows alignment")
          for y in 0..<cg.height {
            for x in 0..<cg.width {
              let index = (y * cg.width + x) * 4
              if pixels[index] > 150 && pixels[index + 1] > 200 {
                XCTAssertTrue(x >= 49 && x <= 311 && y >= top - 1
                  && y <= top + Int(layout.size.height) + 1, "Artwork stays in measured bounds")
              }
            }
          }
          if units == .imperial {
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: UTType.jpeg.identifier)
            attachment.name = "photo-\(style.rawValue)-\(alignment.rawValue).jpg"
            attachment.lifetime = .keepAlways
            add(attachment)
          }
        }
      }
    }
  }

  func testWordmarkIsFixedAcrossFontsAndHasAnOpenVectorBowl() throws {
    var reference: [UInt8]?
    for style in RunPhotoFontStyle.allCases {
      let renderer = ImageRenderer(content: RunPhotoWordmark()
        .font(Font(style.layout.valueFont)).frame(width: 260, height: 48).background(.black))
      renderer.scale = 3
      let pixels = rgba(try XCTUnwrap(renderer.cgImage))
      if let reference { XCTAssertEqual(reference, pixels) } else { reference = pixels }
    }
    let path = RunPhotoRunnerR().path(in: CGRect(x: 0, y: 0, width: 100, height: 100))
    XCTAssertEqual(path.boundingRect, CGRect(x: 0, y: 0, width: 100, height: 100))
    let renderer = ImageRenderer(content: RunPhotoRunnerR().fill(.white, style: FillStyle(eoFill: true))
      .frame(width: 100, height: 100).background(.black))
    renderer.scale = 1
    let pixels = rgba(try XCTUnwrap(renderer.cgImage))
    XCTAssertGreaterThan(pixels[(70 * 100 + 10) * 4], 200, "R has a solid stem")
    XCTAssertLessThan(pixels[(30 * 100 + 50) * 4], 10, "R has a readable open bowl")
    XCTAssertGreaterThan(pixels[(95 * 100 + 83) * 4], 200, "R has a forward leg")
  }

  func testIconBoundsResetAndOverlappingLayerSelection() throws {
    XCTAssertNotNil(RunPhotoBrandAssets.icon, "The isolated test bundle includes the app icon")
    var composition = RunPhotoComposition()
    XCTAssertEqual(composition.alignment, .leading)
    XCTAssertEqual(composition.fontStyle, .sport)
    XCTAssertFalse(composition.showsIcon)
    composition.image = image()
    composition.fontStyle = .serif
    composition.alignment = .trailing
    composition.showsIcon = true
    composition.showsRoute = true
    let same = RunPhotoTransform(center: CGPoint(x: 0.5, y: 0.5), scale: 1)
    composition.stats = same; composition.route = same; composition.icon = same
    for layer in [RunPhotoLayer.stats, .route, .icon] {
      composition.selection = layer
      XCTAssertEqual(composition.layer(at: CGPoint(x: 180, y: 240)), layer)
    }
    composition.selection = .photo
    XCTAssertEqual(composition.layer(at: CGPoint(x: 180, y: 240)), .icon)
    composition.showsIcon = false
    XCTAssertEqual(composition.layer(at: CGPoint(x: 180, y: 240)), .stats)
    XCTAssertEqual(composition.icon, same)
    composition.showsIcon = true
    composition.resetLayout()
    XCTAssertEqual(composition.fontStyle, .serif)
    XCTAssertEqual(composition.alignment, .trailing)
    XCTAssertTrue(composition.showsIcon && composition.showsRoute)
    for format in RunPhotoFormat.allCases {
      composition.format = format
      composition.setTransform(RunPhotoTransform(center: CGPoint(x: -4, y: 8), scale: 100), layer: .icon)
      let value = composition.icon, canvas = composition.canvasSize
      XCTAssertGreaterThanOrEqual(value.center.x * canvas.width - 32 * value.scale, 0)
      XCTAssertLessThanOrEqual(value.center.y * canvas.height + 32 * value.scale, canvas.height)
    }
  }

  func testIconExportAndAppearanceDoNotChangeOtherLayers() throws {
    var composition = RunPhotoComposition()
    composition.image = image()
    composition.resetLayout()
    let stats = RunPhotoStats(run: makeRun(), units: .metric), route = RunPhotoRoute(run: makeRun())
    let plain = try RunPhotoIO.render(composition, stats: stats, route: route)
    let statsTransform = composition.stats, routeTransform = composition.route
    composition.showsIcon = true
    composition.setTransform(RunPhotoTransform(center: CGPoint(x: 0.8, y: 0.2), scale: 1.2), layer: .icon)
    XCTAssertEqual(statsTransform, composition.stats)
    XCTAssertEqual(routeTransform, composition.route)
    for format in RunPhotoFormat.allCases {
      composition.format = format
      composition.alignment = .center
      composition.fontStyle = .rounded
      composition.constrainOverlays()
      let data = try RunPhotoIO.render(composition, stats: stats, route: route)
      XCTAssertNotEqual(plain, data)
      composition.selection = .icon
      XCTAssertEqual(data, try RunPhotoIO.render(composition, stats: stats, route: route))
      let attachment = XCTAttachment(data: data, uniformTypeIdentifier: UTType.jpeg.identifier)
      attachment.name = "photo-icon-\(format.rawValue).jpg"
      attachment.lifetime = .keepAlways
      add(attachment)
    }
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
