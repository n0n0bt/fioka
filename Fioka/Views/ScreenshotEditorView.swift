import SwiftUI

/// Draws the finished image: backdrop, rounded screenshot, annotations.
///
/// The editor shows it scaled to fit and the export renders it at 1:1, so
/// what you see is exactly what gets copied. Drawing is done at the target
/// size (via `scale`) rather than by `scaleEffect`-ing a full-size canvas,
/// which would rasterise a multi-thousand-pixel layer on every mouse move.
struct ScreenshotComposition: View {
  let image: NSImage
  let pixelatedImage: NSImage
  let blurredImage: NSImage
  let backdropImage: NSImage
  let style: CompositionStyle
  let annotations: [Annotation]
  var scale: CGFloat = 1

  private var layout: CompositionLayout { CompositionLayout(imageSize: image.size, style: style) }

  var body: some View {
    let layout = self.layout
    ZStack(alignment: .topLeading) {
      // Separate layers: the screenshot is only redrawn when the style changes,
      // not on every point of a stroke.
      Canvas { context, _ in
        context.scaleBy(x: scale, y: scale)
        drawBase(in: &context, layout: layout)
      }
      Canvas { context, _ in
        context.scaleBy(x: scale, y: scale)
        // Once cropped, anything outside the kept area is cropped too, rather
        // than floating on the backdrop.
        if style.crop != nil {
          context.clip(to: Path(layout.imageFrame))
        }
        context.translateBy(x: layout.offset.x, y: layout.offset.y)
        drawSpotlights(in: context, layout: layout)
        for annotation in annotations {
          draw(annotation, in: context, layout: layout)
        }
      }
    }
    .frame(width: layout.canvasSize.width * scale, height: layout.canvasSize.height * scale)
  }

  private func imageClip(_ layout: CompositionLayout) -> Path {
    Path(roundedRect: layout.imageFrame, cornerRadius: style.cornerRadius, style: .continuous)
  }

  /// The visible screenshot's rounded outline, in image coordinates.
  private func visibleClip(_ layout: CompositionLayout) -> Path {
    Path(roundedRect: layout.visible, cornerRadius: style.cornerRadius, style: .continuous)
  }

  private func drawBase(in context: inout GraphicsContext, layout: CompositionLayout) {
    let canvas = CGRect(origin: .zero, size: layout.canvasSize)

    if style.backgroundEnabled {
      switch style.backdropID {
      case Backdrop.solidID:
        context.fill(Path(canvas), with: .color(style.solidColor))
      case Backdrop.blurredID:
        context.draw(Image(nsImage: backdropImage), in: Self.aspectFill(backdropImage.size, in: canvas))
      default:
        context.fill(
          Path(canvas),
          with: .linearGradient(
            Gradient(colors: style.backdrop.colors),
            startPoint: .zero,
            endPoint: CGPoint(x: canvas.width, y: canvas.height)
          )
        )
      }

      if style.shadowStrength > 0 {
        var shadow = context
        let strength = style.shadowStrength / 100
        let radius = max(style.padding * 0.3, 8) * (0.5 + strength)
        shadow.addFilter(.shadow(color: .black.opacity(0.6 * strength), radius: radius, y: radius * 0.4))
        shadow.fill(imageClip(layout), with: .color(.black))
      }
    }

    var clipped = context
    clipped.clip(to: imageClip(layout))
    clipped.draw(Image(nsImage: image), in: CGRect(origin: layout.offset, size: image.size))
  }

  /// All spotlights dim one shared layer, so overlapping holes stay clear
  /// instead of darkening each other.
  private func drawSpotlights(in context: GraphicsContext, layout: CompositionLayout) {
    var holes = Path()
    for annotation in annotations {
      if case .spotlight(let rect) = annotation.shape {
        holes.addPath(Path(roundedRect: rect, cornerRadius: 8, style: .continuous))
      }
    }
    guard !holes.isEmpty else { return }
    var dim = context
    dim.clip(to: visibleClip(layout))
    dim.clip(to: holes, options: .inverse)
    dim.fill(Path(layout.visible), with: .color(.black.opacity(0.55)))
  }

  private func draw(_ annotation: Annotation, in context: GraphicsContext, layout: CompositionLayout) {
    var context = context
    let color = annotation.color
    let width = annotation.size.lineWidth
    let round = StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)

    switch annotation.shape {
    case .stroke(let points):
      context.stroke(Self.smoothPath(points), with: .color(color), style: round)

    case .highlight(let points):
      context.blendMode = .multiply
      context.stroke(
        Self.smoothPath(points),
        with: .color(color.opacity(0.4)),
        style: StrokeStyle(lineWidth: width * 4, lineCap: .round, lineJoin: .round)
      )

    case .line(let from, let to):
      var path = Path()
      path.move(to: from)
      path.addLine(to: to)
      context.addFilter(.shadow(color: .black.opacity(0.25), radius: 2, y: 1))
      context.stroke(path, with: .color(color), style: round)

    case .arrow(let from, let to):
      let (shaft, head) = Self.arrowPaths(from: from, to: to, lineWidth: width)
      context.addFilter(.shadow(color: .black.opacity(0.25), radius: 2, y: 1))
      context.stroke(shaft, with: .color(color), style: round)
      context.fill(head, with: .color(color))

    case .rectangle(let rect):
      context.addFilter(.shadow(color: .black.opacity(0.2), radius: 2, y: 1))
      context.stroke(Path(roundedRect: rect, cornerRadius: width * 1.2), with: .color(color), style: round)

    case .ellipse(let rect):
      context.addFilter(.shadow(color: .black.opacity(0.2), radius: 2, y: 1))
      context.stroke(Path(ellipseIn: rect), with: .color(color), style: round)

    case .spotlight:
      // Drawn together in drawSpotlights.
      break

    case .pixelate(let rect), .blur(let rect):
      // Never leaks past the screenshot's own rounded edge.
      context.clip(to: visibleClip(layout))
      context.clip(to: Path(rect))
      let source: NSImage
      if case .blur = annotation.shape { source = blurredImage } else { source = pixelatedImage }
      context.draw(Image(nsImage: source), in: CGRect(origin: .zero, size: image.size))

    case .counter(let number, let center):
      let radius = annotation.size.counterRadius
      let circle = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                          width: radius * 2, height: radius * 2))
      context.addFilter(.shadow(color: .black.opacity(0.3), radius: 2, y: 1))
      context.fill(circle, with: .color(color))
      context.stroke(circle, with: .color(.white), lineWidth: max(1.5, radius * 0.12))
      context.draw(
        Text("\(number)")
          .font(.system(size: radius * 1.15, weight: .bold, design: .rounded))
          .foregroundStyle(Self.contrastingText(on: color)),
        at: center,
        anchor: .center
      )

    case .text(let string, let point):
      context.addFilter(.shadow(color: .black.opacity(0.3), radius: 1.5, y: 1))
      context.draw(
        Text(string)
          .font(.system(size: annotation.size.fontSize, weight: .bold, design: .rounded))
          .foregroundStyle(color),
        at: point,
        anchor: .topLeading
      )
    }
  }

  /// White on dark markers, black on light ones (yellow, white).
  private static func contrastingText(on color: Color) -> Color {
    guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return .white }
    let luminance = 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent
    return luminance > 0.7 ? .black : .white
  }

  static func aspectFill(_ size: CGSize, in rect: CGRect) -> CGRect {
    guard size.width > 0, size.height > 0 else { return rect }
    let scale = max(rect.width / size.width, rect.height / size.height)
    let fitted = CGSize(width: size.width * scale, height: size.height * scale)
    return CGRect(x: rect.midX - fitted.width / 2, y: rect.midY - fitted.height / 2,
                  width: fitted.width, height: fitted.height)
  }

  static func smoothPath(_ points: [CGPoint]) -> Path {
    var path = Path()
    guard let first = points.first else { return path }
    path.move(to: first)
    guard points.count > 1 else {
      // A click without a drag still leaves a dot.
      path.addLine(to: CGPoint(x: first.x + 0.1, y: first.y))
      return path
    }
    for index in 1..<points.count {
      let previous = points[index - 1]
      let midpoint = CGPoint(x: (previous.x + points[index].x) / 2, y: (previous.y + points[index].y) / 2)
      path.addQuadCurve(to: midpoint, control: previous)
    }
    path.addLine(to: points[points.count - 1])
    return path
  }

  static func arrowPaths(from: CGPoint, to: CGPoint, lineWidth: CGFloat) -> (Path, Path) {
    let angle = atan2(to.y - from.y, to.x - from.x)
    let length = hypot(to.x - from.x, to.y - from.y)
    let headLength = min(max(lineWidth * 4, 14), length * 0.6)
    let spread = CGFloat.pi / 7

    let left = CGPoint(x: to.x - headLength * cos(angle - spread), y: to.y - headLength * sin(angle - spread))
    let right = CGPoint(x: to.x - headLength * cos(angle + spread), y: to.y - headLength * sin(angle + spread))
    // Stop the shaft inside the head so its round cap doesn't poke through the tip.
    let shaftEnd = CGPoint(x: to.x - headLength * 0.7 * cos(angle), y: to.y - headLength * 0.7 * sin(angle))

    var shaft = Path()
    shaft.move(to: from)
    shaft.addLine(to: shaftEnd)

    var head = Path()
    head.move(to: to)
    head.addLine(to: left)
    head.addLine(to: right)
    head.closeSubpath()

    return (shaft, head)
  }
}

extension ScreenshotEditor {
  /// Renders the composition at the capture's native resolution.
  @MainActor
  func renderPNG() -> Data? {
    let renderer = ImageRenderer(content: ScreenshotComposition(
      image: image,
      pixelatedImage: pixelatedImage,
      blurredImage: blurredImage,
      backdropImage: backdropImage,
      style: style,
      annotations: annotations
    ))
    renderer.scale = pixelScale

    guard let cgImage = renderer.cgImage else { return nil }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    // Point size, so the PNG carries Retina DPI and pastes at its real size.
    rep.size = canvasSize
    return rep.representation(using: .png, properties: [:])
  }
}

struct ScreenshotEditorView: View {
  @Bindable var editor: ScreenshotEditor
  let onCopy: () -> Void
  let onSave: () -> Void
  let onClose: () -> Void

  @FocusState private var textFocused: Bool
  @State private var pointerIsDown = false

  /// How close, in screen points, the pointer has to be to grab something.
  private static let grabDistance: CGFloat = 7

  private static let swatches: [Color] = [
    Color(hex: 0xFF3B30), Color(hex: 0xFF9500), Color(hex: 0xFFCC00), Color(hex: 0x34C759),
    Color(hex: 0x0A84FF), Color(hex: 0xAF52DE), .black, .white
  ]

  var body: some View {
    HStack(spacing: 0) {
      VStack(spacing: 0) {
        toolbar
        Divider()
        canvasArea
      }
      Divider()
      sidebar
        .frame(width: 236)
    }
    .frame(minWidth: 1080, minHeight: 560)
    // Buttons, toggles and sliders in the brand colour too.
    .tint(Brand.accent)
  }

  // MARK: - Toolbar

  private var toolbar: some View {
    HStack(spacing: 14) {
      HStack(spacing: 2) {
        ForEach(AnnotationTool.allCases) { tool in
          Button {
            editor.commitPendingText()
            editor.tool = tool
          } label: {
            Image(systemName: tool.symbol)
              .font(.system(size: 14, weight: .medium))
              .frame(width: 30, height: 28)
              .background(
                RoundedRectangle(cornerRadius: 6)
                  .fill(editor.tool == tool ? Brand.accent.opacity(0.22) : .clear)
              )
              .foregroundStyle(editor.tool == tool ? Brand.accent : .primary)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .help(tool.label)
        }
      }

      Divider().frame(height: 20)

      HStack(spacing: 6) {
        ForEach(Self.swatches, id: \.self) { swatch in
          Circle()
            .fill(swatch)
            .frame(width: 18, height: 18)
            .overlay(Circle().strokeBorder(.primary.opacity(0.25), lineWidth: 1))
            .overlay(
              Circle()
                .strokeBorder(Brand.accent, lineWidth: 2)
                .padding(-4)
                .opacity(editor.color == swatch ? 1 : 0)
            )
            .onTapGesture { editor.setColor(swatch) }
        }
        ColorPicker("", selection: Binding(get: { editor.color }, set: editor.setColor), supportsOpacity: false)
          .labelsHidden()
          .frame(width: 28)
      }

      Divider().frame(height: 20)

      Picker("", selection: Binding(get: { editor.size }, set: editor.setSize)) {
        Text("S").tag(StrokeSize.small)
        Text("M").tag(StrokeSize.medium)
        Text("L").tag(StrokeSize.large)
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .frame(width: 96)
      .help("Line width / text size")

      Spacer()

      Button(action: editor.undo) {
        Image(systemName: "arrow.uturn.backward")
      }
      .keyboardShortcut("z", modifiers: .command)
      .disabled(!editor.canUndo)
      .help("Undo (⌘Z)")

      Button(action: editor.clear) {
        Image(systemName: "trash")
      }
      .disabled(editor.annotations.isEmpty)
      .help("Remove all annotations")
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
  }

  // MARK: - Canvas

  private var canvasArea: some View {
    GeometryReader { proxy in
      let layout = editor.layout
      let canvas = layout.canvasSize
      let scale = min(1, (proxy.size.width - 48) / canvas.width, (proxy.size.height - 48) / canvas.height)
      let offset = layout.offset

      ZStack(alignment: .topLeading) {
        ScreenshotComposition(
          image: editor.image,
          pixelatedImage: editor.pixelatedImage,
          blurredImage: editor.blurredImage,
          backdropImage: editor.backdropImage,
          style: editor.style,
          annotations: editor.annotations + [editor.draft].compactMap { $0 },
          scale: scale
        )
        .shadow(color: .black.opacity(editor.style.backgroundEnabled ? 0.25 : 0), radius: 12, y: 4)

        if let selected = editor.selected, editor.draft == nil {
          SelectionOverlay(annotation: selected, offset: offset, scale: scale)
            .allowsHitTesting(false)
        }

        if let crop = editor.cropDraft {
          CropOverlay(crop: crop, layout: layout, scale: scale)
            .allowsHitTesting(false)
        }

        if editor.pendingText != nil {
          pendingTextField(scale: scale, offset: offset)
        }
      }
      .frame(width: canvas.width * scale, height: canvas.height * scale, alignment: .topLeading)
      .contentShape(Rectangle())
      .gesture(pointerGesture(scale: scale, offset: offset))
      .onContinuousHover { phase in
        switch phase {
        case .active(let location):
          guard !pointerIsDown else { return }
          let point = CGPoint(x: location.x / scale - offset.x, y: location.y / scale - offset.y)
          cursor(for: editor.target(at: point, tolerance: Self.grabDistance / scale)).set()
        case .ended:
          NSCursor.arrow.set()
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .background(CheckerboardBackground())
    .background(keyCommands)
  }

  private func cursor(for target: PointerTarget) -> NSCursor {
    switch target {
    case .handle: return .pointingHand
    case .annotation: return .openHand
    case .text: return .iBeam
    case .none:
      switch editor.tool {
      case .select: return .arrow
      case .text: return .iBeam
      case .counter: return .pointingHand
      default: return .crosshair
      }
    }
  }

  /// Invisible buttons, purely for their keyboard shortcuts.
  private var keyCommands: some View {
    let canEditSelection = editor.selectedID != nil && editor.pendingText == nil
    return ZStack {
      Button("Delete", action: editor.deleteSelected)
        .keyboardShortcut(canEditSelection ? KeyboardShortcut(.delete, modifiers: []) : nil)
      Button("Delete", action: editor.deleteSelected)
        .keyboardShortcut(canEditSelection ? KeyboardShortcut(.deleteForward, modifiers: []) : nil)
      Button("Deselect") { editor.selectedID = nil }
        .keyboardShortcut(canEditSelection ? .cancelAction : nil)
    }
    .opacity(0)
    .allowsHitTesting(false)
  }

  private func pointerGesture(scale: CGFloat, offset: CGPoint) -> some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { value in
        let point = CGPoint(x: value.location.x / scale - offset.x, y: value.location.y / scale - offset.y)
        if pointerIsDown {
          editor.pointerDragged(to: point)
          return
        }

        pointerIsDown = true
        let start = CGPoint(x: value.startLocation.x / scale - offset.x, y: value.startLocation.y / scale - offset.y)
        editor.pointerDown(
          at: start,
          tolerance: Self.grabDistance / scale,
          clickCount: NSApp.currentEvent?.clickCount ?? 1
        )
        if editor.pendingText != nil {
          // The field only exists after this update lands.
          DispatchQueue.main.async { textFocused = true }
        } else if editor.selectedID != nil {
          NSCursor.closedHand.set()
        }
        if point != start {
          editor.pointerDragged(to: point)
        }
      }
      .onEnded { _ in
        pointerIsDown = false
        editor.pointerUp()
      }
  }

  private func pendingTextField(scale: CGFloat, offset: CGPoint) -> some View {
    let pending = editor.pendingText
    let position = pending?.position ?? .zero
    let text = Binding(
      get: { editor.pendingText?.string ?? "" },
      set: { editor.pendingText?.string = $0 }
    )

    return TextField("Type…", text: text, axis: .vertical)
      .textFieldStyle(.plain)
      .font(.system(size: (pending?.size ?? editor.size).fontSize * scale, weight: .bold, design: .rounded))
      .foregroundStyle(pending?.color ?? editor.color)
      .fixedSize()
      .frame(minWidth: 60 * scale, alignment: .leading)
      .padding(2)
      .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Brand.accent.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [3])))
      .offset(x: (position.x + offset.x) * scale - 2, y: (position.y + offset.y) * scale - 2)
      .focused($textFocused)
      .onAppear { textFocused = true }
      .onSubmit { editor.commitPendingText() }
      .onExitCommand { editor.cancelPendingText() }
  }

  // MARK: - Sidebar

  private var sidebar: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        Toggle("Background", isOn: $editor.style.backgroundEnabled)
          .toggleStyle(.switch)
          .font(.headline)

        Group {
          backdropGrid

          if editor.style.backdropID == Backdrop.solidID {
            ColorPicker("Colour", selection: $editor.style.solidColor, supportsOpacity: false)
          }

          VStack(alignment: .leading, spacing: 6) {
            Text("Size")
            Picker("", selection: $editor.style.aspect) {
              ForEach(CanvasAspect.allCases) { aspect in
                Text(aspect.title).tag(aspect)
              }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
          }

          slider("Padding", value: $editor.style.padding, range: 0...240)
          slider("Shadow", value: $editor.style.shadowStrength, range: 0...100)
        }
        .disabled(!editor.style.backgroundEnabled)
        .opacity(editor.style.backgroundEnabled ? 1 : 0.45)

        Divider()

        slider("Corner radius", value: $editor.style.cornerRadius, range: 0...60)

        if editor.style.crop != nil {
          Button {
            editor.resetCrop()
          } label: {
            Label("Reset crop", systemImage: "arrow.uturn.backward")
              .frame(maxWidth: .infinity)
          }
        }
      }
      .padding(16)
    }
    .safeAreaInset(edge: .bottom) { actions }
  }

  /// Gradients, then a colour of your choice, then the screenshot blurred.
  private var backdropGrid: some View {
    LazyVGrid(columns: Array(repeating: GridItem(.fixed(44), spacing: 8), count: 4), spacing: 8) {
      ForEach(Backdrop.presets) { backdrop in
        backdropTile(id: backdrop.id) {
          LinearGradient(colors: backdrop.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
        }
      }
      backdropTile(id: Backdrop.solidID) {
        ZStack {
          editor.style.solidColor
          Image(systemName: "eyedropper")
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.secondary)
        }
      }
      .help("Solid colour")
      backdropTile(id: Backdrop.blurredID) {
        Image(nsImage: editor.backdropImage)
          .resizable()
          .aspectRatio(contentMode: .fill)
      }
      .help("Blurred screenshot")
    }
  }

  private func backdropTile<Fill: View>(id: String, @ViewBuilder fill: () -> Fill) -> some View {
    fill()
      .frame(width: 44, height: 44)
      .clipShape(RoundedRectangle(cornerRadius: 8))
      .overlay(
        RoundedRectangle(cornerRadius: 8)
          .strokeBorder(Brand.accent, lineWidth: 2.5)
          .opacity(editor.style.backdropID == id ? 1 : 0)
      )
      .contentShape(Rectangle())
      .onTapGesture { editor.style.backdropID = id }
  }

  private var actions: some View {
    VStack(spacing: 10) {
      Button(action: onCopy) {
        Label("Copy", systemImage: "doc.on.doc")
          .frame(maxWidth: .infinity)
      }
      .controlSize(.large)
      .buttonStyle(.borderedProminent)
      .keyboardShortcut("c", modifiers: .command)
      .help("Copy to clipboard and close (⌘C)")

      HStack {
        Button(action: onSave) {
          Text("Save…").frame(maxWidth: .infinity)
        }
        .keyboardShortcut("s", modifiers: .command)

        Button(action: onClose) {
          Text("Discard").frame(maxWidth: .infinity)
        }
        // Escape closes the text field or deselects first, if either is open.
        .keyboardShortcut(editor.pendingText == nil && editor.selectedID == nil ? .cancelAction : nil)
      }
      .controlSize(.large)
    }
    .padding(16)
    .background(.bar)
  }

  private func slider(_ title: String, value: Binding<CGFloat>, range: ClosedRange<CGFloat>) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(title)
        Spacer()
        Text("\(Int(value.wrappedValue))")
          .monospacedDigit()
          .foregroundStyle(.secondary)
      }
      Slider(value: value, in: range)
    }
  }
}

/// Dashed outline and grab handles around the selected annotation. Drawn
/// only in the editor, never into the exported image.
private struct SelectionOverlay: View {
  let annotation: Annotation
  /// Image coordinates → canvas coordinates; see `CompositionLayout.offset`.
  let offset: CGPoint
  let scale: CGFloat

  var body: some View {
    Canvas { context, _ in
      let toScreen = { (point: CGPoint) in
        CGPoint(x: (point.x + offset.x) * scale, y: (point.y + offset.y) * scale)
      }
      let handles = annotation.handles

      if annotation.shape.endpoints != nil {
        // A line or arrow is its own outline; just show its two ends.
      } else {
        let bounds = annotation.bounds
        let rect = CGRect(
          origin: toScreen(bounds.origin),
          size: CGSize(width: bounds.width * scale, height: bounds.height * scale)
        ).insetBy(dx: handles.isEmpty ? -6 : 0, dy: handles.isEmpty ? -6 : 0)
        let outline = Path(roundedRect: rect, cornerRadius: 3)
        context.stroke(outline, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: 2.5))
        context.stroke(outline, with: .color(Brand.accent), style: StrokeStyle(lineWidth: 1.2, dash: [5, 3]))
      }

      for point in handles.values {
        let center = toScreen(point)
        let dot = Path(ellipseIn: CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10))
        context.fill(dot, with: .color(.white))
        context.stroke(dot, with: .color(Brand.accent), lineWidth: 2)
      }
    }
  }
}

/// The crop being dragged out: everything outside it dimmed, a frame around it.
private struct CropOverlay: View {
  let crop: CGRect
  let layout: CompositionLayout
  let scale: CGFloat

  var body: some View {
    Canvas { context, size in
      guard !crop.isNull else { return }
      let rect = CGRect(
        x: (crop.minX + layout.offset.x) * scale,
        y: (crop.minY + layout.offset.y) * scale,
        width: crop.width * scale,
        height: crop.height * scale
      )
      var dim = context
      dim.clip(to: Path(rect), options: .inverse)
      dim.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(0.5)))
      context.stroke(Path(rect), with: .color(.white), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
    }
  }
}

/// The usual transparency checkerboard, so rounded corners and a disabled
/// background read as transparent rather than as grey.
private struct CheckerboardBackground: View {
  var body: some View {
    Canvas { context, size in
      let tile: CGFloat = 10
      context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(nsColor: .windowBackgroundColor)))
      var path = Path()
      for row in 0..<Int(size.height / tile) + 1 {
        for column in 0..<Int(size.width / tile) + 1 where (row + column).isMultiple(of: 2) {
          path.addRect(CGRect(x: CGFloat(column) * tile, y: CGFloat(row) * tile, width: tile, height: tile))
        }
      }
      context.fill(path, with: .color(.primary.opacity(0.04)))
    }
  }
}
