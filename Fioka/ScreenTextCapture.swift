import AppKit
import ScreenCaptureKit
import Vision

enum ScreenTextCaptureError: Error {
  case noDisplay
  case captureFailed
}

/// Grabs a region of the screen and runs text recognition over it.
///
/// Capture goes through ScreenCaptureKit: the CoreGraphics calls every older
/// example uses (CGDisplayCreateImage, CGWindowListCreateImage) are marked
/// SCREEN_CAPTURE_OBSOLETE as of macOS 15 and return nothing.
enum ScreenTextCapture {

  /// Converts an AppKit screen rect (bottom-left origin) into the top-left
  /// origin coordinate space CoreGraphics and ScreenCaptureKit use.
  static func cgRect(fromScreenRect rect: CGRect) -> CGRect {
    guard let primary = NSScreen.screens.first else { return rect }
    return CGRect(
      x: rect.minX,
      y: primary.frame.maxY - rect.maxY,
      width: rect.width,
      height: rect.height
    )
  }

  static func captureImage(screenRect: CGRect) async throws -> CGImage {
    let target = cgRect(fromScreenRect: screenRect)

    let content = try await SCShareableContent.excludingDesktopWindows(
      false,
      onScreenWindowsOnly: true
    )

    // Pick the display the selection actually falls on, not just the first.
    guard let display = content.displays.first(where: {
      CGDisplayBounds($0.displayID).intersects(target)
    }) ?? content.displays.first else {
      throw ScreenTextCaptureError.noDisplay
    }

    let displayBounds = CGDisplayBounds(display.displayID)
    let scale = NSScreen.screens
      .first { $0.displayID == display.displayID }?
      .backingScaleFactor ?? 2

    let configuration = SCStreamConfiguration()
    // sourceRect is expressed relative to the display, in points.
    configuration.sourceRect = CGRect(
      x: target.minX - displayBounds.minX,
      y: target.minY - displayBounds.minY,
      width: target.width,
      height: target.height
    )
    // Capture at native backing resolution: OCR accuracy depends on it.
    configuration.width = Int(target.width * scale)
    configuration.height = Int(target.height * scale)
    configuration.captureResolution = .best
    configuration.showsCursor = false
    configuration.scalesToFit = false

    let filter = SCContentFilter(display: display, excludingWindows: [])

    return try await SCScreenshotManager.captureImage(
      contentFilter: filter,
      configuration: configuration
    )
  }

  /// Runs Vision text recognition. Unlike the title-generating OCR in
  /// HistoryItem, this uses `.accurate` — the result is the product here, not
  /// a label, so the extra time is worth it.
  static func recognizeText(in image: CGImage, keepLineBreaks: Bool) throws -> String {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.automaticallyDetectsLanguage = true

    try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])

    let lines = (request.results ?? [])
      .compactMap { $0.topCandidates(1).first?.string }

    return keepLineBreaks
      ? lines.joined(separator: "\n")
      : lines.joined(separator: " ")
  }
}

private extension NSScreen {
  var displayID: CGDirectDisplayID? {
    deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
  }
}
