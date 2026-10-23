import SwiftUI

struct SearchFieldView: View {
  var placeholder: LocalizedStringKey
  @Binding var query: String
  var height: CGFloat = 23

  @Environment(AppState.self) private var appState

  var body: some View {
    ZStack {
      if height > 23 {
        // The card bar's pill, which may float with nothing behind it.
        Capsule()
          .fill(.regularMaterial)
          .overlay(Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
          .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
          .frame(height: height)
      } else {
        RoundedRectangle(cornerRadius: Popup.cornerRadius, style: .continuous)
          .fill(Color.secondary)
          .opacity(0.1)
          .frame(height: height)
      }

      HStack {
        Image(systemName: "magnifyingglass")
          .frame(width: 11, height: 11)
          .padding(.leading, height > 23 ? 12 : 5)
          .opacity(0.8)
          .accessibilityHidden(true)

        TextField(placeholder, text: $query)
          .disableAutocorrection(true)
          .lineLimit(1)
          .textFieldStyle(.plain)
          .font(.system(size: height > 23 ? 14 : NSFont.systemFontSize))
          .onSubmit {
            appState.select(flags: .currentModifierFlags)
          }

        if !query.isEmpty {
          Button {
            query = ""
          } label: {
            Image(systemName: "xmark.circle.fill")
              .frame(width: 11, height: 11)
              .padding(.trailing, height > 23 ? 12 : 5)
          }
          .buttonStyle(.plain)
          .opacity(0.9)
          .accessibilityLabel(Text("search_clear_accessibility_label"))
        }
      }
    }
  }
}

#Preview {
  return List {
    SearchFieldView(placeholder: "search_placeholder", query: .constant(""))
    SearchFieldView(placeholder: "search_placeholder", query: .constant("search"))
  }
  .frame(width: 300)
  .environment(\.locale, .init(identifier: "en"))
}
