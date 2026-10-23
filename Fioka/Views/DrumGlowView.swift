import SwiftUI

/// What sits behind the revolver: no panel, but a frosted backdrop that is
/// solid behind the cards and fades to nothing before the window's edges on
/// every side, tinted with the logo's colours. It calms whatever is behind
/// (text, windows) without drawing a box.
///
/// Elliptical gradient masks rather than blurred shapes: a blur spills past
/// the window and its frame cuts it in a straight line; a mask that reaches
/// clear at the frame's edge cannot. An `EllipticalGradient`'s locations run
/// from the centre (0) to the frame's edge (1).
struct DrumGlowView: View {
  /// Off-screen renders (the README and website images) get a painted frost:
  /// NSVisualEffectView blurs what is behind the window, so it draws nothing
  /// in ImageRenderer.
  var painted = false

  /// Fully opaque out to here, then fading to clear at the edge.
  private static func fade(solidUntil solid: Double) -> some View {
    EllipticalGradient(
      stops: [
        .init(color: .black, location: 0),
        .init(color: .black, location: solid),
        .init(color: .black.opacity(0.7), location: (solid + 1) / 2),
        .init(color: .clear, location: 1)
      ],
      center: .init(x: 0.5, y: 0.55)
    )
  }

  var body: some View {
    ZStack {
      // Frosted glass, as macOS's own panels use, fading out at the rim.
      Group {
        if painted {
          Color(white: 0.97).opacity(0.86)
        } else {
          VisualEffectView(material: .popover, blendingMode: .behindWindow, state: .active)
        }
      }
      .mask { Self.fade(solidUntil: 0.55) }

      // The logo's colours over it.
      LinearGradient(colors: [Brand.pink, Brand.violet, Brand.cyan], startPoint: .leading, endPoint: .trailing)
        .opacity(0.4)
        .mask { Self.fade(solidUntil: 0.38) }

      // A soft shadow under the cards, so they lift off the frost.
      EllipticalGradient(
        stops: [.init(color: .black.opacity(0.28), location: 0), .init(color: .clear, location: 0.8)],
        center: .init(x: 0.5, y: 0.62)
      )
    }
    .frame(maxWidth: 1700, maxHeight: .infinity)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .allowsHitTesting(false)
  }
}
