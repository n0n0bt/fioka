import SwiftUI
import KeyboardShortcuts
import Settings

/// Every shortcut Fioka has, in one place: the global ones that work in any app,
/// and the ones that act on the selected card while the bar is open.
///
/// Strings carry an English default, so locales without a
/// `ShortcutsSettings.strings` table fall back to English rather than raw keys.
struct ShortcutsSettingsPane: View {
  static let allNames: [KeyboardShortcuts.Name] = [
    .popup, .captureText, .captureScreenshot, .pin, .delete, .togglePreview
  ]

  var body: some View {
    Settings.Container(contentWidth: 450) {
      Settings.Section(
        title: "",
        bottomDivider: false
      ) {
        Text(String(localized: "GlobalHeader", defaultValue: "Global — work in any app", table: "ShortcutsSettings"))
          .font(.headline)
      }

      Settings.Section(label: {
        Text(String(localized: "Open", defaultValue: "Open card bar:", table: "ShortcutsSettings"))
      }) {
        KeyboardShortcuts.Recorder(for: .popup, onChange: { newShortcut in
          if newShortcut == nil {
            AppState.shared.popup.deinitEventsMonitor()
          } else {
            AppState.shared.popup.initEventsMonitor()
          }
        })
        .help(Text(String(localized: "OpenTooltip", defaultValue: "Opens the card bar.\nDefault: ⇧⌘V.",
                          table: "ShortcutsSettings")))
      }

      Settings.Section(label: {
        Text(String(localized: "CaptureText", defaultValue: "Capture text:", table: "ShortcutsSettings"))
      }) {
        KeyboardShortcuts.Recorder(for: .captureText)
          .help(Text(String(localized: "CaptureTextTooltip",
                            defaultValue: "Select a screen region and copy the text in it.\nDefault: ⇧⌘2.",
                            table: "ShortcutsSettings")))
      }

      Settings.Section(
        bottomDivider: true,
        label: {
          Text(String(localized: "Screenshot", defaultValue: "Screenshot editor:", table: "ShortcutsSettings"))
        }
      ) {
        KeyboardShortcuts.Recorder(for: .captureScreenshot)
          .help(Text(String(localized: "ScreenshotTooltip",
                            defaultValue: "Take a screenshot and open it in the editor.\nDefault: ⌃⌥⌘4.",
                            table: "ShortcutsSettings")))
      }

      Settings.Section(title: "") {
        Text(String(localized: "BarHeader", defaultValue: "In the card bar", table: "ShortcutsSettings"))
          .font(.headline)
      }

      Settings.Section(label: {
        Text(String(localized: "Pin", defaultValue: "Pin:", table: "ShortcutsSettings"))
      }) {
        KeyboardShortcuts.Recorder(for: .pin)
          .help(Text(String(localized: "PinTooltip", defaultValue: "Pin the selected card.\nDefault: ⌥P.",
                            table: "ShortcutsSettings")))
      }

      Settings.Section(label: {
        Text(String(localized: "Delete", defaultValue: "Delete:", table: "ShortcutsSettings"))
      }) {
        KeyboardShortcuts.Recorder(for: .delete)
          .help(Text(String(localized: "DeleteTooltip", defaultValue: "Delete the selected card.\nDefault: ⌥⌫.",
                            table: "ShortcutsSettings")))
      }

      Settings.Section(
        bottomDivider: true,
        label: {
          Text(String(localized: "Preview", defaultValue: "Preview:", table: "ShortcutsSettings"))
        }
      ) {
        KeyboardShortcuts.Recorder(for: .togglePreview)
          .help(Text(String(localized: "PreviewTooltip",
                            defaultValue: "Show a preview with more information.\nDefault: ⌃Space.",
                            table: "ShortcutsSettings")))
      }

      Settings.Section(title: "") {
        Button {
          KeyboardShortcuts.reset(Self.allNames)
          AppState.shared.popup.initEventsMonitor()
        } label: {
          Text(String(localized: "Reset", defaultValue: "Restore defaults", table: "ShortcutsSettings"))
        }
      }
    }
  }
}

#Preview {
  ShortcutsSettingsPane()
    .environment(\.locale, .init(identifier: "en"))
}
