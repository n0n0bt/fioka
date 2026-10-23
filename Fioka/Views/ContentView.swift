import Defaults
import SwiftData
import SwiftUI

struct ContentView: View {
  @State private var appState = AppState.shared
  @State private var modifierFlags = ModifierFlags()
  @State private var scenePhase: ScenePhase = .background

  @Default(.useCardLayout) private var useCardLayout
  @Default(.cardDrum) private var cardDrum

  @FocusState private var searchFocused: Bool

  var body: some View {
    ZStack {
      if useCardLayout && cardDrum {
        DrumGlowView()
      } else if useCardLayout {
        PanelBackdropView()
      } else if #available(macOS 26.0, *) {
        GlassEffectView()
      } else {
        VisualEffectView()
      }

      KeyHandlingView(searchQuery: $appState.history.searchQuery, searchFocused: $searchFocused) {
        VStack(spacing: 0) {
          if useCardLayout {
            cardLayout
          } else {
            listLayout
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .task {
        try? await appState.history.load()
      }
    }
    .animation(.easeInOut(duration: 0.2), value: appState.searchVisible)
    .environment(appState)
    .environment(modifierFlags)
    .environment(\.scenePhase, scenePhase)
    // FloatingPanel is not a scene, so let's implement custom scenePhase..
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) {
      if let window = $0.object as? NSWindow,
         let bundleIdentifier = Bundle.main.bundleIdentifier,
         window.identifier == NSUserInterfaceItemIdentifier(bundleIdentifier) {
        scenePhase = .active
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) {
      if let window = $0.object as? NSWindow,
         let bundleIdentifier = Bundle.main.bundleIdentifier,
         window.identifier == NSUserInterfaceItemIdentifier(bundleIdentifier) {
        scenePhase = .background
      }
    }
  }

  /// The card bar: search on top, one horizontal row of cards below.
  /// The slideout preview is intentionally left out — each card already shows
  /// its own preview, so the panel stays a fixed height.
  private var cardLayout: some View {
    VStack(spacing: 0) {
      HeaderView(
        controller: appState.preview,
        searchFocused: $searchFocused
      )

      // The revolver by default; the flat strip behind `cardDrum`.
      if cardDrum {
        CardDrumView()
      } else {
        CardCarouselView()
          .animation(.default.speed(3), value: appState.history.items)
      }
    }
    // The panel spans the full screen width; without this the header and
    // carousel size to their content and sit in a narrow left-aligned column.
    .frame(maxWidth: .infinity)
    .onAppear {
      searchFocused = true
    }
    .onMouseMove {
      appState.navigator.isKeyboardNavigating = false
    }
  }

  /// The original vertical list, kept behind the `useCardLayout` default so
  /// the two can be compared without reverting anything.
  private var listLayout: some View {
    SlideoutView(controller: appState.preview) {
      HeaderView(
        controller: appState.preview,
        searchFocused: $searchFocused
      )

      VStack(alignment: .leading, spacing: 0) {
        HistoryListView(
          searchQuery: $appState.history.searchQuery,
          searchFocused: $searchFocused
        )

        FooterView(footer: appState.footer)
      }
      .animation(.default.speed(3), value: appState.history.items)
      .animation(
        .default.speed(3),
        value: appState.history.pasteStack?.id
      )
      .padding(.horizontal, Popup.horizontalPadding)
      .onAppear {
        searchFocused = true
      }
      .onMouseMove {
        appState.navigator.isKeyboardNavigating = false
      }
    } slideout: {
      SlideoutContentView()
    }
    .frame(minHeight: 0)
    .layoutPriority(1)
  }
}

#Preview {
  ContentView()
    .environment(\.locale, .init(identifier: "en"))
    .modelContainer(Storage.shared.container)
}
