import SwiftUI
import XCTest
@testable import Fioka

class CardDrumTests: XCTestCase {
  func testShortHistoryStaysInALine() {
    // Five cards, the newest at the front: the older ones go right only.
    let offsets = (0..<5).map { CardDrumView.offset(of: $0, from: 0, count: 5) }
    XCTAssertEqual(offsets, [0, 1, 2, 3, nil])
  }

  func testLongHistoryDoesNotWrap() {
    // Opened on the newest of ten: nothing on the left, not the oldest.
    let offsets = (0..<10).map { CardDrumView.offset(of: $0, from: 0, count: 10) }
    XCTAssertEqual(offsets, [0, 1, 2, 3, nil, nil, nil, nil, nil, nil])
  }

  func testPassedCardsFillTheLeft() {
    let offsets = (0..<10).map { CardDrumView.offset(of: $0, from: 2, count: 10) }
    XCTAssertEqual(offsets, [-2, -1, 0, 1, 2, 3, nil, nil, nil, nil])
  }

  /// Renders the real drum, opened on the newest of ten copies.
  @MainActor
  func testRenderOpenedDrum() throws {
    let history = AppState.shared.history
    let saved = history.items
    defer { history.items = saved }
    history.items = (0..<10).map { index in
      let item = HistoryItem()
      Storage.shared.context.insert(item)
      item.contents = [HistoryItemContent(type: NSPasteboard.PasteboardType.string.rawValue, value: Data("Copy \(index)".utf8))]
      item.title = item.generateTitle()
      return HistoryItemDecorator(item)
    }
    AppState.shared.navigator.select(item: history.unpinnedItems.first)
    let view = CardDrumView().environment(AppState.shared).frame(width: 1600)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 1
    let image = try XCTUnwrap(renderer.cgImage)
    let png = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
    try png.write(to: URL(fileURLWithPath: "/tmp/fioka-drum-open.png"))
  }
}
