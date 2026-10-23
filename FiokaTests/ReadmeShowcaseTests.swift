import AppKit
import SwiftUI
import XCTest
@testable import Fioka

/// Renders the README's showcase images from the real views, with sample
/// content standing in for anyone's actual clipboard. Writes into docs/.
/// Run on its own when the card or editor design changes:
///
///     xcodebuild test ... -only-testing:FiokaTests/ReadmeShowcaseTests
@MainActor
class ReadmeShowcaseTests: XCTestCase {
  private var docs: URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("docs")
  }

  // MARK: - Card bar

  func testRenderCardBar() throws {
    let minute: TimeInterval = 60
    // Newest in the middle, as the drum opens on it.
    let items: [HistoryItemDecorator] = [
      item(text: "Quarterly numbers\nRevenue up 18%\nChurn down to 2.1%", app: "com.apple.Notes", ago: 3 * 3600),
      item(text: "func greet(_ name: String) -> String {\n  let greeting = \"Hello, \\(name)!\"\n  return greeting\n}",
           app: "com.apple.dt.Xcode", ago: 9 * minute),
      item(text: "https://github.com/n0n0bt/fioka", app: "com.apple.Safari", ago: 25 * minute),
      item(text: "Launch checklist\n• Record the demo video\n• Write the release notes\n• Ship Fioka 1.0 on Friday",
           app: "com.apple.Notes", ago: 2 * minute),
      item(image: landscape(), app: "com.apple.Preview", ago: 48 * minute),
      item(text: "#7C86FF", app: "com.microsoft.VSCode", ago: 2 * 3600),
      item(file: URL(fileURLWithPath: "/Users/jane/Documents/Q3 Report.pdf"), app: "com.apple.finder", ago: 5 * 3600)
    ]
    let centre = 3
    // The search pill floats too.
    items[centre].selectionIndex = 0

    let bar = ZStack {
      VStack(spacing: 18) {
        searchPill
        // The same transforms as CardDrumView.
        ZStack {
          ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            let offset = index - centre
            let distance = CGFloat(abs(offset))
            CardItemView(item: item, position: index + 1)
              .scaleEffect(1 - distance * 0.14)
              .rotation3DEffect(.degrees(Double(-offset) * 38), axis: (0, 1, 0), perspective: 0.55)
              .opacity(1 - Double(distance) * 0.22)
              .blur(radius: distance * 0.6)
              .offset(x: CGFloat(offset) * 196)
              .zIndex(-Double(distance))
          }
        }
        .frame(width: 1500, height: CardItemView.height)
      }
      .padding(.top, 16)
      .padding(.bottom, 26)
      .padding(.horizontal, 26)
    }
    .environment(AppState.shared)
    .environment(\.colorScheme, .light)

    // As in the app: the drum over its frosted, brand-tinted backdrop.
    let readme = bar
      .padding(.horizontal, 44)
      .padding(.vertical, 44)
      // Raised so its shelf of light runs under the cards, as in the app,
      // rather than along the bottom of this image's extra margin.
      .background { DrumGlowView(painted: true).padding(.bottom, 46) }
      .fixedSize()
    try write(readme.background { wallpaper.clipped() }, to: "card-bar.png")

    // For the website's hero, which is already pink, violet and cyan: white
    // frost and a deeper shadow instead of the tint, so the drum stands off
    // it. Lots of room around, so both fade to nothing well inside the image
    // and never end in a visible edge.
    // For the website's hero, which is already pink, violet and cyan: no
    // frost and no tint, just a soft shadow pool under the cards that fades
    // to nothing well inside the image, so it never ends in an edge and
    // never covers the hero's ribbed glass in a band.
    let website = bar
      .padding(.horizontal, 160)
      .padding(.vertical, 120)
      .background {
        EllipticalGradient(
          stops: [
            .init(color: Brand.ink.opacity(0.26), location: 0),
            .init(color: Brand.ink.opacity(0.1), location: 0.45),
            .init(color: .clear, location: 0.85)
          ],
          center: .init(x: 0.5, y: 0.62)
        )
      }
      .fixedSize()
    try write(website, to: "assets/card-bar.png")
  }

  /// The website's live drum: each card on its own, newest first, for
  /// docs/drum.js to place and turn. The selection ring is drawn by the page,
  /// so it can move to whichever card is in front. The padding leaves room
  /// for the card's shadow.
  func testRenderDrumCards() throws {
    let minute: TimeInterval = 60
    let items: [HistoryItemDecorator] = [
      item(text: "Launch checklist\n• Record the demo video\n• Write the release notes\n• Ship Fioka 1.0 on Friday",
           app: "com.apple.Notes", ago: 2 * minute),
      item(text: "func greet(_ name: String) -> String {\n  let greeting = \"Hello, \\(name)!\"\n  return greeting\n}",
           app: "com.apple.dt.Xcode", ago: 9 * minute),
      item(text: "https://github.com/n0n0bt/fioka", app: "com.apple.Safari", ago: 25 * minute),
      item(image: landscape(), app: "com.apple.Preview", ago: 48 * minute),
      item(text: "Coffee on Thursday at 10? I'll bring the sketches", app: "com.apple.MobileSMS", ago: 70 * minute),
      item(text: "#7C86FF", app: "com.microsoft.VSCode", ago: 2 * 3600),
      item(text: "Quarterly numbers\nRevenue up 18%\nChurn down to 2.1%", app: "com.apple.Notes", ago: 3 * 3600),
      item(file: URL(fileURLWithPath: "/Users/jane/Documents/Q3 Report.pdf"), app: "com.apple.finder", ago: 5 * 3600)
    ]
    try FileManager.default.createDirectory(at: docs.appendingPathComponent("assets/drum"), withIntermediateDirectories: true)
    for (index, item) in items.enumerated() {
      let card = CardItemView(item: item, position: index + 1)
        .padding(10)
        .environment(AppState.shared)
        .environment(\.colorScheme, .light)
        .fixedSize()
      try write(card, to: "assets/drum/card-\(index).png")
    }
  }

  // MARK: - Drop wheel

  func testRenderWheels() throws {
    let photo = URL(fileURLWithPath: "/tmp/photo.png")
    for (name, mode) in [("wheel-formats.png", DropWheel.Mode.formats), ("wheel-tools.png", .tools), ("wheel-actions.png", .actions)] {
      let wheel = DropWheel()
      wheel.segments = WheelSegments.segments(for: mode, urls: [photo])
      wheel.hovered = 0
      wheel.isVisible = true
      // Padded, so the wheel's soft shadow isn't cut off at the image edge.
      try write(DropWheelView(wheel: wheel).padding(40).background { wallpaper }, to: name)
      // Transparent, for the website, which draws its own background.
      try write(DropWheelView(wheel: wheel).padding(40), to: "assets/\(name)")
    }
  }

  /// A photo for the website's converter demo to drag around.
  func testRenderSamplePhoto() throws {
    let photo = landscape()
    let rep = try XCTUnwrap(photo.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
    let jpeg = try XCTUnwrap(rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]))
    try jpeg.write(to: docs.appendingPathComponent("assets/sample-photo.jpg"))
  }

  // MARK: - Screenshot editor

  func testRenderEditor() throws {
    let screen = try image(of: SettingsWindowMock(), size: CGSize(width: 900, height: 560))
    let editor = ScreenshotEditor(image: screen)
    editor.style.padding = 70
    editor.style.shadowStrength = 60

    // The way you would annotate it for a support ticket: what to change, in
    // order, with personal details hidden.
    drag(editor, .blur, CGPoint(x: 382, y: 188), CGPoint(x: 640, y: 212))
    drag(editor, .blur, CGPoint(x: 382, y: 308), CGPoint(x: 570, y: 332))
    drag(editor, .ellipse, CGPoint(x: 662, y: 404), CGPoint(x: 834, y: 456))
    editor.setColor(Color(hex: 0xFF3B30))
    click(editor, .counter, CGPoint(x: 800, y: 200))
    click(editor, .counter, CGPoint(x: 800, y: 320))
    click(editor, .counter, CGPoint(x: 870, y: 430))
    drag(editor, .arrow, CGPoint(x: 470, y: 505), CGPoint(x: 676, y: 462))
    editor.tool = .text
    editor.pointerDown(at: CGPoint(x: 252, y: 484), tolerance: 6, clickCount: 1)
    editor.pendingText?.string = "Then save"
    editor.pointerUp()
    editor.commitPendingText()
    editor.selectedID = nil

    let png = try XCTUnwrap(editor.renderPNG())
    try png.write(to: docs.appendingPathComponent("editor.png"))
  }

  // MARK: - Helpers

  private func item(text: String? = nil, image: NSImage? = nil, file: URL? = nil,
                    app: String, ago: TimeInterval) -> HistoryItemDecorator {
    var contents: [HistoryItemContent] = []
    if let text {
      contents.append(HistoryItemContent(type: NSPasteboard.PasteboardType.string.rawValue, value: Data(text.utf8)))
    }
    if let image, let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
      contents.append(HistoryItemContent(type: NSPasteboard.PasteboardType.png.rawValue, value: png))
    }
    if let file {
      contents.append(HistoryItemContent(type: NSPasteboard.PasteboardType.fileURL.rawValue, value: file.dataRepresentation))
      contents.append(HistoryItemContent(type: NSPasteboard.PasteboardType.string.rawValue, value: Data(file.lastPathComponent.utf8)))
    }
    let item = HistoryItem()
    Storage.shared.context.insert(item)
    item.contents = contents
    item.application = app
    item.firstCopiedAt = Date(timeIntervalSinceNow: -ago)
    item.lastCopiedAt = Date(timeIntervalSinceNow: -ago)
    item.title = item.generateTitle()
    let decorator = HistoryItemDecorator(item)
    decorator.applicationImage = ApplicationImage(bundleIdentifier: app, image: flatIcon(app))
    if image != nil {
      decorator.thumbnailImage = item.image
    }
    return decorator
  }

  /// The app's icon as a plain bitmap. Current macOS app icons carry
  /// extended-range colour, which makes ImageRenderer tone-map the whole
  /// output darker; on screen they are fine.
  private func flatIcon(_ bundleIdentifier: String) -> NSImage? {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return nil }
    var rect = CGRect(x: 0, y: 0, width: 256, height: 256)
    guard let source = NSWorkspace.shared.icon(forFile: url.path).cgImage(forProposedRect: &rect, context: nil, hints: nil),
          // Redrawn into plain 8-bit sRGB: the icon's extended-range colour is
          // what makes the renderer tone-map everything else down.
          let context = CGContext(data: nil, width: 256, height: 256, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
      return nil
    }
    context.draw(source, in: rect)
    guard let flat = context.makeImage() else { return nil }
    return NSImage(cgImage: flat, size: NSSize(width: 256, height: 256))
  }

  /// A photo-like image for the image card: sky, sun, two ridges.
  private func landscape() -> NSImage {
    NSImage(size: NSSize(width: 1600, height: 1000), flipped: true) { rect in
      NSGradient(colors: [NSColor(red: 0.98, green: 0.62, blue: 0.45, alpha: 1),
                          NSColor(red: 0.55, green: 0.48, blue: 0.85, alpha: 1)])?.draw(in: rect, angle: 90)
      NSColor(red: 1, green: 0.88, blue: 0.62, alpha: 1).setFill()
      NSBezierPath(ovalIn: NSRect(x: 980, y: 300, width: 220, height: 220)).fill()
      for (index, colour) in [NSColor(red: 0.36, green: 0.30, blue: 0.55, alpha: 1),
                              NSColor(red: 0.20, green: 0.17, blue: 0.36, alpha: 1)].enumerated() {
        let ridge = NSBezierPath()
        let base: CGFloat = index == 0 ? 640 : 760
        ridge.move(to: NSPoint(x: 0, y: 1000))
        ridge.line(to: NSPoint(x: 0, y: base))
        for x in stride(from: 0, through: 1600, by: 200) {
          ridge.line(to: NSPoint(x: CGFloat(x), y: base - CGFloat((x / 200 + index) % 3) * 90))
        }
        ridge.line(to: NSPoint(x: 1600, y: 1000))
        ridge.close()
        colour.setFill()
        ridge.fill()
      }
      return true
    }
  }

  private var wallpaper: some View {
    ZStack {
      LinearGradient(colors: [Color(hex: 0xDCE4F7), Color(hex: 0xF3E3EE)], startPoint: .topLeading, endPoint: .bottomTrailing)
      Circle().fill(Color(hex: 0x9FB4FF).opacity(0.55)).frame(width: 700).blur(radius: 120).offset(x: -500, y: -40)
      Circle().fill(Color(hex: 0xFFB3C8).opacity(0.5)).frame(width: 600).blur(radius: 120).offset(x: 520, y: 60)
    }
  }

  private var searchPill: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .medium))
      Text("Type to search…").font(.system(size: 14))
      Spacer()
    }
    .foregroundStyle(Color(white: 0.45))
    .padding(.horizontal, 12)
    .frame(width: 360, height: Popup.cardSearchFieldHeight)
    .background(Capsule().fill(Color(white: 0.5).opacity(0.12)))
  }

  private func drag(_ editor: ScreenshotEditor, _ tool: AnnotationTool, _ from: CGPoint, _ to: CGPoint) {
    editor.tool = tool
    editor.selectedID = nil
    editor.pointerDown(at: from, tolerance: 6, clickCount: 1)
    editor.pointerDragged(to: to)
    editor.pointerUp()
  }

  private func click(_ editor: ScreenshotEditor, _ tool: AnnotationTool, _ point: CGPoint) {
    editor.tool = tool
    editor.selectedID = nil
    editor.pointerDown(at: point, tolerance: 6, clickCount: 1)
    editor.pointerUp()
  }

  private func image(of view: some View, size: CGSize) throws -> NSImage {
    let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
    renderer.scale = 2
    let cgImage = try XCTUnwrap(renderer.cgImage)
    return NSImage(cgImage: cgImage, size: size)
  }

  private func write(_ view: some View, to name: String) throws {
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    let cgImage = try XCTUnwrap(renderer.cgImage)
    let png = try XCTUnwrap(NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]))
    try png.write(to: docs.appendingPathComponent(name))
  }
}

/// A plausible app window to annotate: an account settings page. Laid out on
/// fixed coordinates so the annotations above land on its parts.
private struct SettingsWindowMock: View {
  var body: some View {
    ZStack(alignment: .topLeading) {
      Color.white

      // Title bar.
      HStack(spacing: 8) {
        ForEach([0xFF5F57, 0xFEBC2E, 0x28C840] as [UInt32], id: \.self) { Circle().fill(Color(hex: $0)).frame(width: 12) }
        Spacer()
      }
      .padding(.horizontal, 16)
      .frame(width: 900, height: 40)
      .background(Color(white: 0.96))
      Text("Settings").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
        .frame(width: 900, height: 40)

      // Sidebar.
      VStack(alignment: .leading, spacing: 4) {
        ForEach(["General", "Account", "Billing", "Notifications", "Privacy"], id: \.self) { name in
          Text(name)
            .font(.system(size: 13, weight: name == "Account" ? .semibold : .regular))
            .foregroundStyle(name == "Account" ? .white : Color(white: 0.25))
            .padding(.horizontal, 12)
            .frame(width: 168, height: 30, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 7).fill(name == "Account" ? Color(hex: 0x0A84FF) : .clear))
        }
      }
      .padding(16)
      .frame(width: 200, height: 520, alignment: .topLeading)
      .background(Color(white: 0.975))
      .offset(y: 40)

      Text("Account").font(.system(size: 24, weight: .bold)).offset(x: 240, y: 70)

      row("Full name", "Jane Cooper", y: 140)
      row("Email", "jane.cooper@example.com", y: 200)
      row("Plan", "Pro · Monthly", y: 260)
      row("Card", "Visa •••• 4242      Exp 08/28", y: 320)

      button("Cancel", x: 560, width: 100, filled: false)
      button("Save changes", x: 676, width: 144, filled: true)
    }
    .frame(width: 900, height: 560)
    .environment(\.colorScheme, .light)
  }

  private func row(_ label: String, _ value: String, y: CGFloat) -> some View {
    ZStack(alignment: .topLeading) {
      Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(Color(white: 0.35))
        .frame(width: 120, height: 36, alignment: .leading)
        .offset(x: 240, y: y - 18)
      Text(value).font(.system(size: 14)).foregroundStyle(Color(white: 0.1))
        .padding(.horizontal, 12)
        .frame(width: 400, height: 36, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(white: 0.82)))
        .offset(x: 370, y: y - 18)
    }
  }

  private func button(_ title: String, x: CGFloat, width: CGFloat, filled: Bool) -> some View {
    Text(title).font(.system(size: 14, weight: .semibold))
      .foregroundStyle(filled ? .white : Color(white: 0.2))
      .frame(width: width, height: 36)
      .background(RoundedRectangle(cornerRadius: 8).fill(filled ? Color(hex: 0x0A84FF) : Color(white: 0.93)))
      .offset(x: x, y: 412)
  }
}
