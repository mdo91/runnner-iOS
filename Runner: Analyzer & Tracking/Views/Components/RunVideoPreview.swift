import AVFoundation
import SwiftUI

@MainActor final class RunVideoPlayback: ObservableObject {
  @Published private(set) var player: AVPlayer?
  @Published private(set) var isPlaying = false
  @Published private(set) var time: Double = 0
  private var observer: Any?
  private var endObserver: NSObjectProtocol?
  private var duration: Double = 0

  func replace(with video: RunVideo?) {
    stop()
    guard let video else { return }
    duration = video.duration
    let next = AVPlayer(url: video.url)
    player = next
    observer = next.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1,
      preferredTimescale: 600), queue: .main) { [weak self] time in
      Task { @MainActor in
        guard let self, time.seconds.isFinite else { return }
        self.time = min(self.duration, max(0, time.seconds))
      }
    }
    endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
      object: next.currentItem, queue: .main) { [weak self] _ in
      Task { @MainActor in self?.pause() }
    }
  }
  func toggle() {
    guard let player else { return }
    if isPlaying { pause() }
    else {
      if time >= duration - 0.1 { seek(to: 0) }
      isPlaying = true
      player.play()
    }
  }
  func pause() { player?.pause(); isPlaying = false }
  func seek(to value: Double) {
    time = min(duration, max(0, value))
    player?.seek(to: CMTime(seconds: time, preferredTimescale: 600),
      toleranceBefore: .zero, toleranceAfter: .zero)
  }
  func stop() {
    pause()
    if let observer { player?.removeTimeObserver(observer) }
    if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    observer = nil
    endObserver = nil
    player = nil
    time = 0
    duration = 0
  }
}

/// AVPlayerLayer fits inside the same crop rectangle used by the export transform.
struct RunVideoPreview: UIViewRepresentable {
  let player: AVPlayer
  func makeUIView(context: Context) -> PlayerView { PlayerView() }
  func updateUIView(_ view: PlayerView, context: Context) { view.playerLayer.player = player }
  static func dismantleUIView(_ view: PlayerView, coordinator: ()) { view.playerLayer.player = nil }

  final class PlayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
  }
}
