import AppKit

struct Accessibility {
  private static var allowed: Bool { AXIsProcessTrustedWithOptions(nil) }

  static func check() {
    guard !allowed else {
      return
    }

    // Ask macOS to show the system dialog that deep-links into
    // System Settings > Privacy & Security > Accessibility. Without the
    // permission, the synthetic Cmd+V in Clipboard.paste() is silently
    // dropped, so the user gets no feedback at all.
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
    _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
  }
}
