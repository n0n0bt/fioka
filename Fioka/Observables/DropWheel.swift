import Foundation
import Observation

/// One slice of the drop wheel: a format to convert to, a tool, or an action.
struct WheelSegment: Identifiable {
  let id: String
  /// Shown on the slice: "PNG", or a short tool name under its icon.
  let title: String
  /// Tools and actions carry an icon; formats are text only.
  let systemImage: String?
  /// Shown under the wheel: "Convert to PNG".
  let caption: String
  /// Runs on the dropped files and returns any files it produced.
  let perform: @MainActor ([URL]) async throws -> [URL]
}

/// State behind the drop wheel: which set of slices is showing and which one
/// the drag is over. Driven by `DropWheelController`, drawn by `DropWheelView`.
@Observable
final class DropWheel {
  enum Mode {
    /// ⇧ — convert to another format.
    case formats
    /// ⌘ — tools that keep the format: compress, resize, …
    case tools
    /// ⌃ — file actions: AirDrop, copy, …
    case actions
  }

  var mode: Mode = .formats
  var segments: [WheelSegment] = []
  /// The slice a drop would run. Stays on the last one hovered while the
  /// cursor is in the hub, so dropping in the centre runs what it names.
  var hovered: Int = 0
  var isVisible = false

  var hoveredSegment: WheelSegment? {
    segments.indices.contains(hovered) ? segments[hovered] : nil
  }

  /// Which slice a point falls in, given its offset from the wheel's centre
  /// in a y-up coordinate space (AppKit's). Returns nil inside the hub or
  /// well outside the ring, where the hovered slice should not change.
  static func segmentIndex(dx: CGFloat, dy: CGFloat, count: Int, innerRadius: CGFloat, outerRadius: CGFloat) -> Int? {
    guard count > 0 else { return nil }
    let distance = hypot(dx, dy)
    guard distance >= innerRadius, distance <= outerRadius + 40 else { return nil }

    // Clockwise from twelve o'clock, where the first slice is centred.
    var angle = atan2(dx, dy)
    if angle < 0 { angle += 2 * .pi }
    let step = 2 * .pi / CGFloat(count)
    return Int((angle + step / 2) / step) % count
  }
}
