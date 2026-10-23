import AppKit
import Defaults
import ImageIO
import UniformTypeIdentifiers

/// One quick action on a clipboard card: convert an image, resize it, share a
/// file. The same engines as the drop wheel, driven from the card bar.
///
/// Every action that produces something writes it to the pasteboard, so the
/// poller picks it up and it lands in history as a new card — the same route
/// screen text capture and the screenshot editor take.
struct CardAction: Identifiable {
  enum Group: String, CaseIterable {
    case convert = "Convert to"
    case resize = "Resize"
    case share = "Share"
    case file = "File"
  }

  var id: String { "\(group.rawValue).\(title)" }
  let title: String
  let systemImage: String
  let group: Group
  let perform: @MainActor () -> Void
}

@MainActor
enum CardActions {
  static func actions(for item: HistoryItem) -> [CardAction] {
    var actions: [CardAction] = []
    let fileURLs = item.fileURLs

    if hasImage(item) {
      for format in ImageExportFormat.available {
        actions.append(CardAction(title: format.title, systemImage: "arrow.triangle.2.circlepath", group: .convert) {
          run("Converted to \(format.title)") { try export(item, as: format) }
        })
      }

      actions.append(CardAction(title: "Compress (JPEG)", systemImage: "arrow.down.right.and.arrow.up.left", group: .resize) {
        run("Compressed") { try export(item, as: .jpeg, quality: 0.6, suffix: "compressed") }
      })
      for scale in [0.5, 0.25] {
        let percent = Int(scale * 100)
        actions.append(CardAction(title: "\(percent) %", systemImage: "arrow.down.forward.and.arrow.up.backward", group: .resize) {
          run("Resized to \(percent) %") { try export(item, as: .png, scale: scale, suffix: "\(percent)pct") }
        })
      }

      actions.append(CardAction(title: "Save to Downloads", systemImage: "arrow.down.circle", group: .share) {
        run(nil) {
          let url = try fileURLs.first.flatMap { ImageConverter.isImageFile($0) ? $0 : nil } ?? export(item, as: .png, toPasteboard: false)
          let saved = try saveToDownloads(url)
          NSWorkspace.shared.activateFileViewerSelecting([saved])
        }
      })
      actions.append(CardAction(title: "AirDrop", systemImage: "airplayaudio", group: .share) {
        run(nil) {
          let url = try fileURLs.first ?? export(item, as: .png, toPasteboard: false)
          NSSharingService(named: .sendViaAirDrop)?.perform(withItems: [url])
        }
      })
    }

    if !fileURLs.isEmpty {
      actions.append(CardAction(title: "Copy Path", systemImage: "doc.on.doc", group: .file) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(fileURLs.map(\.path).joined(separator: "\n"), forType: .string)
        finish(success: true, message: "Path copied")
      })
      actions.append(CardAction(title: "Reveal in Finder", systemImage: "folder", group: .file) {
        NSWorkspace.shared.activateFileViewerSelecting(fileURLs)
        finish(success: true, message: nil)
      })
      actions.append(CardAction(title: "Open in Terminal", systemImage: "terminal", group: .file) {
        openInTerminal(fileURLs[0])
        finish(success: true, message: nil)
      })
    }

    return actions
  }

  /// The same actions as an AppKit menu, for the ⌘K shortcut, which has no
  /// SwiftUI context menu to hang off.
  static func menu(for item: HistoryItem) -> NSMenu {
    let menu = NSMenu()
    let actions = actions(for: item)

    for group in CardAction.Group.allCases {
      let grouped = actions.filter { $0.group == group }
      guard !grouped.isEmpty else { continue }

      if !menu.items.isEmpty {
        menu.addItem(.separator())
      }
      menu.addItem(.sectionHeader(title: group.rawValue))
      for action in grouped {
        let menuItem = ClosureMenuItem(title: action.title, action: action.perform)
        menuItem.image = NSImage(systemSymbolName: action.systemImage, accessibilityDescription: nil)
        menu.addItem(menuItem)
      }
    }

    if menu.items.isEmpty {
      menu.addItem(withTitle: "No actions for this item", action: nil, keyEquivalent: "")
    }
    return menu
  }

  // MARK: - Image sources

  private static func hasImage(_ item: HistoryItem) -> Bool {
    if item.imageData != nil { return true }
    guard item.fileURLs.count == 1, let url = item.fileURLs.first else { return false }
    return ImageConverter.isImageFile(url) && FileManager.default.isReadableFile(atPath: url.path)
  }

  private static func imageSource(for item: HistoryItem) -> CGImageSource? {
    if let data = item.imageData {
      return CGImageSourceCreateWithData(data as CFData, nil)
    }
    if let url = item.fileURLs.first {
      return CGImageSourceCreateWithURL(url as CFURL, nil)
    }
    return nil
  }

  /// File name for the output: the source file's name if there is one, else a
  /// timestamp, the way screenshots are named.
  private static func baseName(for item: HistoryItem, suffix: String?) -> String {
    let name: String
    if let url = item.fileURLs.first {
      name = url.deletingPathExtension().lastPathComponent
    } else {
      let formatter = DateFormatter()
      formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
      name = "Image \(formatter.string(from: item.firstCopiedAt))"
    }
    return [name, suffix].compactMap { $0 }.joined(separator: " ")
  }

  // MARK: - Conversion

  @discardableResult
  static func export(
    _ item: HistoryItem,
    as format: ImageExportFormat,
    quality: Double = 0.9,
    scale: Double = 1,
    suffix: String? = nil,
    toPasteboard: Bool = true
  ) throws -> URL {
    guard let source = imageSource(for: item) else {
      throw ConversionError.unreadable
    }
    let data = try ImageConverter.data(from: source, as: format, quality: quality, scale: scale)
    let url = try outputDirectory()
      .appendingPathComponent(baseName(for: item, suffix: suffix))
      .appendingPathExtension(for: format.type)
    try data.write(to: url, options: .atomic)

    if toPasteboard {
      // Both the file and the bytes: Finder and chat apps take the file,
      // editors take the image data.
      let pasteboard = NSPasteboard.general
      pasteboard.clearContents()
      pasteboard.writeObjects([url as NSURL])
      pasteboard.setData(data, forType: NSPasteboard.PasteboardType(format.type.identifier))
    }
    return url
  }

  // MARK: - Files

  /// Converted files live in the app's caches, not a temporary directory:
  /// they are referenced by history items, so they must outlive the session.
  private static func outputDirectory() throws -> URL {
    let caches = try FileManager.default.url(
      for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true
    )
    let directory = caches
      .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.naumchedev.fioka", isDirectory: true)
      .appendingPathComponent("Conversions", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  private static func saveToDownloads(_ url: URL) throws -> URL {
    let downloads = try FileManager.default.url(
      for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: true
    )

    let name = url.deletingPathExtension().lastPathComponent
    let ext = url.pathExtension
    var destination = downloads.appendingPathComponent(url.lastPathComponent)
    var counter = 2
    while FileManager.default.fileExists(atPath: destination.path) {
      destination = downloads.appendingPathComponent("\(name) \(counter)").appendingPathExtension(ext)
      counter += 1
    }
    try FileManager.default.copyItem(at: url, to: destination)
    return destination
  }

  static func openInTerminal(_ url: URL) {
    var isDirectory: ObjCBool = false
    FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
    let folder = isDirectory.boolValue ? url : url.deletingLastPathComponent()

    guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else {
      return
    }
    NSWorkspace.shared.open([folder], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
  }

  // MARK: - Feedback

  /// Runs an action, then closes the bar. The result is already on the
  /// clipboard, so ⌘V pastes it straight away.
  private static func run(_ successMessage: String?, _ body: () throws -> Void) {
    do {
      try body()
      finish(success: true, message: successMessage.map { "\($0) — on the clipboard" })
    } catch {
      finish(success: false, message: error.localizedDescription)
    }
  }

  private static func finish(success: Bool, message: String?) {
    AppState.shared.popup.close()
    if Defaults[.capturePlaySound] {
      NSSound(named: success ? "Pop" : "Basso")?.play()
    }
    if let message {
      Notifier.notify(body: message, sound: nil)
    }
  }
}

/// NSMenuItem that runs a closure, so menu items need no target object.
private final class ClosureMenuItem: NSMenuItem {
  private let handler: @MainActor () -> Void

  init(title: String, action handler: @escaping @MainActor () -> Void) {
    self.handler = handler
    super.init(title: title, action: #selector(fire), keyEquivalent: "")
    target = self
  }

  required init(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  @objc private func fire() {
    MainActor.assumeIsolated { handler() }
  }
}
