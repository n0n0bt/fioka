import XCTest
@testable import Fioka

class ScreenshotEditorTests: XCTestCase {
  private var editor: ScreenshotEditor!

  override func setUp() {
    super.setUp()
    let image = NSImage(size: NSSize(width: 400, height: 300))
    image.lockFocus()
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: 400, height: 300).fill()
    image.unlockFocus()
    editor = ScreenshotEditor(image: image)
  }

  private func drag(_ from: CGPoint, _ to: CGPoint, clickCount: Int = 1) {
    editor.pointerDown(at: from, tolerance: 6, clickCount: clickCount)
    editor.pointerDragged(to: to)
    editor.pointerUp()
  }

  private func arrowEnds(_ annotation: Annotation?) -> (CGPoint, CGPoint)? {
    guard case .arrow(let from, let to)? = annotation?.shape else { return nil }
    return (from, to)
  }

  func testDrawingSelectsTheNewAnnotation() {
    editor.tool = .arrow
    drag(CGPoint(x: 10, y: 10), CGPoint(x: 100, y: 10))
    XCTAssertEqual(editor.annotations.count, 1)
    XCTAssertEqual(editor.selectedID, editor.annotations[0].id)
  }

  func testDraggingAnArrowMovesItWithAnyTool() {
    editor.tool = .arrow
    drag(CGPoint(x: 10, y: 10), CGPoint(x: 100, y: 10))
    editor.tool = .pen

    drag(CGPoint(x: 50, y: 11), CGPoint(x: 50, y: 61))

    XCTAssertEqual(editor.annotations.count, 1, "grabbing an arrow must not draw a new stroke")
    let ends = arrowEnds(editor.annotations.first)
    XCTAssertEqual(ends?.0, CGPoint(x: 10, y: 60))
    XCTAssertEqual(ends?.1, CGPoint(x: 100, y: 60))
  }

  func testUndoRevertsAMove() {
    editor.tool = .arrow
    drag(CGPoint(x: 10, y: 10), CGPoint(x: 100, y: 10))
    drag(CGPoint(x: 50, y: 10), CGPoint(x: 50, y: 60))

    editor.undo()
    XCTAssertEqual(arrowEnds(editor.annotations.first)?.0, CGPoint(x: 10, y: 10))
    editor.undo()
    XCTAssertTrue(editor.annotations.isEmpty)
  }

  func testArrowHandleReAimsOnlyThatEnd() {
    editor.tool = .arrow
    drag(CGPoint(x: 10, y: 10), CGPoint(x: 100, y: 10))

    drag(CGPoint(x: 101, y: 11), CGPoint(x: 150, y: 120))

    let ends = arrowEnds(editor.annotations.first)
    XCTAssertEqual(ends?.0, CGPoint(x: 10, y: 10))
    XCTAssertEqual(ends?.1, CGPoint(x: 150, y: 120))
  }

  func testDrawingToolsCanStillDrawInsideABox() {
    editor.tool = .rectangle
    drag(CGPoint(x: 10, y: 10), CGPoint(x: 200, y: 200))
    editor.tool = .arrow
    drag(CGPoint(x: 100, y: 100), CGPoint(x: 150, y: 150))
    XCTAssertEqual(editor.annotations.count, 2)
  }

  func testSelectToolGrabsBoxInterior() {
    editor.tool = .rectangle
    drag(CGPoint(x: 10, y: 10), CGPoint(x: 200, y: 200))
    editor.tool = .select
    drag(CGPoint(x: 100, y: 100), CGPoint(x: 120, y: 100))
    guard case .rectangle(let rect)? = editor.annotations.first?.shape else { return XCTFail() }
    XCTAssertEqual(rect.minX, 30)
  }

  func testColorChangeAppliesToSelection() {
    editor.tool = .arrow
    drag(CGPoint(x: 10, y: 10), CGPoint(x: 100, y: 10))
    editor.setColor(.blue)
    XCTAssertEqual(editor.annotations.first?.color, .blue)
    editor.undo()
    XCTAssertNotEqual(editor.annotations.first?.color, .blue)
  }

  func testDeleteSelected() {
    editor.tool = .arrow
    drag(CGPoint(x: 10, y: 10), CGPoint(x: 100, y: 10))
    editor.deleteSelected()
    XCTAssertTrue(editor.annotations.isEmpty)
  }

  func testDoubleClickEditsTextAndEscapeRestoresIt() {
    editor.tool = .text
    editor.pointerDown(at: CGPoint(x: 20, y: 20), tolerance: 6, clickCount: 1)
    editor.pendingText?.string = "Hello"
    editor.pointerUp()
    editor.commitPendingText()
    XCTAssertEqual(editor.annotations.count, 1)

    editor.tool = .arrow
    editor.pointerDown(at: CGPoint(x: 25, y: 25), tolerance: 6, clickCount: 2)
    editor.pointerUp()
    XCTAssertEqual(editor.pendingText?.string, "Hello")
    XCTAssertTrue(editor.annotations.isEmpty)

    editor.cancelPendingText()
    XCTAssertEqual(editor.annotations.count, 1)
  }

  func testTextCanBeMoved() {
    editor.tool = .text
    editor.pointerDown(at: CGPoint(x: 20, y: 20), tolerance: 6, clickCount: 1)
    editor.pendingText?.string = "Hello"
    editor.pointerUp()
    editor.commitPendingText()

    editor.tool = .select
    drag(CGPoint(x: 25, y: 25), CGPoint(x: 75, y: 45))
    guard case .text(_, let point)? = editor.annotations.first?.shape else { return XCTFail() }
    XCTAssertEqual(point, CGPoint(x: 70, y: 40))
  }

  @MainActor
  func testExportRendersAtCaptureResolution() throws {
    let png = try XCTUnwrap(editor.renderPNG())
    let rep = try XCTUnwrap(NSBitmapImageRep(data: png))
    XCTAssertEqual(CGFloat(rep.pixelsWide), editor.canvasSize.width * editor.pixelScale, accuracy: 1)
  }

  // MARK: - Crop

  func testCropShrinksTheCanvasAndKeepsAnnotationsInPlace() {
    editor.tool = .arrow
    drag(CGPoint(x: 150, y: 150), CGPoint(x: 200, y: 150))
    editor.style.backgroundEnabled = false

    editor.tool = .crop
    drag(CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 250))
    XCTAssertEqual(editor.style.crop, CGRect(x: 100, y: 100, width: 200, height: 150))
    XCTAssertEqual(editor.canvasSize, CGSize(width: 200, height: 150))
    // Annotations keep full-image coordinates; the layout offset maps them.
    XCTAssertEqual(arrowEnds(editor.annotations.first)?.0, CGPoint(x: 150, y: 150))
    XCTAssertEqual(editor.layout.offset, CGPoint(x: -100, y: -100))

    editor.resetCrop()
    XCTAssertEqual(editor.canvasSize, CGSize(width: 400, height: 300))
  }

  func testCropDragIgnoresAnnotationsUnderIt() {
    editor.tool = .rectangle
    drag(CGPoint(x: 10, y: 10), CGPoint(x: 390, y: 290))
    editor.tool = .crop
    drag(CGPoint(x: 10, y: 10), CGPoint(x: 100, y: 100))
    XCTAssertNotNil(editor.style.crop)
    guard case .rectangle(let rect)? = editor.annotations.first?.shape else { return XCTFail() }
    XCTAssertEqual(rect.origin, CGPoint(x: 10, y: 10))
  }

  func testTinyCropIsIgnored() {
    editor.tool = .crop
    drag(CGPoint(x: 10, y: 10), CGPoint(x: 13, y: 12))
    XCTAssertNil(editor.style.crop)
  }

  // MARK: - New tools

  func testCountersNumberThemselves() {
    editor.tool = .counter
    for x in [20, 80, 140] {
      editor.pointerDown(at: CGPoint(x: x, y: 50), tolerance: 6, clickCount: 1)
      editor.pointerUp()
    }
    let numbers: [Int] = editor.annotations.compactMap {
      if case .counter(let number, _) = $0.shape { return number }
      return nil
    }
    XCTAssertEqual(numbers, [1, 2, 3])

    editor.deleteSelected()  // the last one is selected
    editor.pointerDown(at: CGPoint(x: 200, y: 50), tolerance: 6, clickCount: 1)
    editor.pointerUp()
    guard case .counter(let number, _)? = editor.annotations.last?.shape else { return XCTFail() }
    XCTAssertEqual(number, 3)
  }

  func testEllipseIsGrabbedByItsOutlineNotItsCorner() {
    editor.tool = .ellipse
    drag(CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 200))
    editor.selectedID = nil
    editor.tool = .pen
    // Bounding-box corner: outside the ellipse, so this draws instead.
    drag(CGPoint(x: 102, y: 102), CGPoint(x: 110, y: 110))
    XCTAssertEqual(editor.annotations.count, 2)
    // On the outline (leftmost point): grabs and moves it.
    drag(CGPoint(x: 100, y: 150), CGPoint(x: 120, y: 150))
    guard case .ellipse(let rect)? = editor.annotations.first?.shape else { return XCTFail() }
    XCTAssertEqual(rect.minX, 120)
  }

  func testLineEndsCanBeReshaped() {
    editor.tool = .line
    drag(CGPoint(x: 10, y: 10), CGPoint(x: 100, y: 10))
    drag(CGPoint(x: 100, y: 10), CGPoint(x: 100, y: 80))
    guard case .line(let from, let to)? = editor.annotations.first?.shape else { return XCTFail() }
    XCTAssertEqual(from, CGPoint(x: 10, y: 10))
    XCTAssertEqual(to, CGPoint(x: 100, y: 80))
  }

  // MARK: - Canvas

  func testAspectRatioCentresTheImage() {
    editor.style.padding = 50
    editor.style.aspect = .square
    let layout = editor.layout
    XCTAssertEqual(layout.canvasSize.width, layout.canvasSize.height)
    XCTAssertEqual(layout.canvasSize.width, 500)
    XCTAssertEqual(layout.imageFrame.midX, 250)
    XCTAssertEqual(layout.imageFrame.midY, 250)
  }

  /// Renders an export with every new feature to /tmp for eyeballing.
  @MainActor
  func testRenderShowcase() throws {
    let size = NSSize(width: 480, height: 300)
    let image = NSImage(size: size, flipped: true) { rect in
      NSGradient(colors: [.systemTeal, .systemIndigo])?.draw(in: rect, angle: 30)
      ("Account: 4242 4242" as NSString).draw(at: NSPoint(x: 240, y: 230),
        withAttributes: [.font: NSFont.boldSystemFont(ofSize: 22), .foregroundColor: NSColor.white])
      ("Click here" as NSString).draw(at: NSPoint(x: 60, y: 60),
        withAttributes: [.font: NSFont.boldSystemFont(ofSize: 26), .foregroundColor: NSColor.white])
      return true
    }
    let editor = ScreenshotEditor(image: image)
    editor.style.backdropID = Backdrop.blurredID
    editor.style.aspect = .wide
    editor.style.shadowStrength = 80

    func drag(_ tool: AnnotationTool, _ from: CGPoint, _ to: CGPoint) {
      editor.tool = tool
      editor.pointerDown(at: from, tolerance: 6, clickCount: 1)
      editor.pointerDragged(to: to)
      editor.pointerUp()
    }
    drag(.spotlight, CGPoint(x: 40, y: 45), CGPoint(x: 210, y: 105))
    editor.selectedID = nil
    drag(.ellipse, CGPoint(x: 25, y: 30), CGPoint(x: 225, y: 120))
    drag(.blur, CGPoint(x: 230, y: 220), CGPoint(x: 470, y: 270))
    drag(.line, CGPoint(x: 30, y: 160), CGPoint(x: 250, y: 160))
    drag(.counter, CGPoint(x: 300, y: 40), CGPoint(x: 300, y: 40))
    drag(.counter, CGPoint(x: 260, y: 160), CGPoint(x: 260, y: 160))

    let png = try XCTUnwrap(editor.renderPNG())
    try png.write(to: URL(fileURLWithPath: "/tmp/maccy-editor-showcase.png"))
  }
}
