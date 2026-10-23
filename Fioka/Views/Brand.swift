import SwiftUI

/// Fioka's colours, taken from the icon: the pink, violet and cyan glow behind
/// the glass, and the near-black of the F's outline. Everything the fork adds
/// draws from here, so the app and the logo stay one family.
enum Brand {
  static let pink = Color(hex: 0xF76BA8)
  static let violet = Color(hex: 0x6E6BFF)
  static let cyan = Color(hex: 0x3CC8E0)
  static let ink = Color(hex: 0x17151F)

  /// The main accent: selection, highlights, prominent buttons.
  static let accent = violet

  /// The icon's glow, as a gradient. Diagonal, pink to cyan.
  static let gradient = LinearGradient(
    colors: [pink, violet, cyan],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
  )

  /// The same three colours, pale, for large areas such as backgrounds.
  static let paleColors = [Color(hex: 0xFFD3E6), Color(hex: 0xD9D2FF), Color(hex: 0xC9F2F6)]
}
