import Defaults
import SwiftUI

/// Horizontal strip of clipboard cards, pinned items first.
///
/// Replaces `HistoryListView` when the card layout is enabled. Selection and
/// keyboard navigation still run through `NavigationManager`, so left/right
/// here means exactly what up/down means in the list.
struct CardCarouselView: View {
  @Environment(AppState.self) private var appState

  @Default(.showHintCards) private var showHintCards
  @Environment(\.scenePhase) private var scenePhase

  /// Just enough above the cards for the selection ring.
  static let topPadding: CGFloat = 6
  static let bottomPadding: CGFloat = 24
  static let spacing: CGFloat = 24

  /// Height the panel needs to show one row of cards.
  static var contentHeight: CGFloat { CardItemView.height + topPadding + bottomPadding }

  private var pinnedItems: [HistoryItemDecorator] {
    appState.history.pinnedItems.filter(\.isVisible)
  }

  private var unpinnedItems: [HistoryItemDecorator] {
    appState.history.unpinnedItems.filter(\.isVisible)
  }

  private var isEmpty: Bool { pinnedItems.isEmpty && unpinnedItems.isEmpty }

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView(.horizontal, showsIndicators: false) {
        LazyHStack(alignment: .center, spacing: Self.spacing) {
          // Hints live at the head of the row and are not history items, so
          // keyboard navigation skips them without any special-casing.
          if showHintCards {
            ForEach(HintCard.all) { hint in
              HintCardView(hint: hint)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }

            if !pinnedItems.isEmpty || !unpinnedItems.isEmpty {
              separator
            }
          }

          ForEach(pinnedItems) { item in
            CardItemView(item: item)
              .transition(.scale(scale: 0.9).combined(with: .opacity))
          }

          if !pinnedItems.isEmpty && !unpinnedItems.isEmpty {
            separator
          }

          ForEach(Array(unpinnedItems.enumerated()), id: \.element.id) { index, item in
            CardItemView(item: item, position: index + 1)
              .transition(.scale(scale: 0.9).combined(with: .opacity))
          }
        }
        .padding(.horizontal, Self.spacing)
        .padding(.top, Self.topPadding)
        .padding(.bottom, Self.bottomPadding)
      }
      .frame(maxWidth: .infinity)
      .frame(height: Self.contentHeight)
      .overlay {
        if isEmpty && !showHintCards {
          emptyState
        }
      }
      // Upstream does this in HistoryListView, which the card layout never
      // renders: every time the bar opens, start on the newest copy rather
      // than whatever happened to be selected last time.
      .onChange(of: scenePhase) {
        if scenePhase == .active {
          appState.navigator.isKeyboardNavigating = true
          appState.navigator.select(
            item: appState.history.unpinnedItems.first ?? appState.history.pinnedItems.first
          )
        } else {
          appState.navigator.isKeyboardNavigating = true
        }
      }
      .onChange(of: appState.navigator.scrollTarget) { _, target in
        guard let target else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
          proxy.scrollTo(target, anchor: .center)
        }
      }
    }
  }

  private var separator: some View {
    RoundedRectangle(cornerRadius: 1, style: .continuous)
      .fill(Color.primary.opacity(0.14))
      .frame(width: 2, height: CardItemView.height * 0.55)
      .padding(.horizontal, 3)
  }

  private var emptyState: some View {
    VStack(spacing: 9) {
      Image(systemName: appState.history.searchQuery.isEmpty
            ? "doc.on.clipboard"
            : "magnifyingglass")
        .font(.system(size: 26, weight: .light))
        .foregroundStyle(.tertiary)

      Text(appState.history.searchQuery.isEmpty
           ? "Nothing copied yet"
           : "No matches")
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.secondary)
    }
  }
}
