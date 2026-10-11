import CoreGraphics
import CoreText
import Foundation
import RunCore
import UIKit

enum RunPhotoFormat: String, CaseIterable, Identifiable {
  case original = "Original", story = "Story", portrait = "Portrait", square = "Square"
  var id: Self { self }
  var label: String {
    switch self {
    case .original: return "Original"
    case .story: return "Story 9:16"
    case .portrait: return "Portrait 4:5"
    case .square: return "Square 1:1"
    }
  }
  func outputSize(for image: CGSize) -> CGSize {
    switch self {
    case .story: return CGSize(width: 1080, height: 1920)
    case .portrait: return CGSize(width: 1080, height: 1350)
    case .square: return CGSize(width: 1080, height: 1080)
    case .original:
      let factor = min(1, 2160 / max(1, image.width, image.height))
      return CGSize(width: max(1, (image.width * factor).rounded()),
        height: max(1, (image.height * factor).rounded()))
    }
  }
}

enum RunPhotoLayer: String, CaseIterable, Identifiable {
  case stats = "Stats", route = "Route", icon = "Icon", photo = "Crop"
  var id: Self { self }
}

enum RunPhotoAlignment: String, CaseIterable, Identifiable {
  case leading = "Leading", center = "Center", trailing = "Trailing"
  var id: Self { self }
}

enum RunPhotoFontStyle: String, CaseIterable, Identifiable {
  case sport = "Sport", clean = "Clean", rounded = "Rounded", mono = "Mono", serif = "Serif"
  var id: Self { self }
  var layout: RunPhotoTextLayout { Self.layouts[self]! }
  private static let layouts = Dictionary(uniqueKeysWithValues:
    allCases.map { ($0, RunPhotoTextLayout(style: $0)) })
}

/// Cached font metrics define the same content bounds for artwork, handles, and gestures.
struct RunPhotoTextLayout {
  let labelFont: UIFont
  let valueFont: UIFont
  let labelHeight: CGFloat
  let valueHeight: CGFloat
  var size: CGSize {
    CGSize(width: 260, height: 3 * (labelHeight + valueHeight) + 30 + 48)
  }
  init(style: RunPhotoFontStyle) {
    func font(size: CGFloat, weight: UIFont.Weight, digits: Bool) -> UIFont {
      let base = style == .sport
        ? UIFont.systemFont(ofSize: size, weight: weight, width: .condensed)
        : UIFont.systemFont(ofSize: size, weight: weight)
      let design: UIFontDescriptor.SystemDesign
      switch style {
      case .sport, .clean: design = .default
      case .rounded: design = .rounded
      case .mono: design = .monospaced
      case .serif: design = .serif
      }
      var descriptor = (style == .sport || style == .clean) ? base.fontDescriptor
        : (base.fontDescriptor.withDesign(design) ?? base.fontDescriptor)
      if digits {
        descriptor = descriptor.addingAttributes([.featureSettings: [
          [UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
            UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector]
        ]])
      }
      return UIFont(descriptor: descriptor, size: size)
    }
    labelFont = font(size: 13, weight: .medium, digits: false)
    valueFont = font(size: 36, weight: .heavy, digits: true)
    labelHeight = max(18, ceil(labelFont.lineHeight) + 2)
    valueHeight = max(44, ceil(valueFont.lineHeight) + 2)
  }
}

struct RunPhotoStats {
  let distance: String
  let pace: String
  let time: String
  init(run: RunData, units: UnitSystem) {
    let metrics = RunCalculator.metrics(run)
    distance = metrics.distanceMeters.map { "\(units.distance($0)) \(units.distanceUnit)" } ?? "—"
    pace = metrics.averagePaceSecondsPerKm.map { "\(units.pace($0))/\(units.distanceUnit)" } ?? "—"
    time = Self.duration(metrics.movingSeconds)
  }
  static func duration(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0, seconds < Double(Int.max / 2) else { return "—" }
    let value = Int(seconds.rounded())
    if value >= 3600 {
      return String(format: "%dh %02dm %02ds", value / 3600, value / 60 % 60, value % 60)
    }
    return String(format: "%dm %02ds", value / 60, value % 60)
  }
}

/// A map-free, north-up route. Each subpath is an independently valid GPS segment.
struct RunPhotoRoute {
  let segments: [[CGPoint]]
  let path: CGPath
  var isEmpty: Bool { segments.isEmpty }

  init(run: RunData) {
    let valid = RunCalculator.routeSegments(run)
    let all = valid.flatMap { $0 }
    let reference = all.first?.longitude ?? 0
    let meanLatitude = all.isEmpty ? 0 : all.reduce(0) { $0 + $1.latitude } / Double(all.count)
    let longitudeScale = max(0.000001, cos(meanLatitude * .pi / 180))
    var projected: [[CGPoint]] = []
    for segment in valid {
      var previousLongitude = reference
      var points: [CGPoint] = []
      for point in segment {
        var longitude = point.longitude
        while longitude - previousLongitude > 180 { longitude -= 360 }
        while longitude - previousLongitude < -180 { longitude += 360 }
        previousLongitude = longitude
        let next = CGPoint(x: (longitude - reference) * longitudeScale, y: -point.latitude)
        if next != points.last { points.append(next) }
      }
      if points.count >= 2 { projected.append(points) }
    }
    let points = projected.flatMap { $0 }
    let minX = points.map(\.x).min() ?? 0, maxX = points.map(\.x).max() ?? 0
    let minY = points.map(\.y).min() ?? 0, maxY = points.map(\.y).max() ?? 0
    let extent = max(maxX - minX, maxY - minY)
    if extent > 0.000000001 {
      // Leave room for the rounded stroke at every edge.
      segments = projected.map { segment in
        segment.map {
          CGPoint(x: 0.5 + ($0.x - (minX + maxX) / 2) / extent * 0.9,
            y: 0.5 + ($0.y - (minY + maxY) / 2) / extent * 0.9)
        }
      }
    } else { segments = [] }
    let result = CGMutablePath()
    for segment in segments {
      if let first = segment.first {
        result.move(to: first)
        for point in segment.dropFirst() { result.addLine(to: point) }
      }
    }
    path = result.copy()!
  }
}

struct RunPhotoTransform: Equatable {
  var center: CGPoint
  var scale: CGFloat

  func clamped(content: CGSize, canvas: CGSize) -> Self {
    let inset: CGFloat = min(10, canvas.width * 0.02, canvas.height * 0.02)
    let limit = min(2.5, (canvas.width - inset * 2) / content.width,
      (canvas.height - inset * 2) / content.height)
    let size = min(limit, max(min(0.25, limit), scale.isFinite ? scale : 1))
    let halfX = (content.width * size / 2 + inset) / canvas.width
    let halfY = (content.height * size / 2 + inset) / canvas.height
    return Self(center: CGPoint(x: min(1 - halfX, max(halfX, center.x.isFinite ? center.x : 0.5)),
      y: min(1 - halfY, max(halfY, center.y.isFinite ? center.y : 0.5))), scale: size)
  }
}

struct RunPhotoCrop: Equatable {
  var zoom: CGFloat = 1
  /// Fraction of available travel; -1 and +1 align opposite photo edges to the canvas.
  var offset: CGPoint = .zero

  func imageFrame(image: CGSize, canvas: CGSize) -> CGRect {
    let factor = max(canvas.width / image.width, canvas.height / image.height)
      * min(4, max(1, zoom))
    let size = CGSize(width: image.width * factor, height: image.height * factor)
    return CGRect(x: (canvas.width - size.width) / 2
        + max(-1, min(1, offset.x)) * (size.width - canvas.width) / 2,
      y: (canvas.height - size.height) / 2
        + max(-1, min(1, offset.y)) * (size.height - canvas.height) / 2,
      width: size.width, height: size.height)
  }
}

struct RunPhotoComposition {
  static let routeSize = CGSize(width: 170, height: 170)
  static let iconSize = CGSize(width: 64, height: 64)
  var image: UIImage?
  var format: RunPhotoFormat = .original
  var crop = RunPhotoCrop()
  var showsRoute = false
  var showsIcon = false
  var alignment: RunPhotoAlignment = .leading
  var fontStyle: RunPhotoFontStyle = .sport
  var selection: RunPhotoLayer = .stats
  var stats = RunPhotoTransform(center: CGPoint(x: 0.35, y: 0.75), scale: 0.85)
  var route = RunPhotoTransform(center: CGPoint(x: 0.74, y: 0.25), scale: 0.85)
  var icon = RunPhotoTransform(center: CGPoint(x: 1, y: 1), scale: 1)
  var statsSize: CGSize { fontStyle.layout.size }
  var imageSize: CGSize { image?.size ?? CGSize(width: 1080, height: 1440) }
  var outputSize: CGSize { format.outputSize(for: imageSize) }
  // A stable coordinate system shared by all display sizes and the export renderer.
  var canvasSize: CGSize {
    let output = outputSize
    return CGSize(width: 360, height: 360 * output.height / output.width)
  }
  mutating func constrainOverlays() {
    stats = stats.clamped(content: statsSize, canvas: canvasSize)
    route = route.clamped(content: Self.routeSize, canvas: canvasSize)
    icon = icon.clamped(content: Self.iconSize, canvas: canvasSize)
  }
  mutating func resetLayout() {
    let canvas = canvasSize
    let statsScale = min(canvas.width * 0.64 / statsSize.width,
      canvas.height * 0.60 / statsSize.height)
    stats = RunPhotoTransform(center: CGPoint(x: 0, y: 1), scale: statsScale)
      .clamped(content: statsSize, canvas: canvas)
    route = RunPhotoTransform(center: CGPoint(x: 0.78, y: 0.22), scale: 0.80)
      .clamped(content: Self.routeSize, canvas: canvas)
    icon = RunPhotoTransform(center: CGPoint(x: 1, y: 1), scale: 1)
      .clamped(content: Self.iconSize, canvas: canvas)
    crop = RunPhotoCrop()
  }

  var overlayLayers: [RunPhotoLayer] {
    (showsRoute ? [.route] : []) + [.stats] + (showsIcon ? [.icon] : [])
  }
  func transform(_ layer: RunPhotoLayer) -> RunPhotoTransform {
    switch layer {
    case .route: return route
    case .icon: return icon
    case .stats, .photo: return stats
    }
  }
  func contentSize(_ layer: RunPhotoLayer) -> CGSize {
    switch layer {
    case .route: return Self.routeSize
    case .icon: return Self.iconSize
    case .stats, .photo: return statsSize
    }
  }
  mutating func setTransform(_ value: RunPhotoTransform, layer: RunPhotoLayer) {
    let bounded = value.clamped(content: contentSize(layer), canvas: canvasSize)
    switch layer {
    case .stats: stats = bounded
    case .route: route = bounded
    case .icon: icon = bounded
    case .photo: break
    }
  }
  func layer(at point: CGPoint) -> RunPhotoLayer? {
    let layers = overlayLayers
    let ordered = (layers.contains(selection) ? [selection] : [])
      + layers.reversed().filter { $0 != selection }
    return ordered.first { layer in
      let transform = transform(layer), content = contentSize(layer)
      return CGRect(x: transform.center.x * canvasSize.width - content.width * transform.scale / 2,
        y: transform.center.y * canvasSize.height - content.height * transform.scale / 2,
        width: content.width * transform.scale, height: content.height * transform.scale).contains(point)
    }
  }
}
