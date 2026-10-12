import AVFoundation
import CoreTransferable
import CoreImage
import Photos
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct RunVideo {
  let url: URL
  let size: CGSize
  let duration: Double
  let poster: UIImage
}

enum RunVideoError: LocalizedError {
  case unreadable, exportFailed
  var errorDescription: String? {
    switch self {
    case .unreadable:
      return "This video couldn’t be loaded. Try another clip. If it’s in iCloud, check your connection."
    case .exportFailed:
      return "The video couldn’t be exported. Your edits are still here. Please try again."
    }
  }
}

struct RunVideoFile: Transferable, Sendable {
  let url: URL
  static var transferRepresentation: some TransferRepresentation {
    FileRepresentation(importedContentType: .movie) { received in
      let url = try RunVideoIO.temporaryFile(named: "Source.mov")
      do { try FileManager.default.copyItem(at: received.file, to: url) }
      catch { RunVideoIO.removeFile(url); throw error }
      return RunVideoFile(url: url)
    }
  }
}

enum RunVideoIO {
  static func load(_ item: PhotosPickerItem) async throws -> RunVideo {
    guard let file = try await item.loadTransferable(type: RunVideoFile.self) else {
      throw RunVideoError.unreadable
    }
    do { return try await inspect(file.url) }
    catch { removeFile(file.url); throw error }
  }

  /// Does not take ownership of the file. Callers remove their own temporary copies.
  static func inspect(_ url: URL) async throws -> RunVideo {
    try Task.checkCancellation()
    let asset = AVURLAsset(url: url)
    guard let track = try await asset.loadTracks(withMediaType: .video).first else {
      throw RunVideoError.unreadable
    }
    let duration = try await asset.load(.duration).seconds
    let natural = try await track.load(.naturalSize)
    let transform = try await track.load(.preferredTransform)
    let bounds = CGRect(origin: .zero, size: natural).applying(transform)
    let size = CGSize(width: abs(bounds.width), height: abs(bounds.height))
    guard duration.isFinite, duration > 0, size.width.isFinite, size.height.isFinite,
      size.width >= 2, size.height >= 2 else { throw RunVideoError.unreadable }
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: 1920, height: 1920)
    let frame = try await generator.image(at: .zero)
    try Task.checkCancellation()
    return RunVideo(url: url, size: size, duration: duration,
      poster: UIImage(cgImage: frame.image))
  }

  @MainActor static func render(_ composition: RunPhotoComposition, stats: RunPhotoStats,
    route: RunPhotoRoute) async throws -> URL {
    try Task.checkCancellation()
    guard let video = composition.video,
      !composition.showsIcon || RunPhotoBrandAssets.icon != nil else {
      throw RunVideoError.exportFailed
    }
    let asset = AVURLAsset(url: video.url)
    guard let source = try await asset.loadTracks(withMediaType: .video).first else {
      throw RunVideoError.unreadable
    }
    let duration = try await asset.load(.duration)
    let natural = try await source.load(.naturalSize)
    let preferred = try await source.load(.preferredTransform)
    let frameDuration = try await source.load(.minFrameDuration)
    try Task.checkCancellation()

    let movie = AVMutableComposition()
    guard let track = movie.addMutableTrack(withMediaType: .video,
      preferredTrackID: kCMPersistentTrackID_Invalid) else { throw RunVideoError.exportFailed }
    let range = CMTimeRange(start: .zero, duration: duration)
    try track.insertTimeRange(range, of: source, at: .zero)
    // Audio is copied from the clip, including silent clips and delayed audio tracks.
    for sourceAudio in try await asset.loadTracks(withMediaType: .audio) {
      let audioRange = CMTimeRangeGetIntersection(try await sourceAudio.load(.timeRange), otherRange: range)
      guard audioRange.duration > .zero else { continue }
      guard let audio = movie.addMutableTrack(withMediaType: .audio,
        preferredTrackID: kCMPersistentTrackID_Invalid) else { throw RunVideoError.exportFailed }
      try audio.insertTimeRange(audioRange, of: sourceAudio, at: audioRange.start)
    }

    let output = composition.outputSize
    let canvas = composition.canvasSize
    let scale = output.width / canvas.width
    let frame = composition.crop.imageFrame(image: video.size, canvas: canvas)
      .applying(CGAffineTransform(scaleX: scale, y: scale))
    let bounds = CGRect(origin: .zero, size: natural).applying(preferred)
    let transform = preferred
      .concatenating(CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY))
      .concatenating(CGAffineTransform(scaleX: frame.width / video.size.width,
        y: frame.height / video.size.height))
      .concatenating(CGAffineTransform(translationX: frame.minX, y: frame.minY))
    // Rasterize exactly the same overlay artwork as the preview, once, with alpha.
    let renderer = ImageRenderer(content: RunPhotoCompositionView(
      composition: composition, stats: stats, route: route, includesBackground: false))
    renderer.scale = scale
    renderer.isOpaque = false
    guard let artwork = renderer.cgImage else { throw RunVideoError.exportFailed }
    // Editor/AVPlayer coordinates start at the top; Core Image starts at the bottom.
    let imageTransform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: natural.height)
      .concatenating(transform)
      .concatenating(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: output.height))
    let instruction = RunVideoInstruction(timeRange: range, trackID: track.trackID,
      transform: imageTransform, artwork: artwork)
    // Deliver an SDR movie compatible with Photos and common share destinations.
    let videoComposition = AVVideoComposition(configuration: .init(
      colorPrimaries: AVVideoColorPrimaries_ITU_R_709_2,
      colorTransferFunction: AVVideoTransferFunction_ITU_R_709_2,
      colorYCbCrMatrix: AVVideoYCbCrMatrix_ITU_R_709_2,
      customVideoCompositorClass: RunVideoCompositor.self,
      frameDuration: frameDuration.isNumeric && frameDuration > .zero
        ? frameDuration : CMTime(value: 1, timescale: 30),
      instructions: [instruction], renderSize: output, sourceTrackIDForFrameTiming: track.trackID))

    guard let exporter = AVAssetExportSession(asset: movie,
      presetName: AVAssetExportPresetHighestQuality) else { throw RunVideoError.exportFailed }
    exporter.videoComposition = videoComposition
    exporter.timeRange = range
    exporter.metadata = []
    exporter.shouldOptimizeForNetworkUse = true
    let url = try temporaryFile(named: "The Runner.mp4")
    do {
      try Task.checkCancellation()
      try await exporter.export(to: url, as: .mp4)
      try Task.checkCancellation()
      return url
    } catch { removeFile(url); throw error }
  }

  static func save(_ url: URL) async throws {
    let authorization = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
    guard authorization == .authorized || authorization == .limited else {
      throw RunPhotoError.permissionDenied
    }
    try await PHPhotoLibrary.shared().performChanges {
      PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: url, options: nil)
    }
  }

  static func temporaryFile(named name: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "run-video-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent(name)
  }

  static func shareFile(_ source: URL) throws -> URL {
    let url = try temporaryFile(named: "The Runner.mp4")
    do { try FileManager.default.copyItem(at: source, to: url); return url }
    catch { removeFile(url); throw error }
  }

  static func removeFile(_ url: URL) {
    // Only delete files owned by this feature, never a caller's original device file.
    guard url.deletingLastPathComponent().lastPathComponent.hasPrefix("run-video-") else { return }
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
  }
}

/// Immutable instructions give the frame renderer no dependency on editor state.
private final class RunVideoInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
  let timeRange: CMTimeRange
  let enablePostProcessing = false
  let containsTweening = false
  let passthroughTrackID = kCMPersistentTrackID_Invalid
  let requiredSourceTrackIDs: [NSValue]?
  let trackID: CMPersistentTrackID
  let transform: CGAffineTransform
  let artwork: CIImage

  init(timeRange: CMTimeRange, trackID: CMPersistentTrackID,
    transform: CGAffineTransform, artwork: CGImage) {
    self.timeRange = timeRange
    self.trackID = trackID
    requiredSourceTrackIDs = [NSNumber(value: trackID)]
    self.transform = transform
    self.artwork = CIImage(cgImage: artwork)
  }
}

/// Core Image renders directly to the exporter's buffer pool, without a layer tree.
private final class RunVideoCompositor: NSObject, AVVideoCompositing {
  var sourcePixelBufferAttributes: [String: any Sendable]? {
    [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
  }
  var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] {
    [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
  }
  // AVFoundation converts HDR/wide-gamut source frames to SDR before compositing.
  var supportsHDRSourceFrames: Bool { false }
  var supportsWideColorSourceFrames: Bool { false }
  private let context = CIContext(options: [.cacheIntermediates: false])
  private let space = CGColorSpace(name: CGColorSpace.sRGB)!

  func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

  func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
    // Finishing synchronously means there are no queued frames left to cancel.
    autoreleasepool {
      guard let instruction = request.videoCompositionInstruction as? RunVideoInstruction,
        let source = request.sourceFrame(byTrackID: instruction.trackID),
        let output = request.renderContext.newPixelBuffer() else {
        request.finish(with: RunVideoError.exportFailed)
        return
      }
      let bounds = CGRect(origin: .zero, size: request.renderContext.size)
      let image = CIImage(cvPixelBuffer: source).transformed(by: instruction.transform)
      let composed = instruction.artwork.composited(over: image).cropped(to: bounds)
      context.render(composed, to: output, bounds: bounds, colorSpace: space)
      request.finish(withComposedVideoFrame: output)
    }
  }
}
