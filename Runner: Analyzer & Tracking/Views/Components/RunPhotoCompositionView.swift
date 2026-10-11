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
          .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
          .frame(width: 170, height: 170)
          .shadow(color: .black.opacity(0.7), radius: 2, y: 1)
          .scaleEffect(composition.route.scale)
          .position(x: composition.route.center.x * canvas.width,
            y: composition.route.center.y * canvas.height)
          .accessibilityHidden(true)
      }
      RunPhotoStatsView(stats: stats)
        .scaleEffect(composition.stats.scale)
        .position(x: composition.stats.center.x * canvas.width,
          y: composition.stats.center.y * canvas.height)
        .accessibilityHidden(true)
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
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      metric("Distance", value: stats.distance)
      metric("pace", value: stats.pace)
      metric("Time", value: stats.time)
      HStack(spacing: 0) {
        Text("The ").foregroundStyle(.white)
        Text("Runner").foregroundStyle(Color(red: 215 / 255, green: 1, blue: 0))
      }
        .font(.system(size: 32, weight: .heavy).width(.condensed))
        .frame(height: 40, alignment: .leading).padding(.top, 8)
    }
    .frame(width: RunPhotoComposition.statsSize.width,
      height: RunPhotoComposition.statsSize.height, alignment: .topLeading)
    .foregroundStyle(.white)
    .shadow(color: .black.opacity(0.75), radius: 2, y: 1)
  }
  private func metric(_ title: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(title).font(.system(size: 13, weight: .medium))
        .frame(height: 18, alignment: .leading)
      Text(value).font(.system(size: 36, weight: .heavy).width(.condensed)).monospacedDigit()
        .lineLimit(1).minimumScaleFactor(0.5)
        .frame(width: 260, height: 44, alignment: .leading)
    }
  }
}
