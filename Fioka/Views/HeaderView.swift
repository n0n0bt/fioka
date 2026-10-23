import Defaults
import SwiftUI

struct HeaderView: View {
  @State private var appState = AppState.shared

  let controller: SlideoutController

  @Default(.useCardLayout) private var useCardLayout
  @FocusState.Binding var searchFocused: Bool

  var previewPlacement: SlideoutPlacement {
    return controller.placement
  }

  var body: some View {
    if useCardLayout {
      cardHeader
    } else {
      listHeader
    }
  }

  /// A compact, centred search field over the card row. The
  /// height is fixed so `Popup.cardPanelHeight` is right on the first open.
  private var cardHeader: some View {
    ListHeaderView(
      searchFocused: $searchFocused,
      searchQuery: $appState.history.searchQuery,
      fieldHeight: Popup.cardSearchFieldHeight
    )
    .frame(width: 360)
    .frame(maxWidth: .infinity)
    .frame(height: Popup.cardHeaderHeight)
    .opacity(appState.searchVisible ? 1 : 0)
    .accessibilityHidden(!appState.searchVisible)
    .readHeight(appState, into: \.popup.headerHeight)
  }

  private var listHeader: some View {
    HStack(alignment: .top, spacing: 0) {
      HStack(alignment: .center, spacing: 0) {
        ListHeaderView(
          searchFocused: $searchFocused,
          searchQuery: $appState.history.searchQuery
        )
        .padding(.horizontal, Popup.horizontalPadding)

        // The card layout has no slideout to toggle, so the button would be dead.
        if !useCardLayout {
          ToolbarButton {
            controller.togglePreview()
          } label: {
            Image(
              systemName: previewPlacement == .right
                ? "sidebar.left" : "sidebar.right"
            )
          }
          .shortcutKeyHelp(
            name: .togglePreview,
            key: controller.state.isOpen ? "ClosePreview" : "OpenPreview",
            tableName: "PreviewItemView",
            replacementKey: "previewKey"
          )
          .padding(.trailing, Popup.horizontalPadding)
        }
      }
      .opacity(appState.searchVisible ? 1 : 0)
      .accessibilityHidden(!appState.searchVisible)
      .layoutPriority(1)
    }
    .padding(.top, Popup.verticalPadding)
    .padding(.horizontal, 10)
    .animation(.default.speed(3), value: appState.navigator.leadSelection)
    .background(.clear)
    .frame(maxHeight: !appState.searchVisible ? 0 : nil, alignment: .top)
    .readHeight(appState, into: \.popup.headerHeight)
  }
}
