#if DEBUG
import AVFoundation

/// A real, tiny moving clip keeps simulator tests independent of the user's library.
enum RunVideoFixture {
  static func create(size: CGSize = CGSize(width: 320, height: 480),
    transform: CGAffineTransform = .identity, includesAudio: Bool = true) async throws -> URL {
    let url = try RunVideoIO.temporaryFile(named: "Fixture.mov")
    do {
      let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
      defer { if writer.status == .writing { writer.cancelWriting() } }
      let location = AVMutableMetadataItem()
      location.identifier = .quickTimeMetadataLocationISO6709
      location.value = "+41.0000+029.0000/" as NSString
      writer.metadata = [location]
      let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height),
      ])
      input.transform = transform
      let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
        sourcePixelBufferAttributes: [
          kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
          kCVPixelBufferWidthKey as String: Int(size.width),
          kCVPixelBufferHeightKey as String: Int(size.height),
        ])
      writer.add(input)
      let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [
        AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100,
        AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64000,
      ])
      if includesAudio { writer.add(audio) }
      guard writer.startWriting() else { throw writer.error ?? RunVideoError.exportFailed }
      writer.startSession(atSourceTime: .zero)
      // Supply the single audio buffer first so video backpressure cannot wait on it.
      if includesAudio {
        while !audio.isReadyForMoreMediaData {
          if writer.status == .failed { throw writer.error ?? RunVideoError.exportFailed }
          try Task.checkCancellation()
          await Task.yield()
        }
        guard audio.append(try sound()) else { throw writer.error ?? RunVideoError.exportFailed }
        audio.markAsFinished()
      }
      for frame in 0..<16 {
        try Task.checkCancellation()
        while !input.isReadyForMoreMediaData {
          if writer.status == .failed { throw writer.error ?? RunVideoError.exportFailed }
          try Task.checkCancellation()
          await Task.yield()
        }
        var buffer: CVPixelBuffer?
        guard let pool = adaptor.pixelBufferPool,
          CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess,
          let buffer else { throw RunVideoError.exportFailed }
        CVPixelBufferLockBaseAddress(buffer, [])
        let bytes = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        for y in 0..<Int(size.height) {
          for x in 0..<Int(size.width) {
            let index = y * stride + x * 4
            bytes[index] = y < Int(size.height) / 2 ? 0 : 230
            bytes[index + 1] = 0
            bytes[index + 2] = y < Int(size.height) / 2 ? 230 : 0
            bytes[index + 3] = 255
            // A moving green bar makes frozen-frame exports detectable.
            if x >= frame * Int(size.width) / 16 && x < (frame + 1) * Int(size.width) / 16 {
              bytes[index] = 0; bytes[index + 1] = 230; bytes[index + 2] = 0
            }
          }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 8))
        else { throw writer.error ?? RunVideoError.exportFailed }
      }
      input.markAsFinished()
      writer.endSession(atSourceTime: CMTime(seconds: 2, preferredTimescale: 8))
      await writer.finishWriting()
      guard writer.status == .completed else { throw writer.error ?? RunVideoError.exportFailed }
      try Task.checkCancellation()
      return url
    } catch { RunVideoIO.removeFile(url); throw error }
  }

  private static func sound() throws -> CMSampleBuffer {
    let count = 88200
    var samples = (0..<count).map { Int16(sin(Double($0) * 2 * .pi * 440 / 44100) * 4000) }
    var block: CMBlockBuffer?
    guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil,
      blockLength: count * 2, blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
      offsetToData: 0, dataLength: count * 2, flags: 0, blockBufferOut: &block) == noErr,
      let block else { throw RunVideoError.exportFailed }
    let status = samples.withUnsafeMutableBytes {
      CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block,
        offsetIntoDestination: 0, dataLength: $0.count)
    }
    var description = AudioStreamBasicDescription(mSampleRate: 44100,
      mFormatID: kAudioFormatLinearPCM, mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
      mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1,
      mBitsPerChannel: 16, mReserved: 0)
    var format: CMAudioFormatDescription?
    guard status == noErr,
      CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &description,
        layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil,
        extensions: nil, formatDescriptionOut: &format) == noErr,
      let format else { throw RunVideoError.exportFailed }
    var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 44100),
      presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
    var sample: CMSampleBuffer?
    guard CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block,
      formatDescription: format, sampleCount: count, sampleTimingEntryCount: 1,
      sampleTimingArray: &timing, sampleSizeEntryCount: 0, sampleSizeArray: nil,
      sampleBufferOut: &sample) == noErr, let sample else { throw RunVideoError.exportFailed }
    return sample
  }
}
#endif
