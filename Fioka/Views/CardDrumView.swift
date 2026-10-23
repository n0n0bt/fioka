import AppKit
import SwiftUI

/// The card bar as a revolver: the selected card faces you in the middle and
/// the cards on either side sit on a drum, turned away, smaller and fainter.
/// ← → (or a sideways swipe) spins the drum one card at a time.
///
/// Selection still runs through `NavigationManager`, exactly as in the strip:
/// the drum only reads `leadHistoryItem` and turns to it.
struct CardDrumView: View {
  @Environment(AppState.self) private var appState
  @Environment(\.scenePhase) private var scenePhase

  /// Cards shown on each side of the centre; further ones are hidden.
  private static let reach = 3
  /// Horizontal distance between neighbouring cards, in points.
  private static let spacing: CGFloat = 196
  /// How far each step turns a card away from you.
  private static let turn: Double = 38

  @State private var scrollMonitor: Any?
  /// 0 while the bar opens, with every card folded behind the front one;
  /// 1 once they have fanned out onto the drum.
  @State private var spread: Double = 1
  @State private var scrollAccumulator: CGFloat = 0

  private var items: [HistoryItemDecorator] {
    (appState.history.pinnedItems + appState.history.unpinnedItems).filter(\.isVisible)
  }

  private var selectedIndex: Int {
    guard let id = appState.navigator.leadHistoryItem?.id else { return 0 }
    return items.firstIndex { $0.id == id } ?? 0
  }

  var body: some View {
    let items = self.items
    let centre = selectedIndex
    let pinnedCount = appState.history.pinnedItems.filter(\.isVisible).count

    ZStack {
      ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
        if let offset = Self.offset(of: index, from: centre, count: items.count) {
          card(item, offset: offset, position: index >= pinnedCount ? index - pinnedCount + 1 : nil)
        }
      }
    }
    .frame(maxWidth: .infinity)
    .frame(height: CardCarouselView.contentHeight)
    .animation(.spring(response: 0.38, dampingFraction: 0.82), value: centre)
    .contentShape(Rectangle())
    .gesture(swipe)
    .overlay {
      if items.isEmpty {
        emptyState
      }
    }
    // Every time the bar opens, start on the newest copy.
    .onChange(of: scenePhase) {
      appState.navigator.isKeyboardNavigating = true
      if scenePhase == .active {
        appState.navigator.select(item: appState.history.unpinnedItems.first ?? appState.history.pinnedItems.first)
        fanOut()
        startScrollMonitor()
      } else {
        stopScrollMonitor()
      }
    }
    .onAppear {
      fanOut()
      startScrollMonitor()
    }
    .onDisappear(perform: stopScrollMonitor)
  }

  /// Where a card sits relative to the front one, or nil if it is hidden.
  /// No wrap-around: the newest copy opens in front with nothing to its
  /// left, and the left fills with the cards you have passed as you go.
  static func offset(of index: Int, from centre: Int, count: Int) -> Int? {
    let offset = index - centre
    return abs(offset) <= reach ? offset : nil
  }

  @ViewBuilder
  private func card(_ item: HistoryItemDecorator, offset: Int, position: Int?) -> some View {
    let distance = CGFloat(abs(offset))
    let isCentre = offset == 0

    CardItemView(item: item, position: position)
      // Only the front card is live; the others just turn to the front.
      .allowsHitTesting(isCentre)
      .overlay {
        if !isCentre {
          Color.clear
            .contentShape(Rectangle())
            .onTapGesture { appState.navigator.select(item: item) }
        }
      }
      .scaleEffect(1 - distance * 0.14 * spread)
      .rotation3DEffect(.degrees(Double(-offset) * Self.turn * spread), axis: (0, 1, 0), perspective: 0.55)
      .opacity((1 - Double(distance) * 0.22) * (isCentre ? 1 : spread))
      .blur(radius: distance * 0.6)
      .offset(x: CGFloat(offset) * Self.spacing * spread)
      // Nearer cards land first, so the drum deals itself out from the front.
      .animation(.spring(response: 0.5, dampingFraction: 0.78).delay(Double(distance) * 0.05), value: spread)
      .zIndex(-Double(distance))
      .transition(.opacity)
  }

  /// Folds the cards behind the front one, then lets them fan out.
  private func fanOut() {
    var fold = Transaction()
    fold.disablesAnimations = true
    withTransaction(fold) { spread = 0 }
    DispatchQueue.main.async { spread = 1 }
  }

  /// A drag across the drum spins it, one card per step.
  private var swipe: some Gesture {
    DragGesture(minimumDistance: 12)
      .onEnded { value in
        let steps = Int((-value.translation.width / (Self.spacing * 0.6)).rounded())
        spin(by: steps)
      }
  }

  private func spin(by steps: Int) {
    guard steps != 0, !items.isEmpty else { return }
    let target = min(max(selectedIndex + steps, 0), items.count - 1)
    appState.navigator.isKeyboardNavigating = true
    appState.navigator.select(item: items[target])
  }

  /// Trackpad and mouse-wheel scrolling spin the drum too. A local monitor,
  /// because SwiftUI has no scroll-wheel event for a view that isn't a
  /// scroll view; it only sees events for this app's own windows.
  private func startScrollMonitor() {
    guard scrollMonitor == nil else { return }
    scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
      let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) ? event.scrollingDeltaX : event.scrollingDeltaY
      scrollAccumulator += event.hasPreciseScrollingDeltas ? delta : delta * 12
      let threshold: CGFloat = 46
      if abs(scrollAccumulator) >= threshold {
        spin(by: scrollAccumulator > 0 ? -1 : 1)
        scrollAccumulator = 0
      }
      if event.phase == .ended || event.momentumPhase == .ended {
        scrollAccumulator = 0
      }
      return event
    }
  }

  private func stopScrollMonitor() {
    if let scrollMonitor {
      NSEvent.removeMonitor(scrollMonitor)
    }
    scrollMonitor = nil
  }

  private var emptyState: some View {
    VStack(spacing: 9) {
      Image(systemName: appState.history.searchQuery.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
        .font(.system(size: 26, weight: .light))
        .foregroundStyle(.tertiary)
      Text(appState.history.searchQuery.isEmpty ? "Nothing copied yet" : "No matches")
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.secondary)
    }
  }
}
