import AVFoundation
import ImageIO
import UniformTypeIdentifiers

/// Audio output formats, all encoded by `afconvert`. macOS has no MP3, Ogg or
/// WMA encoder, so those are not on offer; it decodes them fine as input.
enum AudioFormat: CaseIterable {
  case m4a, wav, aiff, flac, alac

  var title: String {
    switch self {
    case .m4a: return "M4A"
    case .wav: return "WAV"
    case .aiff: return "AIFF"
    case .flac: return "FLAC"
    case .alac: return "ALAC"
    }
  }

  var type: UTType {
    switch self {
    // `.mpeg4Audio` would name files `.mp4`; this type's extension is `.m4a`.
    case .m4a, .alac: return UTType(filenameExtension: "m4a") ?? .mpeg4Audio
    case .wav: return .wav
    case .aiff: return .aiff
    case .flac: return UTType(filenameExtension: "flac") ?? .audio
    }
  }

  /// afconvert's file type and data format.
  var afconvertArguments: [String] {
    switch self {
    case .m4a: return ["-f", "m4af", "-d", "aac", "-b", "256000"]
    case .wav: return ["-f", "WAVE", "-d", "LEI16"]
    case .aiff: return ["-f", "AIFF", "-d", "BEI16"]
    case .flac: return ["-f", "flac", "-d", "flac"]
    case .alac: return ["-f", "m4af", "-d", "alac"]
    }
  }

  /// The format to keep when a tool should not change it. MP3 and the like
  /// cannot be written, so they come back as M4A.
  init(sourceOf url: URL) {
    switch url.pathExtension.lowercased() {
    case "wav", "wave": self = .wav
    case "aif", "aiff": self = .aiff
    case "flac": self = .flac
    default: self = .m4a
    }
  }
}

enum VideoFormat: CaseIterable {
  case mp4, mov, m4v, gif, m4a

  var title: String {
    switch self {
    case .mp4: return "MP4"
    case .mov: return "MOV"
    case .m4v: return "M4V"
    case .gif: return "GIF"
    case .m4a: return "M4A"
    }
  }

  var type: UTType {
    switch self {
    case .mp4: return .mpeg4Movie
    case .mov: return .quickTimeMovie
    case .m4v: return UTType("com.apple.m4v-video") ?? .mpeg4Movie
    case .gif: return .gif
    case .m4a: return UTType(filenameExtension: "m4a") ?? .mpeg4Audio
    }
  }

  var fileType: AVFileType? {
    switch self {
    case .mp4: return .mp4
    case .mov: return .mov
    case .m4v: return .m4v
    case .gif: return nil
    case .m4a: return .m4a
    }
  }
}

/// Video through AVFoundation, audio through `afconvert`. Everything here is
/// async; nothing blocks the main thread while a long file encodes.
enum MediaConverter {
  // MARK: - Audio

  static func convertAudio(
    _ url: URL,
    to format: AudioFormat,
    extraArguments: [String] = [],
    suffix: String? = nil
  ) async throws -> URL {
    let output = ConvertedFile.url(beside: url, suffix: suffix, type: format.type)
    do {
      try await ExternalTool.run("/usr/bin/afconvert", format.afconvertArguments + extraArguments + [url.path, output.path])
    } catch {
      try? FileManager.default.removeItem(at: output)
      throw error
    }
    return output
  }

  static func compressAudio(_ url: URL) async throws -> URL {
    try await convertAudio(url, to: .m4a, extraArguments: ["-b", "96000"], suffix: "compressed")
  }

  static func mono(_ url: URL) async throws -> URL {
    try await convertAudio(url, to: AudioFormat(sourceOf: url), extraArguments: ["-c", "1"], suffix: "mono")
  }

  /// Scales the loudest peak to −1 dBFS. afconvert cannot do this, so the
  /// gain is applied in float PCM and the result re-encoded to the source
  /// format.
  static func normalize(_ url: URL) async throws -> URL {
    let input = try AVAudioFile(forReading: url)
    let format = input.processingFormat
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(input.length)) else {
      throw ConversionError.unreadable
    }
    try input.read(into: buffer)
    guard let channels = buffer.floatChannelData else { throw ConversionError.unreadable }

    let frames = Int(buffer.frameLength)
    var peak: Float = 0
    for channel in 0..<Int(format.channelCount) {
      for frame in 0..<frames {
        peak = max(peak, abs(channels[channel][frame]))
      }
    }
    guard peak > 0 else { throw ConversionError.failed("The audio is silent.") }

    let gain = 0.891 / peak  // −1 dBFS
    for channel in 0..<Int(format.channelCount) {
      for frame in 0..<frames {
        channels[channel][frame] *= gain
      }
    }

    let temporary = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension("caf")
    defer { try? FileManager.default.removeItem(at: temporary) }
    do {
      let output = try AVAudioFile(forWriting: temporary, settings: format.settings)
      try output.write(from: buffer)
    }

    let target = AudioFormat(sourceOf: url)
    let output = ConvertedFile.url(beside: url, suffix: "normalized", type: target.type)
    try await ExternalTool.run("/usr/bin/afconvert", target.afconvertArguments + [temporary.path, output.path])
    return output
  }

  // MARK: - Video

  static func convertVideo(_ url: URL, to format: VideoFormat) async throws -> URL {
    switch format {
    case .gif:
      return try await gif(url)
    case .m4a:
      return try await export(AVURLAsset(url: url), beside: url, preset: AVAssetExportPresetAppleM4A, format: format)
    default:
      return try await export(AVURLAsset(url: url), beside: url, preset: AVAssetExportPresetHighestQuality, format: format)
    }
  }

  /// HEVC at up to 1080p: typically a fraction of a phone video's size.
  static func compressVideo(_ url: URL) async throws -> URL {
    try await export(AVURLAsset(url: url), beside: url, preset: AVAssetExportPresetHEVC1920x1080,
                     format: .mp4, suffix: "compressed")
  }

  static func video720p(_ url: URL) async throws -> URL {
    try await export(AVURLAsset(url: url), beside: url, preset: AVAssetExportPreset1280x720,
                     format: .mp4, suffix: "720p")
  }

  /// Drops every audio track; video is copied, not re-encoded.
  static func mute(_ url: URL) async throws -> URL {
    let asset = AVURLAsset(url: url)
    let duration = try await asset.load(.duration)
    let composition = AVMutableComposition()

    for track in try await asset.loadTracks(withMediaType: .video) {
      let copy = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
      try copy?.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: track, at: .zero)
      copy?.preferredTransform = try await track.load(.preferredTransform)
    }

    let format: VideoFormat = url.pathExtension.lowercased() == "mp4" ? .mp4 : .mov
    return try await export(composition, beside: url, preset: AVAssetExportPresetPassthrough,
                            format: format, suffix: "muted")
  }

  /// A still from one second in (or the middle of a shorter clip), as PNG.
  static func frame(_ url: URL) async throws -> URL {
    let asset = AVURLAsset(url: url)
    let duration = try await asset.load(.duration)
    let time = CMTimeMinimum(CMTime(seconds: 1, preferredTimescale: 600), CMTimeMultiplyByRatio(duration, multiplier: 1, divisor: 2))

    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    let image = try await generator.image(at: time).image

    let output = ConvertedFile.url(beside: url, suffix: "frame", type: .png)
    guard let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil) else {
      throw ConversionError.encodingFailed("PNG")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw ConversionError.encodingFailed("PNG") }
    return output
  }

  /// An animated GIF at up to 480 px and 10 fps, capped at 150 frames so a
  /// long clip gets a lower frame rate instead of an enormous file.
  static func gif(_ url: URL) async throws -> URL {
    let asset = AVURLAsset(url: url)
    let seconds = try await asset.load(.duration).seconds
    guard seconds > 0 else { throw ConversionError.unreadable }

    let count = max(1, min(Int(seconds * 10), 150))
    let delay = seconds / Double(count)
    let times = (0..<count).map { CMTime(seconds: Double($0) * delay, preferredTimescale: 600) }

    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: 480, height: 480)
    generator.requestedTimeToleranceBefore = CMTime(seconds: delay / 2, preferredTimescale: 600)
    generator.requestedTimeToleranceAfter = CMTime(seconds: delay / 2, preferredTimescale: 600)

    let output = ConvertedFile.url(beside: url, type: .gif)
    guard let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.gif.identifier as CFString, count, nil) else {
      throw ConversionError.encodingFailed("GIF")
    }
    let fileProperties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary
    let frameProperties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary
    CGImageDestinationSetProperties(destination, fileProperties)

    for time in times {
      let image = try await generator.image(at: time).image
      CGImageDestinationAddImage(destination, image, frameProperties)
    }
    guard CGImageDestinationFinalize(destination) else {
      try? FileManager.default.removeItem(at: output)
      throw ConversionError.encodingFailed("GIF")
    }
    return output
  }

  private static func export(
    _ asset: AVAsset,
    beside source: URL,
    preset: String,
    format: VideoFormat,
    suffix: String? = nil
  ) async throws -> URL {
    guard let fileType = format.fileType,
          let session = AVAssetExportSession(asset: asset, presetName: preset) else {
      throw ConversionError.encodingFailed(format.title)
    }
    let output = ConvertedFile.url(beside: source, suffix: suffix, type: format.type)
    session.outputURL = output
    session.outputFileType = fileType
    session.shouldOptimizeForNetworkUse = true

    await session.export()
    guard session.status == .completed else {
      try? FileManager.default.removeItem(at: output)
      throw ConversionError.failed(session.error?.localizedDescription ?? "Could not convert to \(format.title).")
    }
    return output
  }
}
