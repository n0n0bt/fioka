import AppKit
import AVFoundation
import PDFKit
import UniformTypeIdentifiers
import XCTest
@testable import Fioka

/// Runs each converter on a real file it generates, then checks the output
/// with the system's own readers.
@MainActor
class ConverterTests: XCTestCase {
  private var directory: URL!

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
  }

  func testFileKinds() {
    let kinds: [(String, FileKind)] = [
      ("a.png", .image), ("a.heic", .image), ("a.mov", .video), ("a.mp4", .video),
      ("a.mp3", .audio), ("a.wav", .audio), ("a.pdf", .pdf), ("a.docx", .document),
      ("a.txt", .document), ("a.srt", .subtitle), ("a.vtt", .subtitle), ("a.zip", .archive),
      ("a.xyz", .other)
    ]
    for (name, kind) in kinds {
      XCTAssertEqual(FileKind(URL(fileURLWithPath: "/tmp/\(name)")), kind, name)
    }
  }

  // MARK: - Images

  func testImageToPDF() throws {
    let png = try makePNG()
    let pdf = try ImageConverter.convertFile(png, to: .pdf)
    let document = try XCTUnwrap(PDFDocument(url: pdf))
    XCTAssertEqual(document.pageCount, 1)
  }

  // MARK: - Audio

  func testAudioFormats() async throws {
    let wav = try makeWAV()
    for format in AudioFormat.allCases where format != .wav {
      let output = try await MediaConverter.convertAudio(wav, to: format)
      let file = try AVAudioFile(forReading: output)
      XCTAssertGreaterThan(file.length, 0, format.title)
    }
  }

  func testAudioTools() async throws {
    let wav = try makeWAV(amplitude: 0.25)
    let mono = try await MediaConverter.mono(wav)
    XCTAssertEqual(try AVAudioFile(forReading: mono).fileFormat.channelCount, 1)

    let normalized = try await MediaConverter.normalize(wav)
    XCTAssertGreaterThan(try peak(of: normalized), 0.8)

    let compressed = try await MediaConverter.compressAudio(wav)
    XCTAssertEqual(compressed.pathExtension, "m4a")
  }

  // MARK: - Video

  func testVideoConversions() async throws {
    let mov = try await makeMovie()

    let mp4 = try await MediaConverter.convertVideo(mov, to: .mp4)
    let duration = try await AVURLAsset(url: mp4).load(.duration).seconds
    XCTAssertEqual(duration, 1, accuracy: 0.2)

    let gif = try await MediaConverter.gif(mov)
    let source = try XCTUnwrap(CGImageSourceCreateWithURL(gif as CFURL, nil))
    XCTAssertGreaterThan(CGImageSourceGetCount(source), 5)

    let frame = try await MediaConverter.frame(mov)
    XCTAssertNotNil(NSImage(contentsOf: frame))

    let muted = try await MediaConverter.mute(mov)
    let audio = try await AVURLAsset(url: muted).loadTracks(withMediaType: .audio)
    XCTAssertTrue(audio.isEmpty)
  }

  // MARK: - PDF

  func testPDFTools() throws {
    let pdf = try makePDF(pages: 3)

    let images = try DocumentConverter.pdfToImages(pdf, as: .png)
    XCTAssertEqual(images.map(\.lastPathComponent), ["doc 1.png", "doc 2.png", "doc 3.png"])

    let pages = try DocumentConverter.split(pdf)
    XCTAssertEqual(pages.count, 3)

    let merged = try DocumentConverter.merge([pdf, pdf])
    XCTAssertEqual(PDFDocument(url: merged)?.pageCount, 6)

    let rotated = try DocumentConverter.rotate(pdf)
    XCTAssertEqual(PDFDocument(url: rotated)?.page(at: 0)?.rotation, 90)

    let compressed = try DocumentConverter.compressPDF(pdf)
    XCTAssertEqual(PDFDocument(url: compressed)?.pageCount, 3)
  }

  func testMergeImagesAndPDFs() throws {
    let pdf = try makePDF(pages: 2)
    let png = try makePNG()
    let merged = try DocumentConverter.merge([png, pdf, png])
    XCTAssertEqual(merged.lastPathComponent, "picture merged.pdf")
    XCTAssertEqual(PDFDocument(url: merged)?.pageCount, 4)
  }

  func testMultipleImagesOfferCombine() {
    let images = ["a.png", "b.jpg"].map { URL(fileURLWithPath: "/tmp/\($0)") }
    XCTAssertTrue(WheelSegments.segments(for: .tools, urls: images).map(\.title).contains("Combine"))
    XCTAssertFalse(WheelSegments.segments(for: .tools, urls: [images[0]]).map(\.title).contains("Combine"))

    let mixed = [URL(fileURLWithPath: "/tmp/a.pdf"), images[0]]
    XCTAssertTrue(WheelSegments.segments(for: .tools, urls: mixed).map(\.title).contains("Merge"))
  }

  // MARK: - Documents

  func testDocumentFormats() throws {
    let rtf = directory.appendingPathComponent("letter.rtf")
    let text = NSAttributedString(string: "Hello from a letter", attributes: [.font: NSFont.boldSystemFont(ofSize: 14)])
    try text.data(from: NSRange(location: 0, length: text.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
      .write(to: rtf)

    for format in DocumentFormat.allCases where format != .rtf {
      let output = try DocumentConverter.convertDocument(rtf, to: format)
      if format == .pdf {
        XCTAssertTrue(PDFDocument(url: output)?.string?.contains("Hello from a letter") ?? false)
      } else {
        XCTAssertTrue(try DocumentConverter.readDocument(output).string.contains("Hello from a letter"), format.title)
      }
    }
  }

  // MARK: - Subtitles

  func testSubtitleRoundTrip() throws {
    let srt = directory.appendingPathComponent("movie.srt")
    try """
    1
    00:00:01,500 --> 00:00:03,000
    <i>Hello</i> there

    2
    00:01:02,000 --> 00:01:04,250
    Second line
    """.write(to: srt, atomically: true, encoding: .utf8)

    let vtt = try DocumentConverter.convertSubtitles(srt, to: .vtt)
    let vttText = try String(contentsOf: vtt, encoding: .utf8)
    XCTAssertTrue(vttText.hasPrefix("WEBVTT"))
    XCTAssertTrue(vttText.contains("00:01:02.000 --> 00:01:04.250"))

    let back = DocumentConverter.parseCues(vttText)
    XCTAssertEqual(back, DocumentConverter.parseCues(try String(contentsOf: srt, encoding: .utf8)))

    let txt = try DocumentConverter.convertSubtitles(srt, to: .txt)
    XCTAssertEqual(try String(contentsOf: txt, encoding: .utf8), "Hello there\nSecond line\n")
  }

  // MARK: - Archives

  func testZipAndExtract() async throws {
    let file = directory.appendingPathComponent("notes.txt")
    try "zip me".write(to: file, atomically: true, encoding: .utf8)

    let zip = try await DocumentConverter.zip([file])
    XCTAssertEqual(zip.lastPathComponent, "notes.zip")

    let folder = try await DocumentConverter.extract(zip)
    let extracted = folder.appendingPathComponent("notes.txt")
    XCTAssertEqual(try String(contentsOf: extracted, encoding: .utf8), "zip me")
  }

  // MARK: - Wheels

  func testEveryKindHasAWheel() throws {
    let names = ["a.png", "a.mov", "a.wav", "a.pdf", "a.docx", "a.srt", "a.zip"]
    for name in names {
      let url = URL(fileURLWithPath: "/tmp/\(name)")
      XCTAssertFalse(WheelSegments.segments(for: .formats, urls: [url]).isEmpty, name)
      XCTAssertLessThanOrEqual(WheelSegments.segments(for: .formats, urls: [url]).count, 8, name)
      XCTAssertLessThanOrEqual(WheelSegments.segments(for: .tools, urls: [url, url]).count, 8, name)
    }
  }

  // MARK: - Fixtures

  private func makePNG() throws -> URL {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 40, pixelsHigh: 20, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let url = directory.appendingPathComponent("picture.png")
    try rep.representation(using: .png, properties: [:])!.write(to: url)
    return url
  }

  /// One second of a 440 Hz stereo tone.
  private func makeWAV(amplitude: Float = 0.5) throws -> URL {
    let url = directory.appendingPathComponent("tone.wav")
    let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100)!
    buffer.frameLength = 44_100
    for channel in 0..<2 {
      for frame in 0..<44_100 {
        buffer.floatChannelData![channel][frame] = amplitude * sin(2 * .pi * 440 * Float(frame) / 44_100)
      }
    }
    let settings: [String: Any] = [
      AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 2,
      AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false
    ]
    let file = try AVAudioFile(forWriting: url, settings: settings)
    try file.write(from: buffer)
    return url
  }

  private func peak(of url: URL) throws -> Float {
    let file = try AVAudioFile(forReading: url)
    let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
    try file.read(into: buffer)
    var peak: Float = 0
    for frame in 0..<Int(buffer.frameLength) {
      peak = max(peak, abs(buffer.floatChannelData![0][frame]))
    }
    return peak
  }

  /// One second of 64×64 H.264 at 10 fps.
  private func makeMovie() async throws -> URL {
    let url = directory.appendingPathComponent("clip.mov")
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
      AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64
    ])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
      kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 64
    ])
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)

    for index in 0..<10 {
      while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
      var buffer: CVPixelBuffer?
      CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
      CVPixelBufferLockBaseAddress(buffer!, [])
      memset(CVPixelBufferGetBaseAddress(buffer!), Int32(index * 25), CVPixelBufferGetDataSize(buffer!))
      CVPixelBufferUnlockBaseAddress(buffer!, [])
      adaptor.append(buffer!, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: 10))
    }
    input.markAsFinished()
    writer.endSession(atSourceTime: CMTime(value: 10, timescale: 10))
    await writer.finishWriting()
    XCTAssertEqual(writer.status, .completed, writer.error?.localizedDescription ?? "")
    return url
  }

  private func makePDF(pages: Int) throws -> URL {
    let document = PDFDocument()
    let image = NSImage(size: NSSize(width: 200, height: 300), flipped: false) { rect in
      NSColor.white.setFill()
      rect.fill()
      ("Page" as NSString).draw(at: NSPoint(x: 20, y: 150), withAttributes: [.font: NSFont.systemFont(ofSize: 24)])
      return true
    }
    for index in 0..<pages {
      document.insert(PDFPage(image: image)!, at: index)
    }
    let url = directory.appendingPathComponent("doc.pdf")
    XCTAssertTrue(document.write(to: url))
    return url
  }
}
