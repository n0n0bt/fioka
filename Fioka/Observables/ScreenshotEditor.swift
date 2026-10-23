import AppKit
import CoreImage
import SwiftUI

enum AnnotationTool: String, CaseIterable, Identifiable {
  case select
  case crop
  case pen
  case line
  case arrow
  case rectangle
  case ellipse
  case highlighter
  case text
  case counter
  case spotlight
  case pixelate
  case blur

  var id: String { rawValue }

  var symbol: String {
    switch self {
    case .select: return "cursorarrow"
    case .crop: return "crop"
    case .pen: return "scribble"
    case .line: return "line.diagonal"
    case .arrow: return "arrow.up.right"
    case .rectangle: return "rectangle"
    case .ellipse: return "circle"
    case .highlighter: return "highlighter"
    case .text: return "textformat"
    case .counter: return "1.circle"
    case .spotlight: return "flashlight.on.fill"
    case .pixelate: return "checkerboard.rectangle"
    case .blur: return "drop.halffull"
    }
  }

  var label: String {
    switch self {
    case .select: return "Select & move"
    case .crop: return "Crop"
    case .pen: return "Draw"
    case .line: return "Line"
    case .arrow: return "Arrow"
    case .rectangle: return "Box"
    case .ellipse: return "Ellipse"
    case .highlighter: return "Highlight"
    case .text: return "Text"
    case .counter: return "Numbered step"
    case .spotlight: return "Spotlight"
    case .pixelate: return "Pixelate"
    case .blur: return "Blur"
    }
  }
}

enum StrokeSize: CaseIterable, Identifiable {
  case small, medium, large

  var id: Self { self }
  var lineWidth: CGFloat { [3, 5, 9][index] }
  var fontSize: CGFloat { [18, 28, 42][index] }
  var counterRadius: CGFloat { [13, 17, 24][index] }
  private var index: Int { Self.allCases.firstIndex(of: self) ?? 1 }
}

/// Everything is stored in image coordinates (points, top-left origin), so
/// annotations stay attached to the screenshot content when the backdrop
/// padding changes or the window is resized.
struct Annotation: Identifiable {
  enum Shape {
    case stroke([CGPoint])
    case highlight([CGPoint])
    case line(from: CGPoint, to: CGPoint)
    case arrow(from: CGPoint, to: CGPoint)
    case rectangle(CGRect)
    case ellipse(CGRect)
    case spotlight(CGRect)
    case pixelate(CGRect)
    case blur(CGRect)
    case text(String, at: CGPoint)
    /// A numbered step marker, centred on the point.
    case counter(Int, at: CGPoint)

    /// Box-shaped annotations share drawing, hit-testing and resize handles.
    var box: CGRect? {
      switch self {
      case .rectangle(let rect), .ellipse(let rect), .spotlight(let rect), .pixelate(let rect), .blur(let rect):
        return rect
      default:
        return nil
      }
    }

    func withBox(_ rect: CGRect) -> Shape {
      switch self {
      case .rectangle: return .rectangle(rect)
      case .ellipse: return .ellipse(rect)
      case .spotlight: return .spotlight(rect)
      case .pixelate: return .pixelate(rect)
      case .blur: return .blur(rect)
      default: return self
      }
    }

    /// Two-point annotations: lines and arrows.
    var endpoints: (CGPoint, CGPoint)? {
      switch self {
      case .line(let from, let to), .arrow(let from, let to): return (from, to)
      default: return nil
      }
    }

    func withEndpoints(_ from: CGPoint, _ to: CGPoint) -> Shape {
      switch self {
      case .line: return .line(from: from, to: to)
      case .arrow: return .arrow(from: from, to: to)
      default: return self
      }
    }
  }

  let id = UUID()
  var shape: Shape
  var color: Color
  var size: StrokeSize

  /// The area the selection outline is drawn around.
  var bounds: CGRect {
    if let box = shape.box { return box }
    if let (from, to) = shape.endpoints { return CGRect(corners: from, to) }
    switch shape {
    case .stroke(let points), .highlight(let points):
      return CGRect(enclosing: points)
    case .text(let string, let point):
      return CGRect(origin: point, size: Self.textSize(string, fontSize: size.fontSize))
    case .counter(_, let center):
      let radius = size.counterRadius
      return CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    default:
      return .null
    }
  }

  func translated(by delta: CGSize) -> Annotation {
    var copy = self
    let move = { (point: CGPoint) in CGPoint(x: point.x + delta.width, y: point.y + delta.height) }
    if let box = shape.box {
      copy.shape = shape.withBox(box.offsetBy(dx: delta.width, dy: delta.height))
    } else if let (from, to) = shape.endpoints {
      copy.shape = shape.withEndpoints(move(from), move(to))
    } else {
      switch shape {
      case .stroke(let points): copy.shape = .stroke(points.map(move))
      case .highlight(let points): copy.shape = .highlight(points.map(move))
      case .text(let string, let point): copy.shape = .text(string, at: move(point))
      case .counter(let number, let point): copy.shape = .counter(number, at: move(point))
      default: break
      }
    }
    return copy
  }

  /// Whether `point` grabs this annotation. `interior` makes the inside of a
  /// box count; drawing tools leave it off so you can still draw inside one.
  func contains(_ point: CGPoint, tolerance: CGFloat, interior: Bool) -> Bool {
    let reach = size.lineWidth / 2 + tolerance
    switch shape {
    case .stroke(let points):
      return points.distance(to: point) <= reach
    case .highlight(let points):
      return points.distance(to: point) <= size.lineWidth * 2 + tolerance
    case .line(let from, let to):
      return [from, to].distance(to: point) <= reach
    case .arrow(let from, let to):
      return [from, to].distance(to: point) <= reach + size.lineWidth
    case .ellipse(let rect):
      if interior, Self.ellipseDistance(point, in: rect) <= 1 { return true }
      // Radial distance from the outline, scaled back into points.
      let radius = min(rect.width, rect.height) / 2
      return abs(Self.ellipseDistance(point, in: rect) - 1) * max(radius, 1) <= reach
    case .rectangle(let rect), .spotlight(let rect), .pixelate(let rect), .blur(let rect):
      if interior, rect.contains(point) { return true }
      let outer = rect.insetBy(dx: -reach, dy: -reach)
      let inner = rect.insetBy(dx: reach, dy: reach)
      return outer.contains(point) && (inner.isNull || !inner.contains(point))
    case .counter(_, let center):
      return hypot(point.x - center.x, point.y - center.y) <= size.counterRadius + tolerance
    case .text:
      return bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
    }
  }

  /// Handles a selected annotation exposes for reshaping.
  /// 1 on the ellipse's outline, less inside, more outside.
  private static func ellipseDistance(_ point: CGPoint, in rect: CGRect) -> CGFloat {
    let rx = max(rect.width / 2, 0.5), ry = max(rect.height / 2, 0.5)
    let dx = (point.x - rect.midX) / rx, dy = (point.y - rect.midY) / ry
    return sqrt(dx * dx + dy * dy)
  }

  var handles: [Handle: CGPoint] {
    if let (from, to) = shape.endpoints {
      return [.arrowStart: from, .arrowEnd: to]
    }
    switch shape {
    case .rectangle(let rect), .ellipse(let rect), .spotlight(let rect), .pixelate(let rect), .blur(let rect):
      return [
        .corner(0): CGPoint(x: rect.minX, y: rect.minY),
        .corner(1): CGPoint(x: rect.maxX, y: rect.minY),
        .corner(2): CGPoint(x: rect.maxX, y: rect.maxY),
        .corner(3): CGPoint(x: rect.minX, y: rect.maxY)
      ]
    default:
      return [:]
    }
  }

  func dragging(_ handle: Handle, to point: CGPoint) -> Annotation {
    var copy = self
    if let (from, to) = shape.endpoints {
      switch handle {
      case .arrowStart: copy.shape = shape.withEndpoints(point, to)
      case .arrowEnd: copy.shape = shape.withEndpoints(from, point)
      default: break
      }
    } else if shape.box != nil, case .corner(let index) = handle,
              let opposite = handles[.corner((index + 2) % 4)] {
      copy.shape = shape.withBox(CGRect(corners: opposite, point))
    }
    return copy
  }

  static func textSize(_ string: String, fontSize: CGFloat) -> CGSize {
    let base = NSFont.systemFont(ofSize: fontSize, weight: .bold)
    let font = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: fontSize) } ?? base
    return (string as NSString).boundingRect(
      with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude),
      options: [.usesLineFragmentOrigin],
      attributes: [.font: font]
    ).size
  }
}

enum Handle: Hashable {
  case arrowStart, arrowEnd
  /// Rect corners, clockwise from top-left, so `(i + 2) % 4` is the opposite.
  case corner(Int)
}

struct Backdrop: Identifiable {
  let id: String
  let colors: [Color]

  static let presets: [Backdrop] = [
    Backdrop(id: "fioka", colors: [Color(hex: 0xFF8DBE), Color(hex: 0x8C8CFF), Color(hex: 0x5BDDEA)]),
    Backdrop(id: "sunset", colors: [Color(hex: 0xFF9A8B), Color(hex: 0xFF6A88), Color(hex: 0xFF99AC)]),
    Backdrop(id: "ocean", colors: [Color(hex: 0x2E3192), Color(hex: 0x1BFFFF)]),
    Backdrop(id: "grape", colors: [Color(hex: 0x8E2DE2), Color(hex: 0x4A00E0)]),
    Backdrop(id: "peach", colors: [Color(hex: 0xFFDEE9), Color(hex: 0xB5FFFC)]),
    Backdrop(id: "lime", colors: [Color(hex: 0xD4FC79), Color(hex: 0x96E6A1)]),
    Backdrop(id: "flame", colors: [Color(hex: 0xF83600), Color(hex: 0xF9D423)]),
    Backdrop(id: "night", colors: [Color(hex: 0x232526), Color(hex: 0x414345)]),
    Backdrop(id: "paper", colors: [Color(hex: 0xF5F5F7), Color(hex: 0xDCDCE2)]),
    Backdrop(id: "mint", colors: [Color(hex: 0x84FAB0), Color(hex: 0x8FD3F4)]),
    Backdrop(id: "candy", colors: [Color(hex: 0xFBC2EB), Color(hex: 0xA6C1EE)]),
    Backdrop(id: "gold", colors: [Color(hex: 0xF6D365), Color(hex: 0xFDA085)]),
    Backdrop(id: "deep", colors: [Color(hex: 0x0F2027), Color(hex: 0x2C5364)])
  ]

  /// Not gradients: a colour you pick, and the screenshot itself blurred.
  static let solidID = "solid"
  static let blurredID = "blurred"
}

/// Fixed canvas proportions for social posts. The image stays centred and the
/// backdrop grows along the short side.
enum CanvasAspect: String, CaseIterable, Identifiable {
  case auto, square, landscape, wide, portrait

  var id: Self { self }

  var title: String {
    switch self {
    case .auto: return "Auto"
    case .square: return "1:1"
    case .landscape: return "4:3"
    case .wide: return "16:9"
    case .portrait: return "9:16"
    }
  }

  var ratio: CGFloat? {
    switch self {
    case .auto: return nil
    case .square: return 1
    case .landscape: return 4.0 / 3
    case .wide: return 16.0 / 9
    case .portrait: return 9.0 / 16
    }
  }
}

/// The look of the exported image, separate from the annotations so views can
/// redraw the (expensive) screenshot layer only when this changes.
struct CompositionStyle: Equatable {
  var backgroundEnabled = true
  var backdropID = Backdrop.presets[0].id
  var solidColor = Color(hex: 0xF2F2F7)
  var padding: CGFloat = 64
  var cornerRadius: CGFloat = 12
  /// 0 turns the shadow off.
  var shadowStrength: CGFloat = 50
  var aspect = CanvasAspect.auto
  /// The part of the screenshot kept, in image coordinates; nil keeps it all.
  var crop: CGRect?

  var backdrop: Backdrop { Backdrop.presets.first { $0.id == backdropID } ?? Backdrop.presets[0] }
}

/// Where everything sits on the canvas. Annotations stay in the coordinates
/// of the full, uncropped screenshot; `offset` maps them onto the canvas, so
/// cropping or changing the padding never moves them relative to the content.
struct CompositionLayout: Equatable {
  /// The part of the screenshot shown, in image coordinates.
  let visible: CGRect
  let canvasSize: CGSize
  /// Where `visible` lands on the canvas.
  let imageFrame: CGRect

  init(imageSize: CGSize, style: CompositionStyle) {
    let full = CGRect(origin: .zero, size: imageSize)
    visible = style.crop?.intersection(full) ?? full

    let padding = style.backgroundEnabled ? style.padding : 0
    var width = visible.width + padding * 2
    var height = visible.height + padding * 2
    if style.backgroundEnabled, let ratio = style.aspect.ratio {
      if width / height < ratio { width = height * ratio } else { height = width / ratio }
    }
    canvasSize = CGSize(width: width, height: height)
    imageFrame = CGRect(
      x: (width - visible.width) / 2,
      y: (height - visible.height) / 2,
      width: visible.width,
      height: visible.height
    )
  }

  /// Image coordinates → canvas coordinates.
  var offset: CGPoint {
    CGPoint(x: imageFrame.minX - visible.minX, y: imageFrame.minY - visible.minY)
  }
}

struct PendingText {
  var position: CGPoint
  var string = ""
  var color: Color
  var size: StrokeSize
  /// Set when re-editing an existing label, so Escape can put it back.
  var original: Annotation?
  var originalIndex: Int?
}

enum PointerTarget {
  case none, annotation, handle, text
}

@Observable
final class ScreenshotEditor {
  let image: NSImage
  /// The same screenshot, pixelated and blurred once up front; those tools
  /// just reveal a clipped region of it.
  let pixelatedImage: NSImage
  let blurredImage: NSImage
  /// A small, heavily blurred copy for the "blurred image" backdrop.
  let backdropImage: NSImage
  /// Backing pixels per point, so the export keeps the capture's resolution.
  let pixelScale: CGFloat

  var annotations: [Annotation] = []
  var draft: Annotation?
  /// The crop rectangle being dragged out, in image coordinates.
  var cropDraft: CGRect?
  var pendingText: PendingText?
  var selectedID: UUID?

  var tool: AnnotationTool = .arrow
  private(set) var color: Color = Color(hex: 0xFF3B30)
  private(set) var size: StrokeSize = .medium
  var style = CompositionStyle()

  @ObservationIgnored private var interaction: Interaction?
  private var undoStack: [[Annotation]] = []
  @ObservationIgnored private var lastCoalesceKey: String?

  private enum Interaction {
    case drawing(start: CGPoint)
    case cropping(start: CGPoint)
    case moving(id: UUID, last: CGPoint, moved: Bool)
    case reshaping(id: UUID, handle: Handle)
  }

  var imageSize: CGSize { image.size }

  var layout: CompositionLayout { CompositionLayout(imageSize: imageSize, style: style) }

  var canvasSize: CGSize { layout.canvasSize }

  var selected: Annotation? {
    annotations.first { $0.id == selectedID }
  }

  var canUndo: Bool { !undoStack.isEmpty || pendingText != nil }

  init(image: NSImage) {
    self.image = image
    let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    pixelScale = cgImage.map { CGFloat($0.width) / max(image.size.width, 1) } ?? 2
    pixelatedImage = Self.pixelate(cgImage, size: image.size) ?? image
    blurredImage = Self.blur(cgImage, size: image.size) ?? image
    backdropImage = Self.backdropBlur(cgImage) ?? image

    // A fixed padding looks lost around a large capture and swamps a small one.
    let shortSide = min(image.size.width, image.size.height)
    style.padding = (shortSide * 0.12).rounded().clamped(to: 32...120)
  }

  // MARK: - Pointer

  /// `tolerance` is in image points, so the view passes a screen distance
  /// divided by its zoom: grabbing feels the same at any window size.
  func pointerDown(at point: CGPoint, tolerance: CGFloat, clickCount: Int) {
    // Clicks inside the open text field belong to the field.
    if let pending = pendingText, pendingBounds(pending).insetBy(dx: -tolerance, dy: -tolerance).contains(point) {
      return
    }
    commitPendingText()

    // Cropping ignores annotations, so a drag that starts on one still crops.
    if tool == .crop {
      selectedID = nil
      cropDraft = CGRect(origin: point, size: .zero)
      interaction = .cropping(start: point)
      return
    }

    if let selected, let handle = handle(of: selected, at: point, tolerance: tolerance) {
      interaction = .reshaping(id: selected.id, handle: handle)
      return
    }

    if let hit = annotation(at: point, tolerance: tolerance) {
      if case .text = hit.shape, clickCount >= 2 || tool == .text {
        editText(hit)
        return
      }
      selectedID = hit.id
      interaction = .moving(id: hit.id, last: point, moved: false)
      return
    }

    selectedID = nil

    let box = CGRect(origin: point, size: .zero)
    switch tool {
    case .select, .crop: return
    case .text: pendingText = PendingText(position: point, color: color, size: size)
    case .counter:
      // Placed on click, then draggable in the same gesture.
      let marker = Annotation(shape: .counter(nextCounter, at: point), color: color, size: size)
      pushUndo()
      annotations.append(marker)
      selectedID = marker.id
      interaction = .moving(id: marker.id, last: point, moved: true)
      return
    case .pen: draft = Annotation(shape: .stroke([point]), color: color, size: size)
    case .highlighter: draft = Annotation(shape: .highlight([point]), color: color, size: size)
    case .line: draft = Annotation(shape: .line(from: point, to: point), color: color, size: size)
    case .arrow: draft = Annotation(shape: .arrow(from: point, to: point), color: color, size: size)
    case .rectangle: draft = Annotation(shape: .rectangle(box), color: color, size: size)
    case .ellipse: draft = Annotation(shape: .ellipse(box), color: color, size: size)
    case .spotlight: draft = Annotation(shape: .spotlight(box), color: color, size: size)
    case .pixelate: draft = Annotation(shape: .pixelate(box), color: color, size: size)
    case .blur: draft = Annotation(shape: .blur(box), color: color, size: size)
    }
    interaction = .drawing(start: point)
  }

  func pointerDragged(to point: CGPoint) {
    switch interaction {
    case .drawing(let start):
      guard var draft else { return }
      if draft.shape.box != nil {
        draft.shape = draft.shape.withBox(CGRect(corners: start, point))
      } else if draft.shape.endpoints != nil {
        draft.shape = draft.shape.withEndpoints(start, point)
      } else {
        switch draft.shape {
        case .stroke(let points): draft.shape = .stroke(points + [point])
        case .highlight(let points): draft.shape = .highlight(points + [point])
        default: break
        }
      }
      self.draft = draft

    case .cropping(let start):
      cropDraft = CGRect(corners: start, point).intersection(layout.visible)

    case .moving(let id, let last, let moved):
      guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
      if !moved { pushUndo() }
      annotations[index] = annotations[index].translated(by: CGSize(width: point.x - last.x, height: point.y - last.y))
      interaction = .moving(id: id, last: point, moved: true)

    case .reshaping(let id, let handle):
      guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
      pushUndo(coalescing: "reshape-\(id)")
      annotations[index] = annotations[index].dragging(handle, to: point)

    case nil:
      break
    }
  }

  func pointerUp() {
    if case .reshaping = interaction {
      lastCoalesceKey = nil
    }
    if case .cropping = interaction {
      if let rect = cropDraft, !rect.isNull, rect.width >= 8, rect.height >= 8 {
        style.crop = rect.integral
      }
      cropDraft = nil
    }
    interaction = nil

    guard let draft else { return }
    self.draft = nil

    if let box = draft.shape.box, box.width < 3 || box.height < 3 { return }
    if let (from, to) = draft.shape.endpoints, hypot(to.x - from.x, to.y - from.y) < 4 { return }
    pushUndo()
    annotations.append(draft)
    // Selected straight away, so a colour or size change applies to it.
    selectedID = draft.id
  }

  func target(at point: CGPoint, tolerance: CGFloat) -> PointerTarget {
    if let selected, handle(of: selected, at: point, tolerance: tolerance) != nil {
      return .handle
    }
    if let hit = annotation(at: point, tolerance: tolerance) {
      if case .text = hit.shape, tool == .text { return .text }
      return .annotation
    }
    return .none
  }

  private func annotation(at point: CGPoint, tolerance: CGFloat) -> Annotation? {
    annotations.reversed().first {
      $0.contains(point, tolerance: tolerance, interior: tool == .select)
    }
  }

  private func handle(of annotation: Annotation, at point: CGPoint, tolerance: CGFloat) -> Handle? {
    annotation.handles.first { hypot($0.value.x - point.x, $0.value.y - point.y) <= tolerance * 1.5 }?.key
  }

  /// One more than the highest step on the canvas, so deleting the last
  /// marker and placing another reuses its number.
  private var nextCounter: Int {
    annotations.reduce(0) { highest, annotation in
      if case .counter(let number, _) = annotation.shape { return max(highest, number) }
      return highest
    } + 1
  }

  func resetCrop() {
    style.crop = nil
  }

  // MARK: - Text

  private func editText(_ annotation: Annotation) {
    guard case .text(let string, let position) = annotation.shape,
          let index = annotations.firstIndex(where: { $0.id == annotation.id }) else { return }
    annotations.remove(at: index)
    selectedID = nil
    pendingText = PendingText(
      position: position,
      string: string,
      color: annotation.color,
      size: annotation.size,
      original: annotation,
      originalIndex: index
    )
  }

  func commitPendingText() {
    guard let pending = pendingText else { return }
    pendingText = nil

    let string = pending.string.trimmingCharacters(in: .whitespacesAndNewlines)
    var before = annotations
    if let original = pending.original {
      before.insert(original, at: min(pending.originalIndex ?? before.count, before.count))
    }
    guard !string.isEmpty || pending.original != nil else { return }

    undoStack.append(before)
    lastCoalesceKey = nil
    guard !string.isEmpty else { return }

    let label = Annotation(shape: .text(string, at: pending.position), color: pending.color, size: pending.size)
    annotations.insert(label, at: min(pending.originalIndex ?? annotations.count, annotations.count))
    selectedID = label.id
  }

  func cancelPendingText() {
    guard let pending = pendingText else { return }
    pendingText = nil
    if let original = pending.original {
      annotations.insert(original, at: min(pending.originalIndex ?? annotations.count, annotations.count))
    }
  }

  private func pendingBounds(_ pending: PendingText) -> CGRect {
    let size = Annotation.textSize(pending.string.isEmpty ? "Type…" : pending.string, fontSize: pending.size.fontSize)
    return CGRect(origin: pending.position, size: size)
  }

  // MARK: - Style

  func setColor(_ newColor: Color) {
    color = newColor
    if pendingText != nil {
      pendingText?.color = newColor
    } else if let index = annotations.firstIndex(where: { $0.id == selectedID }) {
      // The colour well streams changes while you drag; that's one undo step.
      pushUndo(coalescing: "color-\(annotations[index].id)")
      annotations[index].color = newColor
    }
  }

  func setSize(_ newSize: StrokeSize) {
    size = newSize
    if pendingText != nil {
      pendingText?.size = newSize
    } else if let index = annotations.firstIndex(where: { $0.id == selectedID }) {
      pushUndo()
      annotations[index].size = newSize
    }
  }

  // MARK: - Editing

  func deleteSelected() {
    guard let selectedID else { return }
    pushUndo()
    annotations.removeAll { $0.id == selectedID }
    self.selectedID = nil
  }

  func undo() {
    if pendingText != nil {
      cancelPendingText()
      return
    }
    guard let previous = undoStack.popLast() else { return }
    annotations = previous
    lastCoalesceKey = nil
    if selected == nil { selectedID = nil }
  }

  func clear() {
    pendingText = nil
    guard !annotations.isEmpty else { return }
    pushUndo()
    annotations.removeAll()
    selectedID = nil
  }

  /// Snapshot undo: the annotation list is small, so storing whole copies is
  /// simpler than inverting each kind of edit.
  private func pushUndo(coalescing key: String? = nil) {
    if let key, key == lastCoalesceKey { return }
    undoStack.append(annotations)
    lastCoalesceKey = key
  }

  // MARK: - Pixelation and blur

  private static func blur(_ cgImage: CGImage?, size: CGSize) -> NSImage? {
    guard let cgImage else { return nil }
    let input = CIImage(cgImage: cgImage)
    // Strong enough that text cannot be read back, at any capture size.
    let radius = max(CGFloat(cgImage.width) / 90, 10)
    let output = input.clampedToExtent().applyingGaussianBlur(sigma: radius).cropped(to: input.extent)
    guard let result = CIContext().createCGImage(output, from: input.extent) else { return nil }
    return NSImage(cgImage: result, size: size)
  }

  /// Downscaled before blurring: the backdrop is soft anyway, and a heavy
  /// blur at full resolution would take seconds on a large capture.
  private static func backdropBlur(_ cgImage: CGImage?) -> NSImage? {
    guard let cgImage else { return nil }
    let input = CIImage(cgImage: cgImage)
    let scale = min(1, 480 / CGFloat(max(cgImage.width, cgImage.height)))
    let small = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    let output = small.clampedToExtent()
      .applyingGaussianBlur(sigma: 28)
      .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.4])
      .cropped(to: small.extent)
    guard let result = CIContext().createCGImage(output, from: small.extent) else { return nil }
    return NSImage(cgImage: result, size: small.extent.size)
  }

  private static func pixelate(_ cgImage: CGImage?, size: CGSize) -> NSImage? {
    guard let cgImage else { return nil }
    let input = CIImage(cgImage: cgImage)

    // Block size relative to the capture, so text is unreadable at any scale.
    let blocks = max(CGFloat(cgImage.width) / 70, 12)
    let filter = CIFilter(name: "CIPixellate")
    // Clamp first, or the blocks along the edges fade to transparent.
    filter?.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
    filter?.setValue(blocks, forKey: kCIInputScaleKey)
    filter?.setValue(CIVector(x: 0, y: 0), forKey: kCIInputCenterKey)

    guard let output = filter?.outputImage?.cropped(to: input.extent),
          let result = CIContext().createCGImage(output, from: input.extent) else {
      return nil
    }
    return NSImage(cgImage: result, size: size)
  }
}

extension Color {
  init(hex: UInt32) {
    self.init(
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255
    )
  }
}

private extension CGRect {
  init(corners a: CGPoint, _ b: CGPoint) {
    self.init(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
  }

  init(enclosing points: [CGPoint]) {
    let xs = points.map(\.x), ys = points.map(\.y)
    self.init(corners: CGPoint(x: xs.min() ?? 0, y: ys.min() ?? 0), CGPoint(x: xs.max() ?? 0, y: ys.max() ?? 0))
  }
}

private extension Array where Element == CGPoint {
  /// Shortest distance from `point` to the polyline through these points.
  func distance(to point: CGPoint) -> CGFloat {
    guard let first else { return .infinity }
    guard count > 1 else { return hypot(first.x - point.x, first.y - point.y) }
    return zip(self, dropFirst()).map { segmentDistance(point, $0, $1) }.min() ?? .infinity
  }

  private func segmentDistance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
    let dx = b.x - a.x, dy = b.y - a.y
    let lengthSquared = dx * dx + dy * dy
    guard lengthSquared > 0 else { return hypot(p.x - a.x, p.y - a.y) }
    let t = (((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared).clamped(to: 0...1)
    return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
  }
}

private extension Comparable {
  func clamped(to range: ClosedRange<Self>) -> Self {
    min(max(self, range.lowerBound), range.upperBound)
  }
}
