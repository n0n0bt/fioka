import Defaults
import SwiftUI

struct HintRow: Identifiable {
  let id = UUID()
  let keys: [String]
  let label: String
}

struct HintCard: Identifiable {
  let id: String
  let title: String
  let symbol: String
  let subtitle: String
  let gradient: [Color]
  let rows: [HintRow]
  let footer: String

  /// Shown at the head of the carousel until dismissed. Two cards only: any
  /// more and they stop being a hint and start being the content.
  static let all: [HintCard] = [
    HintCard(
      id: "shortcuts",
      title: "Shortcuts",
      symbol: "keyboard",
      subtitle: "How this works",
      gradient: [
        Color(hex: 0x3A3550),
        Brand.ink
      ],
      rows: [
        HintRow(keys: ["⌘", "⇧", "V"], label: "Open this bar"),
        HintRow(keys: ["↵"], label: "Paste it"),
        HintRow(keys: ["←", "→"], label: "Move between cards"),
        HintRow(keys: ["⌘", "1"], label: "Pick by number"),
        HintRow(keys: ["⌥", "P"], label: "Pin to keep"),
        HintRow(keys: ["esc"], label: "Close")
      ],
      footer: "Just type to search"
    ),
    HintCard(
      id: "capture",
      title: "Grab text",
      symbol: "text.viewfinder",
      subtitle: "Anything on screen",
      gradient: [
        Brand.pink,
        Brand.violet
      ],
      rows: [
        HintRow(keys: ["⌘", "⇧", "2"], label: "Capture text on screen"),
        HintRow(keys: [], label: "Drag a box over anything"),
        HintRow(keys: [], label: "Images, video, PDFs, UI"),
        HintRow(keys: [], label: "The text lands here")
      ],
      footer: "Text you can't select, copied"
    )
  ]
}

/// A card that explains the app rather than holding clipboard content. Shares
/// the shape and chrome of `CardItemView` so the row reads as one strip, but
/// uses a neutral gradient so it is clearly not something you copied.
struct HintCardView: View {
  let hint: HintCard

  @Environment(\.colorScheme) private var colorScheme
  @State private var isHovering = false

  private static let cornerRadius = CardItemView.cornerRadius

  private var shape: RoundedRectangle {
    RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
  }

  var body: some View {
    VStack(spacing: 0) {
      header
      content
    }
    .frame(width: CardItemView.width, height: CardItemView.height)
    .background {
      shape.fill(Color(nsColor: .textBackgroundColor))
    }
    .clipShape(shape)
    .overlay {
      shape.strokeBorder(
        Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.09),
        lineWidth: 1
      )
    }
    .shadow(color: .black.opacity(colorScheme == .dark ? 0.45 : 0.14), radius: 4, y: 2)
    .overlay(alignment: .topTrailing) {
      if isHovering {
        dismissButton
      }
    }
    .onHover { isHovering = $0 }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(Text("\(hint.title) hints"))
  }

  private var header: some View {
    HStack(alignment: .center, spacing: 6) {
      VStack(alignment: .leading, spacing: 2) {
        Text(hint.title)
          .font(.system(size: 14, weight: .bold))
          .foregroundStyle(.white)
        Text(hint.subtitle)
          .font(.system(size: 11))
          .foregroundStyle(.white.opacity(0.82))
      }

      Spacer(minLength: 0)

      // Stands where a content card shows its source app icon.
      Image(systemName: hint.symbol)
        .font(.system(size: 22, weight: .regular))
        .foregroundStyle(.white.opacity(0.92))
        .frame(width: 40, height: 40)
    }
    .padding(.leading, 12)
    .padding(.trailing, 8)
    .frame(height: CardItemView.headerHeight)
    .frame(maxWidth: .infinity)
    .background {
      LinearGradient(colors: hint.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
  }

  private var content: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 7) {
        ForEach(hint.rows) { row in
          HStack(alignment: .center, spacing: 5) {
            if row.keys.isEmpty {
              // Continuation line: align with the text above, not the keys.
              Text("·")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.tertiary)
                .frame(width: 12)
            } else {
              HStack(spacing: 2) {
                ForEach(Array(row.keys.enumerated()), id: \.offset) { _, key in
                  keyCap(key)
                }
              }
            }

            Text(row.label)
              .font(.system(size: 10.5))
              .foregroundStyle(.secondary)
              .lineLimit(1)
              .minimumScaleFactor(0.85)

            Spacer(minLength: 0)
          }
        }
      }
      .padding(.horizontal, 10)
      .padding(.top, 10)

      Spacer(minLength: 0)

      Rectangle()
        .fill(Color.primary.opacity(0.08))
        .frame(height: 1)

      Text(hint.footer)
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(.tertiary)
        .lineLimit(1)
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
    }
  }

  private func keyCap(_ key: String) -> some View {
    Text(key)
      .font(.system(size: 9.5, weight: .semibold, design: .rounded))
      .foregroundStyle(.primary.opacity(0.75))
      .frame(minWidth: 13)
      .padding(.horizontal, 3)
      .padding(.vertical, 2)
      .background(
        RoundedRectangle(cornerRadius: 4, style: .continuous)
          .fill(Color.primary.opacity(0.09))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 4, style: .continuous)
          .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
      )
  }

  private var dismissButton: some View {
    Button {
      Defaults[.showHintCards] = false
    } label: {
      Image(systemName: "xmark.circle.fill")
        .font(.system(size: 13))
        .foregroundStyle(.white.opacity(0.85))
        .shadow(color: .black.opacity(0.3), radius: 1)
    }
    .buttonStyle(.plain)
    .padding(7)
    .help("Hide these hints")
  }
}
