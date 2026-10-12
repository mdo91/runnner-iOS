import AVFoundation
import RunCore
import SwiftUI
import XCTest

@MainActor final class RunVideoTests: XCTestCase {
  private var run: RunData {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    return RunData(start: start, end: start.addingTimeInterval(1500), duration: 1500,
      distanceMeters: 5000, source: "Video test", route: [
        RoutePoint(timestamp: start, latitude: 41, longitude: 29, horizontalAccuracy: 5),
        RoutePoint(timestamp: start.addingTimeInterval(5), latitude: 41.0001,
          longitude: 29.0001, horizontalAccuracy: 5),
      ])
  }
  private func composition(_ url: URL) async throws -> RunPhotoComposition {
    let video = try await RunVideoIO.inspect(url)
    var result = RunPhotoComposition()
    result.video = video
    result.image = video.poster
    result.resetLayout()
    return result
  }
  private func frame(_ url: URL, at seconds: Double) async throws -> CGImage {
    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
    generator.appliesPreferredTrackTransform = true
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    return try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
  }
  private func pixels(_ image: CGImage) throws -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
    try bytes.withUnsafeMutableBytes {
      let context = try XCTUnwrap(CGContext(data: $0.baseAddress, width: image.width,
        height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    return bytes
  }
  func testVideoExportKeepsMotionAudioDurationAndOverlaysInEveryFormat() async throws {
    let source = try await RunVideoFixture.create()
    defer { RunVideoIO.removeFile(source) }
    var edit = try await composition(source)
    edit.showsRoute = true
    edit.routeColor = .runnerYellow
    edit.showsIcon = true
    let stats = RunPhotoStats(run: run, units: .metric)
    let route = RunPhotoRoute(run: run)
    for format in RunPhotoFormat.allCases {
      edit.format = format
      edit.constrainOverlays()
      let output = try await RunVideoIO.render(edit, stats: stats, route: route)
      defer { RunVideoIO.removeFile(output) }
      let asset = AVURLAsset(url: output)
      let duration = try await asset.load(.duration).seconds
      XCTAssertEqual(duration, 2, accuracy: 0.15)
      let audio = try await asset.loadTracks(withMediaType: .audio)
      XCTAssertEqual(audio.count, 1)
      let audioDuration = try await XCTUnwrap(audio.first).load(.timeRange).duration.seconds
      XCTAssertEqual(audioDuration, 2, accuracy: 0.15)
      let metadata = try await asset.load(.metadata)
      XCTAssertTrue(metadata.isEmpty, "No source location metadata enters the new movie")
      let videoTracks = try await asset.loadTracks(withMediaType: .video)
      let track = try XCTUnwrap(videoTracks.first)
      let frameRate = try await track.load(.nominalFrameRate)
      XCTAssertEqual(frameRate, 8, accuracy: 0.01)
      let first = try await frame(output, at: 0.25)
      let last = try await frame(output, at: 1.5)
      XCTAssertEqual(first.width, Int(edit.outputSize.width))
      XCTAssertEqual(first.height, Int(edit.outputSize.height))
      let startPixels = try pixels(first)
      let endPixels = try pixels(last)
      let changed = stride(from: 0, to: startPixels.count, by: 4).filter {
        abs(Int(startPixels[$0 + 1]) - Int(endPixels[$0 + 1])) > 120
      }.count
      XCTAssertGreaterThan(changed, first.width * first.height / 40,
        "The source bar must keep moving beneath static overlays")

      // Compare export overlay locations to an actual transparent preview render.
      let renderer = ImageRenderer(content: RunPhotoCompositionView(composition: edit,
        stats: stats, route: route, includesBackground: false))
      renderer.scale = edit.outputSize.width / edit.canvasSize.width
      let overlay = try pixels(XCTUnwrap(renderer.cgImage))
      var opaque = 0
      var matching = 0
      for index in stride(from: 0, to: overlay.count, by: 4) where overlay[index + 3] > 250 {
        opaque += 1
        if (0..<3).allSatisfy({ abs(Int(overlay[index + $0]) - Int(startPixels[index + $0])) < 65 }) {
          matching += 1
        }
      }
      XCTAssertGreaterThan(opaque, 500)
      XCTAssertGreaterThan(Double(matching) / Double(opaque), 0.9,
        "The stats, route, and icon must match the preview at the same pixels")
      let attachment = XCTAttachment(contentsOfFile: output)
      attachment.name = "Run video - \(format.rawValue).mp4"
      attachment.lifetime = .keepAlways
      add(attachment)
    }
  }

  func testPortraitRotationAndCropMatchThePhotoPreview() async throws {
    let size = CGSize(width: 480, height: 320)
    let source = try await RunVideoFixture.create(size: size,
      transform: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: size.height, ty: 0),
      includesAudio: false)
    defer { RunVideoIO.removeFile(source) }
    var edit = try await composition(source)
    XCTAssertEqual(edit.imageSize, CGSize(width: 320, height: 480))
    edit.format = .square
    edit.crop = RunPhotoCrop(zoom: 1.5, offset: CGPoint(x: 0.5, y: -0.7))
    edit.showsRoute = true
    edit.routeColor = .white
    let stats = RunPhotoStats(run: run, units: .imperial)
    let route = RunPhotoRoute(run: run)
    let output = try await RunVideoIO.render(edit, stats: stats, route: route)
    defer { RunVideoIO.removeFile(output) }
    let rendered = try await frame(output, at: 0)
    let actual = try pixels(rendered)
    let expectedData = try RunPhotoIO.render(edit, stats: stats, route: route)
    let expected = try pixels(XCTUnwrap(UIImage(data: expectedData)?.cgImage))
    XCTAssertEqual(actual.count, expected.count)
    let matching = stride(from: 0, to: actual.count, by: 4).filter { index in
      (0..<3).allSatisfy { abs(Int(actual[index + $0]) - Int(expected[index + $0])) < 50 }
    }.count
    XCTAssertGreaterThan(Double(matching) / Double(rendered.width * rendered.height), 0.95,
      "A rotated and panned video frame must agree with the existing image renderer")
    let audio = try await AVURLAsset(url: output).loadTracks(withMediaType: .audio)
    XCTAssertTrue(audio.isEmpty)
  }

  func testUnusualSourceDimensionsAndTemporaryShareOwnership() async throws {
    let source = try await RunVideoFixture.create(size: CGSize(width: 322, height: 482))
    defer { RunVideoIO.removeFile(source) }
    var edit = try await composition(source)
    edit.video = RunVideo(url: source, size: CGSize(width: 321, height: 481),
      duration: 2, poster: edit.image!)
    XCTAssertEqual(edit.outputSize, CGSize(width: 320, height: 480))
    let copy = try RunVideoIO.shareFile(source)
    XCTAssertTrue(FileManager.default.fileExists(atPath: copy.path))
    XCTAssertEqual(try Data(contentsOf: copy), try Data(contentsOf: source))
    RunVideoIO.removeFile(copy)
    XCTAssertFalse(FileManager.default.fileExists(atPath: copy.deletingLastPathComponent().path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    let original = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).mov")
    try Data([1]).write(to: original)
    defer { try? FileManager.default.removeItem(at: original) }
    RunVideoIO.removeFile(original)
    XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
  }

  func testUnreadableVideoAndCancelledExportDoNotLeaveFiles() async throws {
    let bad = try RunVideoIO.temporaryFile(named: "Invalid.mov")
    defer { RunVideoIO.removeFile(bad) }
    try Data([0, 1, 2]).write(to: bad)
    do { _ = try await RunVideoIO.inspect(bad); XCTFail("Invalid clips must fail") }
    catch { /* Failure leaves any previously selected media available in the editor. */ }
    let source = try await RunVideoFixture.create()
    defer { RunVideoIO.removeFile(source) }
    let edit = try await composition(source)
    let before = try videoDirectories()
    let stats = RunPhotoStats(run: run, units: .metric)
    let route = RunPhotoRoute(run: run)
    let task = Task { try await RunVideoIO.render(edit, stats: stats, route: route) }
    task.cancel()
    do { _ = try await task.value; XCTFail("Cancelled exports must fail") }
    catch is CancellationError {} catch { XCTFail("Unexpected cancellation error: \(error)") }
    XCTAssertEqual(try videoDirectories(), before)
  }
  private func videoDirectories() throws -> Set<String> {
    Set(try FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)
      .filter { $0.hasPrefix("run-video-") })
  }
}
