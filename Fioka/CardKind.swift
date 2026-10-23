import AppKit
import SwiftHEXColors
import SwiftUI

/// Visual classification of a clipboard item.
///
/// Paste gives every card a colored header naming what was copied. This derives
/// the same classification from the pasteboard representations `HistoryItem`
/// already stores, so no extra data has to be captured at copy time.
enum CardKind: Equatable {
  case text
  case code
  case link
  case file
  case image
  case color(hex: String)

  var label: String {
    switch self {
    case .text: return "Text"
    case .code: return "Code"
    case .link: return "Link"
    case .file: return "File"
    case .image: return "Image"
    case .color: return "Color"
    }
  }

  var symbol: String {
    switch self {
    case .text: return "textformat"
    case .code: return "chevron.left.forwardslash.chevron.right"
    case .link: return "link"
    case .file: return "doc"
    case .image: return "photo"
    case .color: return "paintpalette"
    }
  }

  /// Base header colour, chosen so types stay distinguishable at a glance
  /// without reading the label.
  var accentNSColor: NSColor {
    switch self {
    case .text: return NSColor(srgbRed: 0.96, green: 0.53, blue: 0.15, alpha: 1)
    case .code: return NSColor(srgbRed: 0.35, green: 0.40, blue: 0.95, alpha: 1)
    case .link: return NSColor(srgbRed: 0.13, green: 0.74, blue: 0.44, alpha: 1)
    case .file: return NSColor(srgbRed: 0.16, green: 0.56, blue: 0.96, alpha: 1)
    case .image: return NSColor(srgbRed: 0.73, green: 0.33, blue: 0.92, alpha: 1)
    case .color(let hex): return NSColor(hexString: hex) ?? .systemPink
    }
  }

  var accent: Color { Color(nsColor: accentNSColor) }

  /// Diagonal gradient for the card header. Two stops derived from one base
  /// colour, so a copied colour gets the same treatment as a built-in type.
  var gradient: [Color] {
    let base = accentNSColor
    return [Color(nsColor: base.shifted(by: 0.10)), Color(nsColor: base.shifted(by: -0.16))]
  }

  /// Colour used for text drawn on top of the header. A copied colour can be
  /// arbitrarily light, so pick black or white by luminance instead of
  /// assuming white always reads.
  var onAccent: Color {
    guard case .color = self,
          let srgb = accentNSColor.usingColorSpace(.sRGB) else {
      return .white
    }

    let luminance = 0.299 * srgb.redComponent +
                    0.587 * srgb.greenComponent +
                    0.114 * srgb.blueComponent
    return luminance > 0.6 ? .black : .white
  }

  static func of(_ item: HistoryItem) -> CardKind {
    if item.image != nil {
      return .image
    }

    if !item.fileURLs.isEmpty {
      return .file
    }

    let trimmed = item.previewableText.trimmingCharacters(in: .whitespacesAndNewlines)

    if isHexColor(trimmed) {
      return .color(hex: trimmed)
    }

    if isLink(trimmed) {
      return .link
    }

    if looksLikeCode(trimmed) {
      return .code
    }

    return .text
  }

  private static func isHexColor(_ string: String) -> Bool {
    let pattern = "^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$"
    return string.range(of: pattern, options: .regularExpression) != nil
  }

  private static func isLink(_ string: String) -> Bool {
    // A link is a single token; a paragraph that happens to contain a URL is
    // still text as far as the card is concerned.
    guard !string.contains(where: \.isWhitespace), string.count < 2048 else {
      return false
    }
    guard let url = URL(string: string), let scheme = url.scheme?.lowercased() else {
      return false
    }
    return ["http", "https", "ftp", "mailto"].contains(scheme) && url.host != nil || scheme == "mailto"
  }

  /// Deliberately conservative: prose with a stray bracket should stay Text.
  /// Requires either a strong single signal (a fenced block, a shebang, an
  /// import/function keyword at line start) or several weaker ones.
  private static func looksLikeCode(_ string: String) -> Bool {
    guard string.count > 12 else { return false }

    let strong = [
      "^#!/", "^\\s*(func|def|class|struct|enum|interface|impl)\\s+\\w",
      "^\\s*(import|#include|using|package|from)\\s+\\S", "^\\s*```",
      "^\\s*(public|private|protected|static|const|let|var)\\s+\\w+\\s*[:=]",
      "=>|->|::|\\}\\s*;|\\)\\s*\\{"
    ]
    for pattern in strong
    where string.range(of: pattern, options: [.regularExpression]) != nil {
      return true
    }

    let weak = ["[{};]", "\\b(if|for|while|return|else)\\b", "==|!=|&&|\\|\\|", "\\w+\\(\\)", "^\\s{2,}\\S"]
    let hits = weak.filter { string.range(of: $0, options: [.regularExpression]) != nil }.count
    return hits >= 3
  }
}

private extension NSColor {
  /// Lighten (positive) or darken (negative) by moving each channel a fraction
  /// of the way toward white or black. Works on any colour space, unlike
  /// adjusting HSB brightness directly.
  func shifted(by amount: CGFloat) -> NSColor {
    guard let srgb = usingColorSpace(.sRGB) else { return self }

    func move(_ channel: CGFloat) -> CGFloat {
      let target: CGFloat = amount >= 0 ? 1 : 0
      return channel + (target - channel) * abs(amount)
    }

    return NSColor(
      srgbRed: move(srgb.redComponent),
      green: move(srgb.greenComponent),
      blue: move(srgb.blueComponent),
      alpha: srgb.alphaComponent
    )
  }
}
