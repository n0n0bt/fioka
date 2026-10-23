import AppKit
import Defaults
import KeyboardShortcuts

/// Hotkey -> drag a region -> OCR -> clipboard.
///
/// The result is written to the pasteboard as plain text and nothing more:
/// the clipboard poller picks it up like any other copy, so it lands in the
/// history and shows up in the card bar on its own.
@MainActor
final class TextCaptureController {
  static let shared = TextCaptureController()

  private var isCapturing = false

  func start() {
    KeyboardShortcuts.onKeyDown(for: .captureText) { [weak self] in
      self?.capture()
    }
  }

  func capture() {
    guard !isCapturing, !RegionSelector.shared.isActive else { return }
    isCapturing = true

    RegionSelector.shared.begin { [weak self] rect in
      guard let self else { return }
      guard let rect, rect.width >= 4, rect.height >= 4 else {
        self.isCapturing = false
        return
      }

      Task { @MainActor in
        defer { self.isCapturing = false }
        await self.recognize(in: rect)
      }
    }
  }

  private func recognize(in rect: CGRect) async {
    do {
      // Give the overlay a frame to disappear, or it lands in the capture.
      try? await Task.sleep(for: .milliseconds(120))

      let image = try await ScreenTextCapture.captureImage(screenRect: rect)
      let text = try ScreenTextCapture.recognizeText(
        in: image,
        keepLineBreaks: Defaults[.captureKeepLineBreaks]
      )

      guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        notify(success: false, message: "No text found")
        return
      }

      let pasteboard = NSPasteboard.general
      pasteboard.clearContents()
      pasteboard.setString(text, forType: .string)

      notify(success: true, message: nil)
    } catch {
      // The most likely cause by far is Screen Recording not being granted;
      // ScreenCaptureKit reports that as an ordinary failure.
      notify(success: false, message: "Capture failed — check Screen Recording permission")
    }
  }

  private func notify(success: Bool, message: String?) {
    if Defaults[.capturePlaySound] {
      NSSound(named: success ? "Glass" : "Basso")?.play()
    }

    guard let message else { return }

    let alert = NSAlert()
    alert.messageText = message
    alert.alertStyle = success ? .informational : .warning
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }
}
