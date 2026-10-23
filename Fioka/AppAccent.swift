import AppKit
import SwiftUI

/// Derives a header colour from a source application's icon.
///
/// Tinting each card by the app the content came from is what makes a bar of
/// twenty clipboard entries scannable: you recognise the app before
/// you read a word. Averaging the icon flat gives mud, so this weights each
/// pixel by its saturation and then normalises the result into a band where
/// white text stays legible.
enum AppAccent {
  private static var cache: [String: Color] = [:]

  /// Used when an icon is greyscale, missing, or the app is unknown.
  static let neutral = Color(red: 0.36, green: 0.40, blue: 0.48)

  static func color(for appImage: ApplicationImage, fallback: Color) -> Color {
    guard let bundleIdentifier = appImage.bundleIdentifier else {
      return fallback
    }

    if let cached = cache[bundleIdentifier] {
      return cached
    }

    let color = dominant(in: appImage.nsImage) ?? fallback
    cache[bundleIdentifier] = color
    return color
  }

  private static func dominant(in image: NSImage) -> Color? {
    let side = 16
    guard let context = CGContext(
      data: nil,
      width: side,
      height: side,
      bitsPerComponent: 8,
      bytesPerRow: side * 4,
      space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
      return nil
    }

    var rect = CGRect(x: 0, y: 0, width: side, height: side)
    guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
      return nil
    }
    context.draw(cgImage, in: rect)

    guard let data = context.data else { return nil }
    let pixels = data.bindMemory(to: UInt8.self, capacity: side * side * 4)

    var red = 0.0, green = 0.0, blue = 0.0, total = 0.0

    for index in stride(from: 0, to: side * side * 4, by: 4) {
      let alpha = Double(pixels[index + 3]) / 255
      guard alpha > 0.5 else { continue }

      let pixelRed = Double(pixels[index]) / 255
      let pixelGreen = Double(pixels[index + 1]) / 255
      let pixelBlue = Double(pixels[index + 2]) / 255

      let maximum = max(pixelRed, pixelGreen, pixelBlue)
      let minimum = min(pixelRed, pixelGreen, pixelBlue)
      let saturation = maximum > 0 ? (maximum - minimum) / maximum : 0

      // Skip the white card stock and black outlines most icons are built on.
      guard saturation > 0.18, maximum > 0.12, minimum < 0.96 else { continue }

      // Saturated pixels carry the app's identity; pale ones dilute it.
      let weight = saturation * saturation
      red += pixelRed * weight
      green += pixelGreen * weight
      blue += pixelBlue * weight
      total += weight
    }

    guard total > 0 else { return neutral }

    return normalised(
      NSColor(srgbRed: red / total, green: green / total, blue: blue / total, alpha: 1)
    )
  }

  /// Keeps every header in the same tonal band, so a pale icon and a dark one
  /// both end up with a chip that white text reads against.
  private static func normalised(_ color: NSColor) -> Color {
    guard let srgb = color.usingColorSpace(.sRGB) else { return neutral }

    var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
    srgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

    return Color(nsColor: NSColor(
      hue: hue,
      saturation: min(max(saturation, 0.48), 0.88),
      brightness: min(max(brightness, 0.58), 0.82),
      alpha: 1
    ))
  }
}

extension Color {
  /// Lighter or darker along the same hue, for the header gradient.
  func shifted(by amount: CGFloat) -> Color {
    guard let srgb = NSColor(self).usingColorSpace(.sRGB) else { return self }

    func move(_ channel: CGFloat) -> CGFloat {
      let target: CGFloat = amount >= 0 ? 1 : 0
      return channel + (target - channel) * abs(amount)
    }

    return Color(nsColor: NSColor(
      srgbRed: move(srgb.redComponent),
      green: move(srgb.greenComponent),
      blue: move(srgb.blueComponent),
      alpha: 1
    ))
  }
}
