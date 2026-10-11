import SwiftUI

/// Artwork only. Selection handles, gestures, and editor controls never enter an export.
struct RunPhotoCompositionView: View {
  let composition: RunPhotoComposition
  let stats: RunPhotoStats
  let route: RunPhotoRoute

  var body: some View {
    let canvas = composition.canvasSize
    let photo = composition.crop.imageFrame(image: composition.imageSize, canvas: canvas)
    ZStack(alignment: .topLeading) {
      Color.black
      if let image = composition.image {
        Image(uiImage: image).resizable()
          .frame(width: photo.width, height: photo.height)
          .position(x: photo.midX, y: photo.midY)
          .accessibilityHidden(true)
      }
      if composition.showsRoute {
        Path(route.path).applying(CGAffineTransform(scaleX: 170, y: 170))
          .stroke(Color(uiColor: composition.routeColor.uiColor),
            style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
          .frame(width: 170, height: 170)
          .shadow(color: .black.opacity(0.7), radius: 2, y: 1)
          .scaleEffect(composition.route.scale)
          .position(x: composition.route.center.x * canvas.width,
            y: composition.route.center.y * canvas.height)
          .accessibilityHidden(true)
      }
      RunPhotoStatsView(stats: stats, layout: composition.fontStyle.layout,
        alignment: composition.alignment)
        .scaleEffect(composition.stats.scale)
        .position(x: composition.stats.center.x * canvas.width,
          y: composition.stats.center.y * canvas.height)
        .accessibilityHidden(true)
      if composition.showsIcon, let icon = RunPhotoBrandAssets.icon {
        Image(uiImage: icon).resizable().aspectRatio(contentMode: .fit)
          .frame(width: 64, height: 64)
          .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
          .shadow(color: .black.opacity(0.7), radius: 2, y: 1)
          .scaleEffect(composition.icon.scale)
          .position(x: composition.icon.center.x * canvas.width,
            y: composition.icon.center.y * canvas.height)
          .accessibilityHidden(true)
      }
    }
    .frame(width: canvas.width, height: canvas.height).clipped()
    .environment(\.layoutDirection, .leftToRight)
    .environment(\.dynamicTypeSize, .large)
    .environment(\.colorScheme, .dark)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Run photo, Distance \(stats.distance), pace \(stats.pace), Time \(stats.time), The Runner")
    .accessibilityIdentifier("photo.artwork")
  }
}

private struct RunPhotoStatsView: View {
  let stats: RunPhotoStats
  let layout: RunPhotoTextLayout
  let alignment: RunPhotoAlignment
  var body: some View {
    VStack(alignment: alignment.horizontal, spacing: 10) {
      metric("Distance", value: stats.distance)
      metric("pace", value: stats.pace)
      metric("Time", value: stats.time)
      RunPhotoWordmark()
        .frame(width: layout.size.width, height: 40, alignment: alignment.frame)
        .padding(.top, 8)
    }
    .frame(width: layout.size.width, height: layout.size.height, alignment: .top)
    .foregroundStyle(.white)
    .shadow(color: .black.opacity(0.75), radius: 2, y: 1)
  }
  private func metric(_ title: String, value: String) -> some View {
    VStack(alignment: alignment.horizontal, spacing: 0) {
      Text(title).font(Font(layout.labelFont))
        .frame(width: layout.size.width, height: layout.labelHeight, alignment: alignment.frame)
      Text(value).font(Font(layout.valueFont)).monospacedDigit()
        .lineLimit(1).minimumScaleFactor(0.5)
        .frame(width: layout.size.width, height: layout.valueHeight, alignment: alignment.frame)
    }
  }
}

private extension RunPhotoAlignment {
  var horizontal: HorizontalAlignment {
    switch self { case .leading: return .leading; case .center: return .center; case .trailing: return .trailing }
  }
  var frame: Alignment {
    switch self { case .leading: return .leading; case .center: return .center; case .trailing: return .trailing }
  }
}

enum RunPhotoBrandAssets {
  private final class Token: NSObject {}
  static let icon = UIImage(named: "RunPhotoAppIcon", in: Bundle(for: Token.self), compatibleWith: nil)
}

/// A fixed identity, independent of the user's metric font choice.
struct RunPhotoWordmark: View {
  private let font = UIFont.systemFont(ofSize: 32, weight: .heavy, width: .condensed)
  static let yellow = Color(uiColor: RunPhotoRouteColor.runnerYellow.uiColor)
  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 0) {
      Text("The ").foregroundStyle(.white)
      RunPhotoRunnerR().fill(Self.yellow, style: FillStyle(eoFill: true))
        .frame(width: font.capHeight * 0.86, height: font.capHeight)
        .alignmentGuide(.firstTextBaseline) { $0[.bottom] }
      Text("unner").foregroundStyle(Self.yellow)
    }.font(Font(font)).fixedSize()
      .accessibilityElement(children: .ignore).accessibilityLabel("The Runner")
  }
}

/// Angular bowl and split forward leg form an original, readable capital R.
struct RunPhotoRunnerR: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    func polygon(_ points: [CGPoint]) {
      guard let first = points.first else { return }
      path.move(to: first)
      for point in points.dropFirst() { path.addLine(to: point) }
      path.closeSubpath()
    }
    polygon([CGPoint(x: 0, y: 1), CGPoint(x: 0, y: 0), CGPoint(x: 0.68, y: 0),
      CGPoint(x: 0.96, y: 0.16), CGPoint(x: 0.96, y: 0.42), CGPoint(x: 0.68, y: 0.60),
      CGPoint(x: 0.30, y: 0.60), CGPoint(x: 0.30, y: 1)])
    polygon([CGPoint(x: 0.30, y: 0.20), CGPoint(x: 0.64, y: 0.20),
      CGPoint(x: 0.70, y: 0.26), CGPoint(x: 0.70, y: 0.34),
      CGPoint(x: 0.64, y: 0.40), CGPoint(x: 0.30, y: 0.40)])
    polygon([CGPoint(x: 0.49, y: 0.57), CGPoint(x: 0.75, y: 0.49),
      CGPoint(x: 0.85, y: 0.70), CGPoint(x: 0.62, y: 0.80)])
    polygon([CGPoint(x: 0.65, y: 0.86), CGPoint(x: 0.88, y: 0.76),
      CGPoint(x: 1, y: 1), CGPoint(x: 0.72, y: 1)])
    return path.applying(CGAffineTransform(scaleX: rect.width, y: rect.height)
      .concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY)))
  }
}
