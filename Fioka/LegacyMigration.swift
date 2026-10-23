import Foundation

/// One-time move from the app's previous identity. Fioka started as a fork of
/// Maccy (bundle ID `org.p0deje.Maccy`); the rename gave it a new bundle ID,
/// which means a new preferences domain and a new Application Support folder.
/// Without this, the first launch would start with no history, no settings
/// and default shortcuts.
///
/// Everything is copied, never moved, so the old app's data stays intact.
/// Each step only runs when the new location is still empty, so it is safe to
/// call on every launch.
enum LegacyMigration {
  static let legacyBundleID = "org.p0deje.Maccy"

  static func run() {
    migratePreferences()
    migrateHistory()
  }

  /// Settings, keyboard shortcuts and pins all live in the preferences domain.
  private static func migratePreferences() {
    guard let bundleID = Bundle.main.bundleIdentifier, bundleID != legacyBundleID else { return }
    let defaults = UserDefaults.standard
    guard defaults.persistentDomain(forName: bundleID)?.isEmpty ?? true,
          let legacy = defaults.persistentDomain(forName: legacyBundleID),
          !legacy.isEmpty else {
      return
    }
    defaults.setPersistentDomain(legacy, forName: bundleID)
  }

  /// The SwiftData store, with its write-ahead log so no recent copies are lost.
  private static func migrateHistory() {
    let files = FileManager.default
    let support = URL.applicationSupportDirectory
    let legacy = support.appending(path: "Maccy")
    let current = support.appending(path: "Fioka")
    let store = "Storage.sqlite"

    guard !files.fileExists(atPath: current.appending(path: store).path),
          files.fileExists(atPath: legacy.appending(path: store).path) else {
      return
    }

    do {
      try files.createDirectory(at: current, withIntermediateDirectories: true)
      for name in [store, "\(store)-wal", "\(store)-shm"] {
        let source = legacy.appending(path: name)
        guard files.fileExists(atPath: source.path) else { continue }
        try files.copyItem(at: source, to: current.appending(path: name))
      }
    } catch {
      NSLog("Fioka: could not copy history from Maccy: \(error)")
    }
  }
}
