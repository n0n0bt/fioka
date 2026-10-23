import Cocoa

class About {
  private static let repository = "https://github.com/n0n0bt/fioka"

  private var links: NSMutableAttributedString {
    let string = NSMutableAttributedString(string: "Website│GitHub│Report an issue",
                                           attributes: [NSAttributedString.Key.foregroundColor: NSColor.labelColor])
    string.addAttribute(.link, value: "https://n0n0bt.github.io/fioka/", range: NSRange(location: 0, length: 7))
    string.addAttribute(.link, value: Self.repository, range: NSRange(location: 8, length: 6))
    string.addAttribute(.link, value: "\(Self.repository)/issues", range: NSRange(location: 15, length: 15))
    return string
  }

  /// Fioka is a fork of Maccy; the credit stays with the original.
  private var upstreamCredit: NSMutableAttributedString {
    let string = NSMutableAttributedString(string: "Based on Maccy by Alex Rodionov",
                                           attributes: [NSAttributedString.Key.foregroundColor: NSColor.labelColor])
    string.addAttribute(.link, value: "https://github.com/p0deje/Maccy", range: NSRange(location: 9, length: 5))
    return string
  }

  private var credits: NSMutableAttributedString {
    let credits = NSMutableAttributedString(string: "",
                                            attributes: [NSAttributedString.Key.foregroundColor: NSColor.labelColor])
    credits.append(links)
    credits.append(NSAttributedString(string: "\n\n"))
    credits.append(upstreamCredit)
    credits.setAlignment(.center, range: NSRange(location: 0, length: credits.length))
    return credits
  }

  @objc
  func openAbout(_ sender: NSMenuItem?) {
    NSApp.activate(ignoringOtherApps: true)
    NSApp.orderFrontStandardAboutPanel(options: [NSApplication.AboutPanelOptionKey.credits: credits])
  }
}
