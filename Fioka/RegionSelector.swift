import AppKit

/// Full-screen overlay that lets the user drag out a rectangle, the way
/// Screenshot.app does. Reports the selection in AppKit screen coordinates
/// (bottom-left origin), or nil if cancelled.
@MainActor
final class RegionSelector {
  static let shared = RegionSelector()

  private var window: NSWindow?
  private var completion: ((CGRect?) -> Void)?
  private var previousApp: NSRunningApplication?

  var isActive: Bool { window != nil }

  func begin(_ completion: @escaping (CGRect?) -> Void) {
    guard window == nil else { return }
    self.completion = completion
    // Showing the overlay activates this app, so remember who to hand focus
    // back to once the selection is done.
    previousApp = NSWorkspace.shared.frontmostApplication

    // One window spanning every display, so a drag can cross screen edges.
    let unionFrame = NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
    guard !unionFrame.isNull else {
      finish(nil)
      return
    }

    let panel = RegionSelectionPanel(
      contentRect: unionFrame,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.level = .screenSaver
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = false
    panel.ignoresMouseEvents = false
    panel.acceptsMouseMovedEvents = true
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

    let view = RegionSelectionView(frame: CGRect(origin: .zero, size: unionFrame.size))
    view.onFinish = { [weak self] localRect in
      guard let self else { return }
      guard let localRect else {
        self.finish(nil)
        return
      }
      // Local view coordinates -> global screen coordinates.
      let global = localRect.offsetBy(dx: unionFrame.minX, dy: unionFrame.minY)
      self.finish(global)
    }

    panel.contentView = view
    window = panel

    panel.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    panel.makeFirstResponder(view)
    NSCursor.crosshair.push()
  }

  private func finish(_ rect: CGRect?) {
    NSCursor.pop()
    window?.orderOut(nil)
    window = nil

    // Hand focus back before the caller does anything with the result.
    previousApp?.activate()
    previousApp = nil

    let completion = self.completion
    self.completion = nil
    completion?(rect)
  }
}

/// Borderless windows return false from canBecomeKey, which would leave the
/// selection view unable to receive the Escape key.
private final class RegionSelectionPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var acceptsFirstResponder: Bool { true }
}

/// Dims the screen, punches a clear hole where the drag is, and reports the
/// rectangle on mouse-up. Escape or right-click cancels.
private final class RegionSelectionView: NSView {
  var onFinish: ((CGRect?) -> Void)?

  private var anchor: NSPoint?
  private var cursor: NSPoint?

  override var acceptsFirstResponder: Bool { true }
  override var isFlipped: Bool { false }

  private var selection: CGRect? {
    guard let anchor, let cursor else { return nil }
    let rect = CGRect(
      x: min(anchor.x, cursor.x),
      y: min(anchor.y, cursor.y),
      width: abs(cursor.x - anchor.x),
      height: abs(cursor.y - anchor.y)
    )
    return rect.width >= 4 && rect.height >= 4 ? rect : nil
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    trackingAreas.forEach(removeTrackingArea)
    addTrackingArea(
      NSTrackingArea(
        rect: bounds,
        options: [.activeAlways, .mouseMoved, .cursorUpdate, .inVisibleRect],
        owner: self
      )
    )
  }

  override func cursorUpdate(with event: NSEvent) {
    NSCursor.crosshair.set()
  }

  override func mouseMoved(with event: NSEvent) {
    NSCursor.crosshair.set()
    // Only while the hint is up, so it can follow the pointer across screens.
    if anchor == nil {
      needsDisplay = true
    }
  }

  override func draw(_ dirtyRect: NSRect) {
    NSColor.black.withAlphaComponent(0.32).setFill()
    dirtyRect.fill()

    guard let selection else {
      drawHint()
      return
    }

    let path = NSBezierPath(
      roundedRect: selection,
      xRadius: cornerRadius(for: selection),
      yRadius: cornerRadius(for: selection)
    )

    // Punch the rounded selection out of the dimming so it reads at full
    // brightness. .copy writes the clear colour rather than blending it.
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current?.compositingOperation = .copy
    NSColor.clear.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Soft accent glow, so the edge reads against light and dark content.
    NSGraphicsContext.saveGraphicsState()
    let glow = NSShadow()
    glow.shadowColor = NSColor.controlAccentColor.withAlphaComponent(0.55)
    glow.shadowBlurRadius = 9
    glow.shadowOffset = .zero
    glow.set()
    NSColor.controlAccentColor.setStroke()
    path.lineWidth = 2
    path.stroke()
    NSGraphicsContext.restoreGraphicsState()

    // Hairline inside the accent stroke keeps it legible on busy content.
    let inner = NSBezierPath(
      roundedRect: selection.insetBy(dx: 1.5, dy: 1.5),
      xRadius: max(0, cornerRadius(for: selection) - 1.5),
      yRadius: max(0, cornerRadius(for: selection) - 1.5)
    )
    NSColor.white.withAlphaComponent(0.55).setStroke()
    inner.lineWidth = 1
    inner.stroke()

    drawSizeLabel(for: selection)
  }

  /// Scales with the selection so a small drag does not turn into a lozenge.
  private func cornerRadius(for rect: CGRect) -> CGFloat {
    min(12, min(rect.width, rect.height) / 3)
  }

  /// Shown until the first drag, so the dimmed screen is self-explanatory.
  private func drawHint() {
    guard anchor == nil else { return }

    let text = "Drag to capture text   ·   Esc to cancel"
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 13, weight: .medium),
      .foregroundColor: NSColor.white.withAlphaComponent(0.92)
    ]
    let size = text.size(withAttributes: attributes)
    let padding: CGFloat = 12

    // Centre it on whichever screen the pointer is on.
    let mouse = NSEvent.mouseLocation
    let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    let centre: NSPoint
    if let screenFrame = screen?.frame, let window {
      let local = NSPoint(
        x: screenFrame.midX - window.frame.minX,
        y: screenFrame.midY - window.frame.minY
      )
      centre = local
    } else {
      centre = NSPoint(x: bounds.midX, y: bounds.midY)
    }

    let box = NSRect(
      x: centre.x - size.width / 2 - padding,
      y: centre.y - size.height / 2 - padding / 2,
      width: size.width + padding * 2,
      height: size.height + padding
    )
    NSColor.black.withAlphaComponent(0.62).setFill()
    NSBezierPath(roundedRect: box, xRadius: box.height / 2, yRadius: box.height / 2).fill()
    text.draw(at: NSPoint(x: box.minX + padding, y: box.minY + padding / 2), withAttributes: attributes)
  }

  private func drawSizeLabel(for rect: CGRect) {
    let text = "\(Int(rect.width)) x \(Int(rect.height))"
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
      .foregroundColor: NSColor.white
    ]
    let size = text.size(withAttributes: attributes)
    let padding: CGFloat = 5

    // Above the selection, or inside it when there is no room above.
    var origin = NSPoint(x: rect.minX, y: rect.maxY + 6)
    if origin.y + size.height + padding * 2 > bounds.maxY {
      origin.y = rect.maxY - size.height - padding * 2 - 6
    }

    let box = NSRect(
      x: origin.x,
      y: origin.y,
      width: size.width + padding * 2,
      height: size.height + padding * 2
    )
    NSColor.black.withAlphaComponent(0.78).setFill()
    NSBezierPath(roundedRect: box, xRadius: box.height / 2, yRadius: box.height / 2).fill()
    text.draw(at: NSPoint(x: box.minX + padding, y: box.minY + padding), withAttributes: attributes)
  }

  override func mouseDown(with event: NSEvent) {
    anchor = convert(event.locationInWindow, from: nil)
    cursor = anchor
    needsDisplay = true
  }

  override func mouseDragged(with event: NSEvent) {
    cursor = convert(event.locationInWindow, from: nil)
    needsDisplay = true
  }

  override func mouseUp(with event: NSEvent) {
    cursor = convert(event.locationInWindow, from: nil)
    onFinish?(selection)
  }

  override func rightMouseDown(with event: NSEvent) {
    onFinish?(nil)
  }

  override func keyDown(with event: NSEvent) {
    if event.keyCode == 53 { // escape
      onFinish?(nil)
    }
  }
}
