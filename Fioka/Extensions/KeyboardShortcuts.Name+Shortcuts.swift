import KeyboardShortcuts

extension KeyboardShortcuts.Name {
  static let popup = Self("popup", default: Shortcut(.v, modifiers: [.command, .shift]))
  static let captureText = Self("captureText", default: Shortcut(.two, modifiers: [.command, .shift]))
  static let captureScreenshot = Self("captureScreenshot", default: Shortcut(.four, modifiers: [.control, .option, .command]))
  static let pin = Self("pin", default: Shortcut(.p, modifiers: [.option]))
  static let delete = Self("delete", default: Shortcut(.delete, modifiers: [.option]))
  static let togglePreview = Self("togglePreview", default: Shortcut(.space, modifiers: [.control]))
}
