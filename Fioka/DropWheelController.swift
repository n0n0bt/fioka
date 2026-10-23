import AppKit
import Defaults
import SwiftUI
import UniformTypeIdentifiers

/// A drag-and-tap gesture, system-wide: start dragging files
/// anywhere, tap ⇧ (formats), ⌘ (tools) or ⌃ (actions), and a wheel opens
/// under the cursor. Drop on a slice to run it.
///
/// There is no public "a drag started" notification, so this watches for it:
/// a global mouse-down records the drag pasteboard's change count, and while
/// the button is held a timer polls for a change (a drag began) and for a
/// newly pressed modifier. Polling `NSEvent.modifierFlags` rather than using a
/// flagsChanged monitor, because during another app's drag session those
/// events go to the drag loop, not to monitors.
///
/// Converted files are written beside the originals, where you will look, and
/// also put on the clipboard, so they show up in the card bar.
@MainActor
final class DropWheelController {
  static let shared = DropWheelController()

  private let wheel = DropWheel()
  private var panel: NSPanel?
  private var mouseDownMonitor: Any?
  private var pollTimer: Timer?
  private var baselineChangeCount = 0
  private var previousFlags: NSEvent.ModifierFlags = []

  private static let modifiers: NSEvent.ModifierFlags = [.shift, .command, .control, .option]
  private static let escapeKeyCode: CGKeyCode = 0x35

  func start() {
    guard mouseDownMonitor == nil else { return }
    // Global monitors only see other apps' events, which is what we want:
    // drags inside this app are the card bar's own.
    mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { _ in
      MainActor.assumeIsolated { DropWheelController.shared.mouseDown() }
    }
  }

  // MARK: - Detecting the gesture

  private func mouseDown() {
    guard Defaults[.dropWheelEnabled] else { return }
    baselineChangeCount = NSPasteboard(name: .drag).changeCount
    previousFlags = NSEvent.modifierFlags.intersection(Self.modifiers)
    pollTimer?.invalidate()
    pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { _ in
      MainActor.assumeIsolated { DropWheelController.shared.tick() }
    }
  }

  private func tick() {
    guard NSEvent.pressedMouseButtons & 1 != 0 else {
      pollTimer?.invalidate()
      pollTimer = nil
      // A drop on the wheel hides it itself; this covers a drop anywhere
      // else. The delay lets that drop arrive before the target disappears.
      if wheel.isVisible {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { self.hide() }
      }
      return
    }

    // Esc closes the wheel. Key events go to the dragging app, so read the
    // key's hardware state instead; the drag itself is the source app's to
    // cancel (Finder does, on the same key). Tapping a modifier reopens it.
    if wheel.isVisible, CGEventSource.keyState(.combinedSessionState, key: Self.escapeKeyCode) {
      hide()
      return
    }

    let flags = NSEvent.modifierFlags.intersection(Self.modifiers)
    defer { previousFlags = flags }
    // Only a key going down counts: the wheel stays open after it is released.
    guard !flags.subtracting(previousFlags).isEmpty,
          NSPasteboard(name: .drag).changeCount != baselineChangeCount else {
      return
    }

    let mode: DropWheel.Mode
    switch flags {
    case [.shift]: mode = .formats
    case [.command]: mode = .tools
    case [.control]: mode = .actions
    default: return
    }

    let urls = Self.fileURLs(on: NSPasteboard(name: .drag))
    guard !urls.isEmpty else { return }
    show(mode, for: urls)
  }

  private static func fileURLs(on pasteboard: NSPasteboard) -> [URL] {
    pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
  }

  // MARK: - Panel

  private func show(_ mode: DropWheel.Mode, for urls: [URL]) {
    let segments = WheelSegments.segments(for: mode, urls: urls)
    guard !segments.isEmpty else { return }

    wheel.mode = mode
    wheel.segments = segments
    wheel.hovered = 0

    // Switching modes mid-drag keeps the wheel where it is.
    guard !wheel.isVisible else { return }

    let panel = self.panel ?? makePanel()
    self.panel = panel
    let mouse = NSEvent.mouseLocation
    let center = Self.wheelCenterInPanel
    panel.setFrameOrigin(NSPoint(x: mouse.x - center.x, y: mouse.y - center.y))
    panel.orderFrontRegardless()
    wheel.isVisible = true
  }

  private func hide() {
    guard wheel.isVisible else { return }
    wheel.isVisible = false
    // Let the fade-out play before the window goes.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
      if !self.wheel.isVisible { self.panel?.orderOut(nil) }
    }
  }

  /// The wheel's centre in the panel's y-up coordinates.
  private static var wheelCenterInPanel: NSPoint {
    NSPoint(
      x: DropWheelView.panelSize.width / 2,
      y: DropWheelView.panelSize.height - DropWheelView.topInset - DropWheelView.outerRadius
    )
  }

  private func makePanel() -> NSPanel {
    let panel = NSPanel(
      contentRect: NSRect(origin: .zero, size: DropWheelView.panelSize),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.level = .popUpMenu
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    panel.hidesOnDeactivate = false

    let target = DropTargetView(frame: NSRect(origin: .zero, size: DropWheelView.panelSize))
    target.onMove = { [weak self] point in self?.dragMoved(to: point) }
    target.onDrop = { [weak self] urls in self?.drop(urls) ?? false }

    let hosting = NSHostingView(rootView: DropWheelView(wheel: wheel))
    hosting.frame = target.bounds
    hosting.autoresizingMask = [.width, .height]
    target.addSubview(hosting)
    panel.contentView = target
    return panel
  }

  // MARK: - Drop

  private func dragMoved(to point: NSPoint) {
    let center = Self.wheelCenterInPanel
    if let index = DropWheel.segmentIndex(
      dx: point.x - center.x,
      dy: point.y - center.y,
      count: wheel.segments.count,
      innerRadius: DropWheelView.innerRadius,
      outerRadius: DropWheelView.outerRadius
    ) {
      wheel.hovered = index
    }
  }

  private func drop(_ urls: [URL]) -> Bool {
    guard let segment = wheel.hoveredSegment, !urls.isEmpty else { return false }
    hide()
    // After the drop returns, so the dragging app is not kept waiting.
    DispatchQueue.main.async {
      Self.run(segment, on: urls)
    }
    return true
  }

  private static func run(_ segment: WheelSegment, on urls: [URL]) {
    Task { @MainActor in
      let started = Date()
      do {
        let outputs = try await segment.perform(urls)
        if !outputs.isEmpty {
          let pasteboard = NSPasteboard.general
          pasteboard.clearContents()
          pasteboard.writeObjects(outputs as [NSURL])
        }
        if Defaults[.capturePlaySound] {
          NSSound(named: "Pop")?.play()
        }
        // A video can take a while; say when it is done, since the wheel
        // is long gone by then.
        if Date().timeIntervalSince(started) > 2, let first = outputs.first {
          let more = outputs.count > 1 ? " and \(outputs.count - 1) more" : ""
          Notifier.notify(body: "Saved \(first.lastPathComponent)\(more)", sound: nil)
        }
      } catch {
        if Defaults[.capturePlaySound] {
          NSSound(named: "Basso")?.play()
        }
        Notifier.notify(body: error.localizedDescription, sound: nil)
      }
    }
  }
}

/// The wheel's content view: accepts the file drag and reports where it is.
private final class DropTargetView: NSView {
  var onMove: ((NSPoint) -> Void)?
  var onDrop: (([URL]) -> Bool)?

  override init(frame: NSRect) {
    super.init(frame: frame)
    registerForDraggedTypes([.fileURL])
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    draggingUpdated(sender)
  }

  override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
    onMove?(convert(sender.draggingLocation, from: nil))
    return Self.operation(for: sender)
  }

  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    let urls = sender.draggingPasteboard.readObjects(
      forClasses: [NSURL.self],
      options: [.urlReadingFileURLsOnly: true]
    ) as? [URL] ?? []
    return onDrop?(urls) ?? false
  }

  /// Copy if the source allows it. Holding ⌘ makes Finder offer only a move,
  /// so fall back to whatever is on offer — the files are only read, never
  /// moved, whatever operation is reported.
  private static func operation(for sender: NSDraggingInfo) -> NSDragOperation {
    let mask = sender.draggingSourceOperationMask
    for operation in [NSDragOperation.copy, .generic, .link, .move] where mask.contains(operation) {
      return operation
    }
    return []
  }
}

/// What each wheel offers for a set of dragged files. The first file decides
/// the kind; files of other kinds in the same drag are left alone.
@MainActor
enum WheelSegments {
  static func segments(for mode: DropWheel.Mode, urls: [URL]) -> [WheelSegment] {
    guard let first = urls.first else { return [] }
    let kind = FileKind(first)
    let files = urls.filter { FileKind($0) == kind }

    switch mode {
    case .formats: return formats(kind: kind, files: files)
    case .tools: return tools(kind: kind, files: files, mergeable: mergeable(urls))
    case .actions: return actions
    }
  }

  // MARK: - ⇧ Formats

  private static func formats(kind: FileKind, files: [URL]) -> [WheelSegment] {
    switch kind {
    case .image:
      // Converting a PNG to PNG is pointless, so drop the source format when
      // every file shares it.
      let sources = Set(files.map { ImageExportFormat(fileURL: $0) })
      let skip = sources.count == 1 ? sources.first ?? nil : nil
      return ImageExportFormat.available.filter { $0 != skip }.map { format in
        convert(format.title, kind: kind) { try ImageConverter.convertFile($0, to: format) }
      }

    case .video:
      let ext = files.first?.pathExtension.lowercased()
      return VideoFormat.allCases.filter { $0.title.lowercased() != ext }.map { format in
        convert(format.title, kind: kind) { try await MediaConverter.convertVideo($0, to: format) }
      }

    case .audio:
      let ext = files.first?.pathExtension.lowercased()
      return AudioFormat.allCases.filter { $0.title.lowercased() != ext }.map { format in
        convert(format.title, kind: kind) { try await MediaConverter.convertAudio($0, to: format) }
      }

    case .pdf:
      let images: [ImageExportFormat] = [.png, .jpeg]
      return images.map { format in
        convertMany(format.title, kind: kind) { try DocumentConverter.pdfToImages($0, as: format) }
      } + [
        convert("TXT", kind: kind) { try DocumentConverter.pdfToText($0) },
        convert("DOCX", kind: kind) { try DocumentConverter.pdfToDocument($0, as: .docx) },
        convert("RTF", kind: kind) { try DocumentConverter.pdfToDocument($0, as: .rtf) }
      ]

    case .document:
      return DocumentFormat.allCases.filter { format in !files.allSatisfy(format.matches) }.map { format in
        convert(format.title, kind: kind) { try DocumentConverter.convertDocument($0, to: format) }
      }

    case .subtitle:
      let ext = files.first?.pathExtension.lowercased()
      return SubtitleFormat.allCases.filter { $0.title.lowercased() != ext }.map { format in
        convert(format.title, kind: kind) { try DocumentConverter.convertSubtitles($0, to: format) }
      }

    case .archive:
      return [
        WheelSegment(id: "format.extract", title: "Extract", systemImage: "archivebox",
                     caption: "Extract here") { urls in
          var folders: [URL] = []
          for url in of(kind, in: urls) {
            folders.append(try await DocumentConverter.extract(url))
          }
          return folders
        }
      ]

    case .other:
      return []
    }
  }

  /// A format slice that converts each file to one output.
  private static func convert(
    _ title: String,
    kind: FileKind,
    _ body: @escaping @MainActor (URL) async throws -> URL
  ) -> WheelSegment {
    convertMany(title, kind: kind) { [try await body($0)] }
  }

  /// A format slice where one file can produce several, e.g. PDF pages.
  private static func convertMany(
    _ title: String,
    kind: FileKind,
    _ body: @escaping @MainActor (URL) async throws -> [URL]
  ) -> WheelSegment {
    WheelSegment(id: "format.\(title)", title: title, systemImage: nil, caption: "Convert to \(title)") { urls in
      var outputs: [URL] = []
      for url in of(kind, in: urls) {
        outputs += try await body(url)
      }
      return outputs
    }
  }

  // MARK: - ⌘ Tools

  private static func tools(kind: FileKind, files: [URL], mergeable: [URL]) -> [WheelSegment] {
    switch kind {
    case .image:
      var tools = [
        tool("Compress", "arrow.down.right.and.arrow.up.left", "Compress", kind: kind) { url in
          // Lossy formats are re-encoded as they are; lossless ones have
          // nothing to give without changing format, so they become JPEG.
          let lossy: [ImageExportFormat] = [.jpeg, .heic, .webp, .avif]
          let format = ImageExportFormat(fileURL: url).flatMap { lossy.contains($0) ? $0 : nil } ?? .jpeg
          return try ImageConverter.convertFile(url, to: format, quality: 0.6, suffix: "compressed")
        },
        resize(0.5),
        resize(0.25),
        tool("Metadata", "eye.slash", "Remove metadata", kind: kind) { url in
          try ImageConverter.convertFile(url, to: sameImageFormat(url), quality: 0.95, suffix: "clean")
        },
        copyText(kind: kind) { url in
          guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ConversionError.unreadable
          }
          return try ScreenTextCapture.recognizeText(in: image, keepLineBreaks: Defaults[.captureKeepLineBreaks])
        }
      ]
      if mergeable.count > 1 {
        tools.insert(mergeSegment(title: "Combine", caption: "Combine into one PDF"), at: 1)
      }
      if files.count == 1 {
        tools.append(WheelSegment(id: "tool.edit", title: "Edit", systemImage: "slider.horizontal.3",
                                  caption: "Crop, annotate, add a background") { urls in
          guard let url = of(kind, in: urls).first, let image = NSImage(contentsOf: url) else {
            throw ConversionError.unreadable
          }
          ScreenshotController.shared.openEditor(with: image)
          return []
        })
      }
      return tools

    case .video:
      return [
        tool("Compress", "arrow.down.right.and.arrow.up.left", "Compress (HEVC, up to 1080p)", kind: kind) {
          try await MediaConverter.compressVideo($0)
        },
        tool("720p", "rectangle.compress.vertical", "Resize to 720p", kind: kind) {
          try await MediaConverter.video720p($0)
        },
        tool("Mute", "speaker.slash", "Remove the sound", kind: kind) {
          try await MediaConverter.mute($0)
        },
        tool("Frame", "photo", "Save a still frame", kind: kind) {
          try await MediaConverter.frame($0)
        }
      ]

    case .audio:
      return [
        tool("Compress", "arrow.down.right.and.arrow.up.left", "Compress (AAC 96 kbps)", kind: kind) {
          try await MediaConverter.compressAudio($0)
        },
        tool("Mono", "speaker.wave.1", "Mix down to mono", kind: kind) {
          try await MediaConverter.mono($0)
        },
        tool("Normalize", "waveform", "Normalize loudness", kind: kind) {
          try await MediaConverter.normalize($0)
        }
      ]

    case .pdf:
      var tools = [
        tool("Compress", "arrow.down.right.and.arrow.up.left", "Compress", kind: kind) {
          try DocumentConverter.compressPDF($0)
        },
        WheelSegment(id: "tool.split", title: "Split", systemImage: "scissors",
                     caption: "One PDF per page") { urls in
          try of(kind, in: urls).flatMap(DocumentConverter.split)
        },
        tool("Rotate", "rotate.right", "Rotate 90°", kind: kind) {
          try DocumentConverter.rotate($0)
        },
        copyText(kind: kind) { try DocumentConverter.pdfText($0) }
      ]
      if mergeable.count > 1 {
        tools.insert(mergeSegment(title: "Merge", caption: "Merge into one PDF"), at: 1)
      }
      return tools

    case .document:
      return [copyText(kind: kind) { try DocumentConverter.readDocument($0).string }]

    case .subtitle, .archive, .other:
      return []
    }
  }

  private static func tool(
    _ title: String,
    _ systemImage: String,
    _ caption: String,
    kind: FileKind,
    _ body: @escaping @MainActor (URL) async throws -> URL
  ) -> WheelSegment {
    WheelSegment(id: "tool.\(title)", title: title, systemImage: systemImage, caption: caption) { urls in
      var outputs: [URL] = []
      for url in of(kind, in: urls) {
        outputs.append(try await body(url))
      }
      return outputs
    }
  }

  private static func resize(_ scale: Double) -> WheelSegment {
    let percent = Int(scale * 100)
    return tool("\(percent)%", "arrow.down.forward.and.arrow.up.backward", "Resize to \(percent)%", kind: .image) { url in
      try ImageConverter.convertFile(url, to: sameImageFormat(url), scale: scale, suffix: "\(percent)%")
    }
  }

  /// Puts the text in the files on the clipboard rather than in a file.
  private static func copyText(kind: FileKind, _ extract: @escaping @MainActor (URL) throws -> String) -> WheelSegment {
    WheelSegment(id: "tool.text", title: "Text", systemImage: "text.viewfinder", caption: "Copy the text") { urls in
      let text = try of(kind, in: urls).map(extract).joined(separator: "\n\n")
      let pasteboard = NSPasteboard.general
      pasteboard.clearContents()
      pasteboard.setString(text, forType: .string)
      return []
    }
  }

  private static func sameImageFormat(_ url: URL) -> ImageExportFormat {
    ImageExportFormat(fileURL: url).flatMap { $0.isAvailable ? $0 : nil } ?? .png
  }

  // MARK: - ⌃ Actions

  private static var actions: [WheelSegment] {
    [
      WheelSegment(id: "action.airdrop", title: "AirDrop", systemImage: "airplayaudio",
                   caption: "Send with AirDrop") { urls in
        NSSharingService(named: .sendViaAirDrop)?.perform(withItems: urls)
        return []
      },
      WheelSegment(id: "action.copy", title: "Copy", systemImage: "doc.on.doc",
                   caption: "Copy to the clipboard") { urls in
        urls
      },
      WheelSegment(id: "action.path", title: "Path", systemImage: "link",
                   caption: "Copy path") { urls in
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
        return []
      },
      WheelSegment(id: "action.zip", title: "Zip", systemImage: "archivebox",
                   caption: "Compress into a zip") { urls in
        [try await DocumentConverter.zip(urls)]
      },
      WheelSegment(id: "action.terminal", title: "Terminal", systemImage: "terminal",
                   caption: "Open in Terminal") { urls in
        if let url = urls.first { CardActions.openInTerminal(url) }
        return []
      }
    ]
  }

  /// Merging takes PDFs and images together, whichever kind was dragged
  /// first, so one drag can turn a scan pile plus a cover PDF into one file.
  private static func mergeSegment(title: String, caption: String) -> WheelSegment {
    WheelSegment(id: "tool.merge", title: title, systemImage: "square.stack", caption: caption) { urls in
      [try DocumentConverter.merge(mergeable(urls))]
    }
  }

  private static func mergeable(_ urls: [URL]) -> [URL] {
    urls.filter { [.pdf, .image].contains(FileKind($0)) }
  }

  private static func of(_ kind: FileKind, in urls: [URL]) -> [URL] {
    urls.filter { FileKind($0) == kind }
  }
}
