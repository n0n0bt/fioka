import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Fioka

@MainActor
class CardActionsTests: XCTestCase {
  func testImageItemOffersConversions() {
    let titles = CardActions.actions(for: imageItem()).map(\.title)
    XCTAssertTrue(titles.contains("JPEG"))
    XCTAssertTrue(titles.contains("PDF"))
    XCTAssertFalse(titles.contains("Copy Path"))
  }

  func testTextItemOffersNothing() {
    let item = HistoryItem()
    Storage.shared.context.insert(item)
    item.contents = [HistoryItemContent(type: NSPasteboard.PasteboardType.string.rawValue, value: Data("hi".utf8))]
    XCTAssertTrue(CardActions.actions(for: item).isEmpty)
  }

  func testExportConvertsAndScales() throws {
    let url = try CardActions.export(imageItem(), as: .jpeg, scale: 0.5, suffix: "test", toPasteboard: false)
    defer { try? FileManager.default.removeItem(at: url) }

    XCTAssertEqual(url.pathExtension, "jpeg")
    let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
    XCTAssertEqual(CGImageSourceGetType(source) as String?, UTType.jpeg.identifier)
    let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    XCTAssertEqual(image.width, 20)
    XCTAssertEqual(image.height, 10)
  }

  func testExportToPDF() throws {
    let url = try CardActions.export(imageItem(), as: .pdf, toPasteboard: false)
    defer { try? FileManager.default.removeItem(at: url) }
    XCTAssertEqual(url.pathExtension, "pdf")
    XCTAssertTrue(try Data(contentsOf: url).starts(with: Data("%PDF".utf8)))
  }

  private func imageItem() -> HistoryItem {
    let rep = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: 40, pixelsHigh: 20, bitsPerSample: 8,
      samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    let item = HistoryItem()
    Storage.shared.context.insert(item)
    item.contents = [
      HistoryItemContent(type: NSPasteboard.PasteboardType.png.rawValue, value: rep.representation(using: .png, properties: [:]))
    ]
    return item
  }
}
