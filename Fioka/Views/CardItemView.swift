import Defaults
import SwiftUI

/// A clipboard entry as a card: a header tinted by the application the content
/// came from, with that app's icon, and a preview beneath.
///
/// The header takes its colour from the source app rather than the content
/// type, because that is what makes a long row scannable — you recognise where
/// something came from before you read any of it. The type is still named in
/// the header, so nothing is lost. Items with no known app fall back to the
/// content type's colour.
struct CardItemView: View {
  @Bindable var item: HistoryItemDecorator
  /// 1-based place in the row, shown in the footer badge. Pinned cards have none.
  var position: Int?

  @Environment(AppState.self) private var appState
  @Environment(\.colorScheme) private var colorScheme

  @State private var isHovering = false
  @State private var cardFrame: CGRect = .zero

  static let width: CGFloat = 232
  static let height: CGFloat = 232
  static let headerHeight: CGFloat = 48
  static let cornerRadius: CGFloat = 14
  /// Drawn larger than the header and cropped by the card's corner, so the
  /// icon fills the header's trailing end.
  private static let iconSize: CGFloat = 62

  private var kind: CardKind { item.kind }

  private var accent: Color {
    AppAccent.color(for: item.applicationImage, fallback: kind.accent)
  }

  private var shape: RoundedRectangle {
    RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
  }

  private func performSelect() {
    if NSEvent.modifierFlags.contains(.command) && appState.multiSelectionEnabled {
      appState.navigator.addToSelection(item: item)
    } else {
      let flags = NSEvent.ModifierFlags.currentModifierFlags
      Task {
        appState.history.select(item, flags: flags)
      }
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      header
      content
    }
    .frame(width: Self.width, height: Self.height)
    .background(Color(nsColor: .textBackgroundColor))
    .clipShape(shape)
    .overlay {
      shape.strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.06), lineWidth: 1)
    }
    .shadow(
      color: .black.opacity(colorScheme == .dark ? 0.40 : (isHovering ? 0.16 : 0.10)),
      radius: isHovering ? 6 : 3,
      y: 1
    )
    // Selection is a ring in the brand gradient, just outside the card.
    .overlay {
      if item.isSelected {
        SelectionRing(cornerRadius: Self.cornerRadius + 4)
          .padding(-4)
      }
    }
    .animation(.easeOut(duration: 0.12), value: item.isSelected)
    .animation(.easeOut(duration: 0.15), value: isHovering)
    .onHover { isHovering = $0 }
    .id(item.id)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(item.accessibilityLabel))
    .accessibilityAddTraits(item.isSelected ? .isSelected : [])
    .accessibilityIdentifier("copy-history-item")
    .buttonAction(performSelect)
    .contextMenu { actionsMenu }
    .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { frame in
      cardFrame = frame
      if item.isSelected { appState.popup.selectedCardFrame = frame }
    }
    .onChange(of: item.isSelected) { _, selected in
      if selected { appState.popup.selectedCardFrame = cardFrame }
    }
    .hoverSelectionId(item.id)
    .onAppear { item.ensureThumbnailImage() }
  }

  // MARK: - Actions

  /// Right-click menu: the same actions ⌘K opens, grouped into submenus.
  @ViewBuilder
  private var actionsMenu: some View {
    let actions = CardActions.actions(for: item.item)
    ForEach(CardAction.Group.allCases, id: \.self) { group in
      let grouped = actions.filter { $0.group == group }
      if !grouped.isEmpty {
        Menu(group.rawValue) {
          ForEach(grouped) { action in
            Button(action.title, systemImage: action.systemImage) { action.perform() }
          }
        }
      }
    }
  }

  // MARK: - Header

  private var header: some View {
    ZStack(alignment: .leading) {
      LinearGradient(
        colors: [accent.shifted(by: 0.08), accent.shifted(by: -0.14)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )

      HStack(alignment: .center, spacing: 6) {
        VStack(alignment: .leading, spacing: 1) {
          Text(kind.label)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(.white)
          Text(item.relativeCopiedAt)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.85))
            .lineLimit(1)
            .minimumScaleFactor(0.9)
        }

        Spacer(minLength: 0)
      }
      .padding(.leading, 12)

      // Flush to the trailing edge and cropped by the header: the icon is the
      // fastest thing to recognise, so it gets the corner.
      AppImageView(
        appImage: item.applicationImage,
        size: NSSize(width: Self.iconSize, height: Self.iconSize)
      )
      .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
      .offset(x: 7, y: -2)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)

      if item.isPinned {
        Image(systemName: "pin.fill")
          .font(.system(size: 9, weight: .bold))
          .foregroundStyle(.white.opacity(0.9))
          .padding(5)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
          .padding(.leading, 1)
      }
    }
    .frame(height: Self.headerHeight)
    .clipped()
  }

  // MARK: - Content

  @ViewBuilder
  private var content: some View {
    switch kind {
    case .image:
      imageContent

    case .color:
      ZStack {
        kind.accent
        Text(item.cardMetadata)
          .font(.system(size: 16, weight: .heavy, design: .rounded))
          .foregroundStyle(kind.onAccent)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)

    default:
      VStack(alignment: .leading, spacing: 0) {
        preview
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        footer
      }
    }
  }

  private var imageContent: some View {
    ZStack(alignment: .bottom) {
      if let image = item.thumbnailImage ?? item.previewImage {
        // Filled inside an overlay so a tall image is cropped to the card
        // instead of growing the stack and pushing the header off the top.
        Color.clear
          .overlay {
            Image(nsImage: image)
              .resizable()
              .aspectRatio(contentMode: .fill)
          }
          .clipped()
      } else {
        ProgressView()
          .controlSize(.small)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }

      // Floats over the image rather than stealing a strip from it.
      footer
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  @ViewBuilder
  private var preview: some View {
    switch kind {
    case .file:
      VStack(spacing: 8) {
        Image(systemName: "doc.fill")
          .font(.system(size: 34))
          .foregroundStyle(accent.opacity(0.65))
        Text(item.previewText)
          .font(.system(size: 10.5))
          .foregroundStyle(.secondary)
          .lineLimit(2)
          .truncationMode(.middle)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 12)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)

    default:
      Text(item.previewText.shortened(to: 500))
        .font(kind == .code
              ? .system(size: 11.5, weight: .regular, design: .monospaced)
              : .system(size: 13))
        .foregroundStyle(.primary.opacity(0.9))
        .lineSpacing(2)
        .lineLimit(7)
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 12)
        .padding(.top, 11)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
  }

  /// Size or length centred, the row position in a badge on the right. Both
  /// sit on capsules so they stay legible over an image.
  private var footer: some View {
    ZStack {
      if !item.cardMetadata.isEmpty {
        Text(item.cardMetadata)
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
          .padding(.horizontal, 9)
          .padding(.vertical, 3)
          .background(footerCapsule)
          .frame(maxWidth: 150)
      }

      if let position {
        Label("\(position)", systemImage: "text.alignleft")
          .labelStyle(PositionBadgeLabelStyle())
          .padding(.horizontal, 8)
          .padding(.vertical, 3)
          .background(footerCapsule)
          .frame(maxWidth: .infinity, alignment: .trailing)
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.horizontal, 8)
    .padding(.bottom, 8)
    .padding(.top, 4)
  }

  private var footerCapsule: some View {
    Capsule().fill(Color(nsColor: .textBackgroundColor).opacity(0.85))
      .overlay(Capsule().fill(Color.primary.opacity(0.07)))
  }
}

private struct PositionBadgeLabelStyle: LabelStyle {
  func makeBody(configuration: Configuration) -> some View {
    HStack(spacing: 4) {
      configuration.icon
        .font(.system(size: 10, weight: .semibold))
      configuration.title
        .font(.system(size: 12, weight: .medium).monospacedDigit())
    }
    .foregroundStyle(.secondary)
  }
}

/// The selected card's ring: the logo's colours going round it, slowly, so the
/// card in front feels lit rather than outlined.
private struct SelectionRing: View {
  var cornerRadius: CGFloat
  @State private var turning = false

  var body: some View {
    // The gradient turns and the ring is cut out of it. Scaled up so its
    // corners stay covered while it rotates.
    AngularGradient(colors: [Brand.pink, Brand.violet, Brand.cyan, Brand.violet, Brand.pink], center: .center)
      .scaleEffect(1.5)
      .rotationEffect(.degrees(turning ? 360 : 0))
      .mask {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .strokeBorder(lineWidth: 3.5)
      }
      .allowsHitTesting(false)
      .onAppear {
        withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) { turning = true }
      }
  }
}
