import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import XCTest
@testable import Fioka

@MainActor
class DropWheelTests: XCTestCase {
  private var directory: URL!

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
  }

  // MARK: - Hit testing

  func testSegmentIndexIsClockwiseFromTwelve() {
    func index(_ dx: CGFloat, _ dy: CGFloat) -> Int? {
      DropWheel.segmentIndex(dx: dx, dy: dy, count: 4, innerRadius: 70, outerRadius: 190)
    }
    XCTAssertEqual(index(0, 120), 0)    // up
    XCTAssertEqual(index(120, 0), 1)    // right
    XCTAssertEqual(index(0, -120), 2)   // down
    XCTAssertEqual(index(-120, 0), 3)   // left
    XCTAssertEqual(index(-30, 120), 0)  // just left of up still wraps to the first slice
  }

  func testSegmentIndexIgnoresHubAndFarAway() {
    XCTAssertNil(DropWheel.segmentIndex(dx: 10, dy: 10, count: 6, innerRadius: 70, outerRadius: 190))
    XCTAssertNil(DropWheel.segmentIndex(dx: 0, dy: 400, count: 6, innerRadius: 70, outerRadius: 190))
  }

  // MARK: - Segments

  func testFormatsSkipTheSourceFormat() throws {
    let png = try makeImage(named: "a.png", type: .png)
    let titles = WheelSegments.segments(for: .formats, urls: [png]).map(\.title)
    XCTAssertFalse(titles.contains("PNG"))
    XCTAssertTrue(titles.contains("JPEG"))
    XCTAssertLessThanOrEqual(titles.count, 8)
  }

  func testUnknownFilesGetOnlyActions() throws {
    let text = directory.appendingPathComponent("notes.xyz")
    try Data("hi".utf8).write(to: text)
    XCTAssertTrue(WheelSegments.segments(for: .formats, urls: [text]).isEmpty)
    XCTAssertTrue(WheelSegments.segments(for: .tools, urls: [text]).isEmpty)
    XCTAssertFalse(WheelSegments.segments(for: .actions, urls: [text]).isEmpty)
  }

  // MARK: - Conversion

  func testConvertWritesBesideSourceWithoutOverwriting() throws {
    let png = try makeImage(named: "photo.png", type: .png)
    let first = try ImageConverter.convertFile(png, to: .jpeg)
    let second = try ImageConverter.convertFile(png, to: .jpeg)

    XCTAssertEqual(first.lastPathComponent, "photo.jpeg")
    XCTAssertEqual(second.lastPathComponent, "photo 2.jpeg")
    XCTAssertEqual(first.deletingLastPathComponent().standardizedFileURL, directory.standardizedFileURL)
    let source = try XCTUnwrap(CGImageSourceCreateWithURL(first as CFURL, nil))
    XCTAssertEqual(CGImageSourceGetType(source) as String?, UTType.jpeg.identifier)
  }

  func testOrientationIsApplied() throws {
    // 40×20 pixels stored with orientation 6 (rotate 90° CW) must come out 20×40.
    let url = try makeImage(named: "rotated.jpeg", type: .jpeg, orientation: 6)
    let output = try ImageConverter.convertFile(url, to: .png)
    let source = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
    let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    XCTAssertEqual(image.width, 20)
    XCTAssertEqual(image.height, 40)
  }

  // MARK: - Rendering

  /// Renders each wheel to /tmp for eyeballing; asserts only that it draws.
  func testRenderWheels() throws {
    let png = try makeImage(named: "a.png", type: .png)
    let cases: [(String, DropWheel.Mode, URL)] = [
      ("formats", .formats, png), ("tools", .tools, png), ("actions", .actions, png),
      ("video", .formats, URL(fileURLWithPath: "/tmp/a.mov")),
      ("pdf-tools", .tools, URL(fileURLWithPath: "/tmp/a.pdf")),
      ("subtitles", .formats, URL(fileURLWithPath: "/tmp/a.srt")),
      ("document-tools", .tools, URL(fileURLWithPath: "/tmp/a.docx"))
    ]
    for (name, mode, url) in cases {
      let wheel = DropWheel()
      wheel.segments = WheelSegments.segments(for: mode, urls: [url])
      wheel.hovered = 0
      wheel.isVisible = true
      let renderer = ImageRenderer(content: DropWheelView(wheel: wheel).background(Color(white: 0.6)))
      renderer.scale = 2
      let image = try XCTUnwrap(renderer.nsImage)
      let rep = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
      try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/maccy-wheel-\(name).png"))
    }
  }

  // MARK: - Helpers

  private func makeImage(named name: String, type: UTType, orientation: Int? = nil) throws -> URL {
    let context = CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(.init(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
    let url = directory.appendingPathComponent(name)
    let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
    let properties = orientation.map { [kCGImagePropertyOrientation: $0] as CFDictionary }
    CGImageDestinationAddImage(destination, context.makeImage()!, properties)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    return url
  }
}
