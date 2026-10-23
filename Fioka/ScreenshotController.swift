import AppKit
import Defaults
import KeyboardShortcuts
import SwiftUI
import UniformTypeIdentifiers

/// Hotkey -> the system screenshot UI -> an editor window -> clipboard.
///
/// Selection is done by `/usr/sbin/screencapture -i`, the same tool behind
/// ⌘⇧4, so it behaves exactly like the system one: drag a region, or press
/// Space to pick a window. Copying writes a PNG to the pasteboard, where the
/// clipboard poller picks it up like any other copy and puts it in the card bar.
@MainActor
final class ScreenshotController: NSObject, NSWindowDelegate {
  static let shared = ScreenshotController()

  private var isCapturing = false
  private var editors: [NSWindow: ScreenshotEditor] = [:]
  private var previousApp: NSRunningApplication?

  func start() {
    KeyboardShortcuts.onKeyDown(for: .captureScreenshot) { [weak self] in
      self?.capture()
    }
  }

  func capture() {
    guard !isCapturing, !RegionSelector.shared.isActive else { return }
    isCapturing = true
    if NSWorkspace.shared.frontmostApplication != NSRunningApplication.current {
      previousApp = NSWorkspace.shared.frontmostApplication
    }

    Task {
      defer { isCapturing = false }
      do {
        if let image = try await runScreencapture() {
          openEditor(with: image)
        }
      } catch {
        // screencapture couldn't run at all (sandbox, missing binary): fall
        // back to our own selector, which goes through ScreenCaptureKit.
        NSLog("Fioka: screencapture failed (\(error)); using built-in selector")
        if let image = await captureWithRegionSelector() {
          openEditor(with: image)
        }
      }
    }
  }

  // MARK: - Capture

  private enum CaptureError: Error {
    case failed(String)
  }

  /// Returns nil when the user cancels with Escape.
  private func runScreencapture() async throws -> NSImage? {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("screenshot-\(UUID().uuidString).png")
    defer { try? FileManager.default.removeItem(at: url) }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    // -i interactive, -o no window shadow (the editor adds its own), -x silent.
    process.arguments = ["-i", "-o", "-x", url.path]
    let stderr = Pipe()
    process.standardError = stderr

    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      process.terminationHandler = { _ in continuation.resume() }
      do {
        try process.run()
      } catch {
        process.terminationHandler = nil
        continuation.resume(throwing: error)
      }
    }

    if let image = NSImage(contentsOf: url), image.isValid {
      return image
    }

    // Escape exits quietly with no file. Anything else is a real failure.
    let message = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    if process.terminationReason == .uncaughtSignal || !message.isEmpty {
      throw CaptureError.failed(message)
    }
    return nil
  }

  private func captureWithRegionSelector() async -> NSImage? {
    let rect: CGRect? = await withCheckedContinuation { continuation in
      RegionSelector.shared.begin { continuation.resume(returning: $0) }
    }
    guard let rect, rect.width >= 4, rect.height >= 4 else { return nil }

    // Give the overlay a frame to disappear, or it lands in the capture.
    try? await Task.sleep(for: .milliseconds(120))
    guard let cgImage = try? await ScreenTextCapture.captureImage(screenRect: rect) else {
      NSSound(named: "Basso")?.play()
      return nil
    }
    return NSImage(cgImage: cgImage, size: rect.size)
  }

  // MARK: - Editor window

  func openEditor(with image: NSImage) {
    let editor = ScreenshotEditor(image: image)
    // A non-activating panel, like the card bar: by the time the capture
    // finishes, screencapture is the frontmost app and macOS refuses to
    // activate us, so a plain NSWindow opens *behind* everything. This panel
    // takes key focus (typing, shortcuts) without needing activation.
    let window = NSPanel(
      contentRect: NSRect(origin: .zero, size: windowSize(for: editor)),
      styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    window.title = "Screenshot"
    window.level = .floating
    window.isFloatingPanel = true
    // Panels hide when their app deactivates by default, and this app is
    // usually not active at all.
    window.hidesOnDeactivate = false
    window.becomesKeyOnlyIfNeeded = false
    window.isReleasedWhenClosed = false
    window.delegate = self
    window.contentView = NSHostingView(rootView: ScreenshotEditorView(
      editor: editor,
      onCopy: { [weak self, weak window] in
        guard let window else { return }
        self?.copy(from: window)
      },
      onSave: { [weak self, weak window] in
        guard let window else { return }
        self?.save(from: window)
      },
      onClose: { [weak window] in window?.close() }
    ))
    editors[window] = editor

    window.center()
    window.makeKeyAndOrderFront(nil)
  }

  private func windowSize(for editor: ScreenshotEditor) -> NSSize {
    let visible = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
    let canvas = editor.canvasSize
    // Room for the toolbar (top) and the sidebar (right) around the canvas.
    return NSSize(
      width: min(max(canvas.width + 236 + 48, 1180), visible.width * 0.9),
      height: min(max(canvas.height + 52 + 48, 560), visible.height * 0.9)
    )
  }

  private func copy(from window: NSWindow) {
    guard let editor = editors[window] else { return }
    editor.commitPendingText()
    guard let png = editor.renderPNG() else {
      NSSound(named: "Basso")?.play()
      return
    }

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setData(png, forType: .png)

    if Defaults[.capturePlaySound] {
      NSSound(named: "Glass")?.play()
    }
    window.close()
  }

  private func save(from window: NSWindow) {
    guard let editor = editors[window] else { return }
    editor.commitPendingText()

    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"

    let panel = NSSavePanel()
    panel.allowedContentTypes = [.png]
    panel.nameFieldStringValue = "Screenshot \(formatter.string(from: Date())).png"
    panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
    // The save sheet needs the app properly active to take typing.
    NSApp.activate()
    panel.beginSheetModal(for: window) { response in
      guard response == .OK, let url = panel.url else { return }
      guard let png = editor.renderPNG() else {
        NSSound(named: "Basso")?.play()
        return
      }
      do {
        try png.write(to: url)
        window.close()
      } catch {
        NSAlert(error: error).beginSheetModal(for: window)
      }
    }
  }

  func windowWillClose(_ notification: Notification) {
    guard let window = notification.object as? NSWindow else { return }
    editors[window] = nil

    // Hand focus back to where the screenshot came from, so a copy can be
    // pasted straight away.
    if editors.isEmpty {
      previousApp?.activate()
      previousApp = nil
    }
  }
}
