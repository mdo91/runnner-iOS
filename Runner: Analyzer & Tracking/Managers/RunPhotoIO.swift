import CoreTransferable
import ImageIO
import Photos
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

enum RunPhotoError: LocalizedError, Equatable {
  case unreadable, renderFailed, permissionDenied, sharingFailed
  var errorDescription: String? {
    switch self {
    case .unreadable: return "This photo couldn’t be loaded. Try again, or choose another image. If it’s in iCloud, check your connection."
    case .renderFailed: return "The image couldn’t be exported. Your edits are still here. Please try again."
    case .permissionDenied: return "Runner needs add-only Photos access to save here. You can use Share instead. Changing access in Settings may restart Runner and discard this edit, so share a copy first."
    case .sharingFailed: return "This app couldn’t finish sharing. Try again or choose another destination."
    }
  }
}

struct RunPhotoFile: Transferable, Sendable {
  let url: URL
  static var transferRepresentation: some TransferRepresentation {
    FileRepresentation(importedContentType: .image) { received in
      let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      try FileManager.default.copyItem(at: received.file, to: url)
      return RunPhotoFile(url: url)
    }
  }
}

enum RunPhotoIO {
  static func load(_ item: PhotosPickerItem) async throws -> UIImage {
    guard let file = try await item.loadTransferable(type: RunPhotoFile.self) else {
      throw RunPhotoError.unreadable
    }
    defer { try? FileManager.default.removeItem(at: file.url) }
    try Task.checkCancellation()
    return try await Task.detached(priority: .userInitiated) {
      try decode(file.url)
    }.value
  }

  static func decode(_ url: URL) throws -> UIImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL,
      [kCGImageSourceShouldCache: false] as CFDictionary),
      let image = CGImageSourceCreateThumbnailAtIndex(source,
        CGImageSourceGetPrimaryImageIndex(source), [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceCreateThumbnailWithTransform: true,
          kCGImageSourceShouldCacheImmediately: true,
          kCGImageSourceThumbnailMaxPixelSize: 4096,
        ] as CFDictionary)
    else { throw RunPhotoError.unreadable }
    return UIImage(cgImage: image, scale: 1, orientation: .up)
  }

  @MainActor static func render(_ composition: RunPhotoComposition, stats: RunPhotoStats,
    route: RunPhotoRoute) throws -> Data {
    guard composition.image != nil else { throw RunPhotoError.renderFailed }
    guard !composition.showsIcon || RunPhotoBrandAssets.icon != nil else { throw RunPhotoError.renderFailed }
    let size = composition.outputSize
    let renderer = ImageRenderer(content: RunPhotoCompositionView(
      composition: composition, stats: stats, route: route))
    renderer.scale = size.width / composition.canvasSize.width
    renderer.isOpaque = true
    guard let image = renderer.cgImage,
      let space = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
        bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { throw RunPhotoError.renderFailed }
    context.draw(image, in: CGRect(origin: .zero, size: size))
    guard let converted = context.makeImage() else { throw RunPhotoError.renderFailed }
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
    else { throw RunPhotoError.renderFailed }
    CGImageDestinationAddImage(destination, converted,
      [kCGImageDestinationLossyCompressionQuality: 0.94] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { throw RunPhotoError.renderFailed }
    return data as Data
  }

  static func save(_ data: Data) async throws {
    let authorization = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
    guard authorization == .authorized || authorization == .limited else {
      throw RunPhotoError.permissionDenied
    }
    try await PHPhotoLibrary.shared().performChanges {
      PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
    }
  }

  static func shareFile(_ data: Data) throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "run-photo-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("The Runner.jpg")
    do { try data.write(to: url, options: .atomic) }
    catch { try? FileManager.default.removeItem(at: directory); throw error }
    return url
  }

  static func removeShareFile(_ url: URL) {
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
  }
}

struct RunPhotoShareSheet: UIViewControllerRepresentable {
  let url: URL
  let completion: @MainActor (Bool, Error?) -> Void
  func makeUIViewController(context: Context) -> UIActivityViewController {
    // Image payloads advertise photo sharing to compatible installed social-app extensions.
    let item: Any
    if let image = UIImage(contentsOfFile: url.path) { item = image } else { item = url }
    let controller = UIActivityViewController(activityItems: [item], applicationActivities: nil)
    if let popover = controller.popoverPresentationController {
      popover.sourceView = controller.view
      popover.sourceRect = CGRect(x: controller.view.bounds.midX,
        y: controller.view.bounds.maxY, width: 0, height: 0)
      popover.permittedArrowDirections = []
    }
    controller.completionWithItemsHandler = { _, completed, _, error in
      Task { @MainActor in completion(completed, error) }
    }
    return controller
  }
  func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
