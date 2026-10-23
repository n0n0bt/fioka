import SwiftUI

/// What sits behind the revolver. No panel and no shapes: a frost that rises
/// from the bottom of the window and thins out upwards, and under the cards a
/// thin line of light in the logo's colours, like a lit glass shelf, whose
/// colours drift slowly along it.
///
/// Everything fades to clear before the window's edges, so nothing ends in a
/// line where the window frame cuts it.
struct DrumGlowView: View {
  /// Off-screen renders (the README and website images) get a painted frost:
  /// NSVisualEffectView blurs what is behind the window, so it draws nothing
  /// in ImageRenderer. They also hold still.
  var painted = false

  @Environment(\.colorScheme) private var colorScheme
  @State private var drifting = false

  /// How far above the window's bottom the shelf runs: just under the front
  /// card, whose bottom is CardCarouselView.bottomPadding up.
  private static let shelfInset: CGFloat = CardCarouselView.bottomPadding - 10

  var body: some View {
    GeometryReader { geometry in
      let width = min(geometry.size.width * 0.62, 1100)
      ZStack(alignment: .bottom) {
        frost
          .mask { Self.rising }
        shelf(width: width)
          .padding(.bottom, Self.shelfInset)
      }
      .frame(width: geometry.size.width, height: geometry.size.height)
    }
    .allowsHitTesting(false)
    .onAppear {
      guard !painted else { return }
      withAnimation(.easeInOut(duration: 10).repeatForever(autoreverses: true)) {
        drifting = true
      }
    }
  }

  /// Clear at the top, solid from a little below the middle down; clear in
  /// the last few points and at both sides.
  private static var rising: some View {
    LinearGradient(
      stops: [
        .init(color: .clear, location: 0),
        .init(color: .black.opacity(0.3), location: 0.3),
        .init(color: .black.opacity(0.85), location: 0.6),
        .init(color: .black, location: 0.94),
        .init(color: .clear, location: 1)
      ],
      startPoint: .top,
      endPoint: .bottom
    )
    .mask { sides(edge: 0.1) }
  }

  private static func sides(edge: Double) -> some View {
    LinearGradient(
      stops: [
        .init(color: .clear, location: 0),
        .init(color: .black, location: edge),
        .init(color: .black, location: 1 - edge),
        .init(color: .clear, location: 1)
      ],
      startPoint: .leading,
      endPoint: .trailing
    )
  }

  @ViewBuilder
  private var frost: some View {
    if painted {
      Color(white: 0.97).opacity(0.8)
    } else {
      VisualEffectView(material: .popover, blendingMode: .behindWindow, state: .active)
    }
  }

  /// The logo's colours, twice over so they can slide along the line without
  /// running out, fading in from both ends.
  private func colours(width: CGFloat) -> some View {
    LinearGradient(
      colors: [Brand.pink, Brand.violet, Brand.cyan, Brand.violet, Brand.pink, Brand.violet, Brand.cyan],
      startPoint: .leading,
      endPoint: .trailing
    )
    .frame(width: width * 2)
    .offset(x: drifting ? -width * 0.35 : width * 0.35)
    .frame(width: width)
    .clipped()
    .mask { Self.sides(edge: 0.3) }
  }

  private func shelf(width: CGFloat) -> some View {
    let dark = colorScheme == .dark
    return ZStack(alignment: .bottom) {
      // A faint wash of the same colours rising from the line.
      colours(width: width)
        .frame(height: 70)
        .mask {
          LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
        }
        .opacity(dark ? 0.22 : 0.16)
      // The glow around the line.
      colours(width: width)
        .frame(height: 8)
        .blur(radius: 10)
        .opacity(dark ? 0.9 : 0.7)
        .offset(y: 3)
      // The line itself.
      colours(width: width)
        .frame(height: 1.5)
        .opacity(dark ? 1 : 0.85)
    }
    .frame(width: width, height: 90, alignment: .bottom)
  }
}
