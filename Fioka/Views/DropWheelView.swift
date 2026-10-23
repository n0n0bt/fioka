import SwiftUI

/// The radial menu: slices around a hub, the one under the drag lit in the brand gradient,
/// its name in the hub and a caption underneath. Light-only, since it floats
/// over whatever is on screen and needs to look the same everywhere.
struct DropWheelView: View {
  let wheel: DropWheel

  static let outerRadius: CGFloat = 190
  static let innerRadius: CGFloat = 70
  /// Space above the wheel, so the shadow is not clipped by the panel.
  static let topInset: CGFloat = 20
  static let panelSize = NSSize(width: 420, height: 470)

  /// Spans the whole wheel, so each slice lights in its own part of the
  /// gradient: pink at the top left, through violet, to cyan.
  private static let highlight = LinearGradient(
    colors: [Brand.pink, Brand.violet, Brand.cyan],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
  )
  private static let gap: CGFloat = 7
  private static let cornerRadius: CGFloat = 12

  var body: some View {
    VStack(spacing: 14) {
      ZStack {
        Circle()
          .fill(Color(hex: 0xEAE8F3))
          .shadow(color: .black.opacity(0.22), radius: 18, y: 8)

        ForEach(Array(wheel.segments.enumerated()), id: \.element.id) { index, segment in
          slice(index: index, segment: segment)
        }

        hub
      }
      .frame(width: Self.outerRadius * 2, height: Self.outerRadius * 2)

      if let caption = wheel.hoveredSegment?.caption {
        Text(caption)
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(Color(white: 0.25))
          .padding(.horizontal, 12)
          .padding(.vertical, 5)
          .background(Color.white.opacity(0.92), in: Capsule())
          .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
      }
    }
    .padding(.top, Self.topInset)
    .frame(width: Self.panelSize.width, height: Self.panelSize.height, alignment: .top)
    .scaleEffect(wheel.isVisible ? 1 : 0.85)
    .opacity(wheel.isVisible ? 1 : 0)
    .animation(.spring(response: 0.28, dampingFraction: 0.78), value: wheel.isVisible)
    .animation(.easeOut(duration: 0.12), value: wheel.hovered)
    .environment(\.colorScheme, .light)
  }

  // MARK: - Slices

  private var step: Angle { .degrees(360 / Double(max(wheel.segments.count, 1))) }

  private func slice(index: Int, segment: WheelSegment) -> some View {
    let isHovered = index == wheel.hovered
    let center = step * Double(index)
    let shape = AnnularSector(
      start: center - step / 2,
      end: center + step / 2,
      innerRadius: Self.innerRadius + 6,
      outerRadius: Self.outerRadius - 6,
      inset: Self.gap / 2 + Self.cornerRadius
    )
    let fill = isHovered ? AnyShapeStyle(Self.highlight) : AnyShapeStyle(Color(hex: 0xFBFAFF))

    return ZStack {
      if wheel.segments.count == 1 {
        // A lone slice would close on itself with a seam; make it a ring.
        let outerInset = 6 + Self.gap / 2
        let thickness = (Self.outerRadius - outerInset) - (Self.innerRadius + outerInset)
        Circle()
          .inset(by: outerInset)
          .strokeBorder(fill, lineWidth: thickness)
      } else {
        // Filling the inset sector and stroking it with a round join grows it
        // back out by the corner radius, which rounds every corner.
        shape.fill(fill)
        shape.stroke(fill, style: StrokeStyle(lineWidth: Self.cornerRadius * 2, lineJoin: .round))
      }
    }
    // One shadow for the merged slice; otherwise each layer casts its own and
    // the stroke's shadow draws an outline inside the fill.
    .compositingGroup()
    .shadow(color: .black.opacity(isHovered ? 0.18 : 0.07), radius: isHovered ? 6 : 2, y: 1)
    .overlay {
      label(segment, isHovered: isHovered)
        .position(position(at: center, radius: (Self.innerRadius + Self.outerRadius) / 2 + 6))
    }
  }

  @ViewBuilder
  private func label(_ segment: WheelSegment, isHovered: Bool) -> some View {
    let color: Color = isHovered ? .white : Color(white: 0.08)
    if let symbol = segment.systemImage {
      VStack(spacing: 6) {
        Image(systemName: symbol)
          .font(.system(size: 19, weight: .medium))
        Text(segment.title.uppercased())
          .font(.system(size: 11, weight: .semibold))
          .tracking(0.8)
      }
      .foregroundStyle(color)
    } else {
      Text(segment.title.uppercased())
        .font(.system(size: 21, weight: .bold))
        .tracking(0.6)
        .foregroundStyle(color)
    }
  }

  private var hub: some View {
    ZStack {
      Circle()
        .fill(Color(white: 0.965))
        .frame(width: Self.innerRadius * 2 - 8, height: Self.innerRadius * 2 - 8)

      if let segment = wheel.hoveredSegment {
        Text(segment.title.uppercased())
          .font(.system(size: segment.systemImage == nil ? 15 : 11, weight: .semibold))
          .tracking(0.8)
          .foregroundStyle(Color(white: 0.08))
          .lineLimit(1)
          .minimumScaleFactor(0.7)
          .padding(.horizontal, 14)
          .padding(.vertical, 8)
          .frame(maxWidth: Self.innerRadius * 2 - 24)
          .background(.white, in: Capsule())
          .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
      }
    }
  }

  /// A point on the wheel, `angle` clockwise from twelve o'clock.
  private func position(at angle: Angle, radius: CGFloat) -> CGPoint {
    CGPoint(
      x: Self.outerRadius + sin(angle.radians) * radius,
      y: Self.outerRadius - cos(angle.radians) * radius
    )
  }
}

/// A ring slice between two angles measured clockwise from twelve o'clock,
/// shrunk by `inset` on every side.
private struct AnnularSector: Shape {
  let start: Angle
  let end: Angle
  let innerRadius: CGFloat
  let outerRadius: CGFloat
  let inset: CGFloat

  func path(in rect: CGRect) -> Path {
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let outer = outerRadius - inset
    let inner = innerRadius + inset
    // Same straight-line inset along both radial edges, so the gap between
    // neighbours is even rather than wedge-shaped.
    let outerPad = Angle.radians(Double(asin(min(1, inset / outer))))
    let innerPad = Angle.radians(Double(asin(min(1, inset / inner))))

    // Path angles start at three o'clock; in SwiftUI's flipped space
    // `clockwise: false` draws clockwise on screen.
    let offset = Angle.degrees(90)
    var path = Path()
    path.addArc(center: center, radius: outer,
                startAngle: start + outerPad - offset, endAngle: end - outerPad - offset, clockwise: false)
    path.addArc(center: center, radius: inner,
                startAngle: end - innerPad - offset, endAngle: start + innerPad - offset, clockwise: true)
    path.closeSubpath()
    return path
  }
}
