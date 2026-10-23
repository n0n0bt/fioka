import SwiftUI

@main
struct FiokaApp: App {
  // Stored properties initialise in declaration order, so this runs before
  // the app delegate is created and before anything reads preferences or
  // opens the history database.
  private let migrated: Void = LegacyMigration.run()

  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  // It's impossible to create sceneless application,
  // so we are hacking this around by creating a menubar
  // scene that is always hidden.
  @State private var hiddenMenu: Bool = false

  var body: some Scene {
    MenuBarExtra("", isInserted: $hiddenMenu) {
      EmptyView()
    }
  }
}
