import AVFoundation
import Photos
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

  func testExportPreservesNeutralBackgroundAndColoredArtwork() async throws {
    let source = try await RunVideoFixture.create(size: CGSize(width: 720, height: 1080), gray: 128)
    defer { RunVideoIO.removeFile(source) }
    var edit = try await composition(source)
    edit.showsRoute = true
    edit.routeColor = .green
    edit.route.scale = 1.4
    edit.constrainOverlays()
    let stats = RunPhotoStats(run: run, units: .metric)
    let route = RunPhotoRoute(run: run)
    let output = try await RunVideoIO.render(edit, stats: stats, route: route)
    defer { RunVideoIO.removeFile(output) }
    let sourcePixels = try pixels(await frame(source, at: 0.25))
    let actual = try pixels(await frame(output, at: 0.25))
    let renderer = ImageRenderer(content: RunPhotoCompositionView(composition: edit,
      stats: stats, route: route, includesBackground: false))
    renderer.scale = edit.outputSize.width / edit.canvasSize.width
    let artwork = try pixels(XCTUnwrap(renderer.cgImage))
    let width = Int(edit.outputSize.width)
    let height = Int(edit.outputSize.height)
    var backgroundDifferences = [Double](repeating: 0, count: 3)
    var artworkDifferences = [Double](repeating: 0, count: 3)
    var backgroundCount = 0
    var artworkCount = 0
    let green = [52, 199, 89]
    for y in 8..<(height - 8) {
      for x in 8..<(width - 8) {
        let index = (y * width + x) * 4
        // Stay away from artwork edges and H.264 chroma subsampling boundaries.
        if stride(from: -8, through: 8, by: 4).allSatisfy({ dy in
          stride(from: -8, through: 8, by: 4).allSatisfy { dx in
            artwork[((y + dy) * width + x + dx) * 4 + 3] == 0
          }
        }) {
          backgroundCount += 1
          for channel in 0..<3 {
            backgroundDifferences[channel] += Double(Int(actual[index + channel]) - Int(sourcePixels[index + channel]))
          }
        }
        if (-2...2).allSatisfy({ dy in
          (-2...2).allSatisfy { dx in
            let pixel = ((y + dy) * width + x + dx) * 4
            return artwork[pixel + 3] == 255 && (0..<3).allSatisfy {
              abs(Int(artwork[pixel + $0]) - green[$0]) <= 2
            }
          }
        }) {
          artworkCount += 1
          for channel in 0..<3 {
            artworkDifferences[channel] += Double(Int(actual[index + channel]) - Int(artwork[index + channel]))
          }
        }
      }
    }
    XCTAssertGreaterThan(backgroundCount, 10000)
    XCTAssertGreaterThan(artworkCount, 30)
    for channel in 0..<3 {
      XCTAssertEqual(backgroundDifferences[channel] / Double(max(1, backgroundCount)), 0, accuracy: 3,
        "Neutral clip values must survive the sRGB/Rec. 709 conversion")
      XCTAssertEqual(artworkDifferences[channel] / Double(max(1, artworkCount)), 0, accuracy: 6,
        "Opaque route colors must agree with the preview")
    }
  }

  func testDelayedFirstVideoSampleImportsAndExportsWithItsAudio() async throws {
    let source = try await RunVideoFixture.create(videoStart: 0.5)
    defer { RunVideoIO.removeFile(source) }
    let edit = try await composition(source)
    XCTAssertEqual(edit.video?.duration ?? 0, 2.5, accuracy: 0.01)
    XCTAssertEqual(edit.image?.size, CGSize(width: 320, height: 480))
    let output = try await RunVideoIO.render(edit,
      stats: RunPhotoStats(run: run, units: .metric), route: RunPhotoRoute(run: run))
    defer { RunVideoIO.removeFile(output) }
    let asset = AVURLAsset(url: output)
    let duration = try await asset.load(.duration).seconds
    XCTAssertEqual(duration, 2.5, accuracy: 0.15)
    let audio = try await asset.loadTracks(withMediaType: .audio)
    let audioRange = try await XCTUnwrap(audio.first).load(.timeRange)
    XCTAssertEqual(audioRange.start.seconds, 0, accuracy: 0.01)
    XCTAssertEqual(audioRange.duration.seconds, 2.5, accuracy: 0.15)
    let leading = try pixels(await frame(output, at: 0))
    let black = stride(from: 0, to: leading.count, by: 4).filter {
      leading[$0] < 5 && leading[$0 + 1] < 5 && leading[$0 + 2] < 5
    }.count
    let white = stride(from: 0, to: leading.count, by: 4).filter {
      leading[$0] > 240 && leading[$0 + 1] > 240 && leading[$0 + 2] > 240
    }.count
    XCTAssertGreaterThan(black, 320 * 480 / 2, "An empty leading interval has a black background")
    XCTAssertGreaterThan(white, 100, "The overlay is still present before the first video sample")
    let later = try pixels(await frame(output, at: 0.75))
    let red = stride(from: 0, to: later.count, by: 4).filter {
      later[$0] > 180 && later[$0 + 1] < 60 && later[$0 + 2] < 60
    }.count
    XCTAssertGreaterThan(red, 10000, "Real source frames resume at the original timestamp")
  }

  func testCancellationBeforeOrDuringAuthorizationNeverCommitsPhotosChanges() async throws {
    var authorized = false
    var committing = false
    var wrote = false
    let before = Task {
      try await RunVideoIO.save(authorization: { authorized = true; return .authorized },
        onCommit: { committing = true }, changes: { wrote = true })
    }
    before.cancel()
    do { try await before.value; XCTFail("Cancelled saves must stop before authorization") }
    catch is CancellationError {}
    XCTAssertFalse(authorized)
    XCTAssertFalse(committing)
    XCTAssertFalse(wrote)

    let during = Task {
      try await RunVideoIO.save(authorization: {
        authorized = true
        withUnsafeCurrentTask { $0?.cancel() }
        return .authorized
      }, onCommit: { committing = true }, changes: { wrote = true })
    }
    do { try await during.value; XCTFail("Cancellation during authorization must stop before saving") }
    catch is CancellationError {}
    XCTAssertTrue(authorized)
    XCTAssertFalse(committing)
    XCTAssertFalse(wrote)
  }

  func testAcceptedPhotosTransactionStillReportsSuccessIfTheTaskIsCancelled() async throws {
    var committing = false
    var wrote = false
    let task = Task {
      try await RunVideoIO.save(authorization: { .authorized }, onCommit: { committing = true }) {
        XCTAssertTrue(committing, "Hide Cancel Export before submitting the Photos transaction")
        withUnsafeCurrentTask { $0?.cancel() }
        wrote = true
      }
    }
    try await task.value
    XCTAssertTrue(wrote, "A successful Photos commit must produce a saved receipt")
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
