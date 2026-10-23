import SwiftUI

/// Backdrop for the card bar.
///
/// A floating frosted sheet: `.popover` follows the system
/// appearance (light frost in light mode, dark in dark mode), unlike
/// `.hudWindow`, which is always dark. The bar sits inset from the screen
/// edges with every corner rounded, so it gets a hairline all the way round
/// instead of a seam along one edge.
struct PanelBackdropView: View {
  var body: some View {
    VisualEffectView(
      material: .popover,
      blendingMode: .behindWindow,
      // The panel is never the active window; see VisualEffectView.
      state: .active
    )
    // The icon's glow, barely there: enough to tie the bar to the brand
    // without competing with the cards' own colours.
    .overlay {
      LinearGradient(colors: [Brand.pink, Brand.violet, Brand.cyan], startPoint: .leading, endPoint: .trailing)
        .opacity(0.07)
    }
    .overlay {
      RoundedRectangle(cornerRadius: Popup.cardBarCornerRadius, style: .continuous)
        .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
    }
  }
}
