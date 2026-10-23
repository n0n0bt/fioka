import AppKit
import CoreText

let space = CGColorSpace(name: CGColorSpace.sRGB)!
func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
  CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
let ink = color(0x17151F)

func context(_ w: Int, _ h: Int) -> CGContext {
  CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

/// The drawer F and "ioka" as one outline, baseline at y = 0, cap height `cap`.
/// Returns the letters, the handle pills and the total width.
func letters(cap: CGFloat) -> (CGPath, CGPath, CGFloat) {
  // The F from the icon, defined top-down in a 580-tall box, flipped to y-up.
  let s = cap / 580
  func bar(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGPath {
    CGPath(roundedRect: CGRect(x: x * s, y: (580 - y - h) * s, width: w * s, height: h * s),
           cornerWidth: 50 * s, cornerHeight: 50 * s, transform: nil)
  }
  let f = bar(0, 0, 170, 580).union(bar(0, 0, 460, 150)).union(bar(0, 248, 360, 140))
  let handles = CGMutablePath()
  handles.addRoundedRect(in: CGRect(x: 290 * s, y: (580 - 58 - 34) * s, width: 92 * s, height: 34 * s), cornerWidth: 17 * s, cornerHeight: 17 * s)
  handles.addRoundedRect(in: CGRect(x: 212 * s, y: (580 - 301 - 34) * s, width: 84 * s, height: 34 * s), cornerWidth: 17 * s, cornerHeight: 17 * s)

  // "ioka" in SF Rounded, heavy enough to match the F, light enough that an
  // outline leaves the counters of o and a open.
  let size = cap / 0.715
  let base = NSFont.systemFont(ofSize: size, weight: .heavy)
  let font = (base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base) as CTFont
  let chars = Array("ioka".utf16)
  var glyphs = [CGGlyph](repeating: 0, count: chars.count)
  CTFontGetGlyphsForCharacters(font, chars, &glyphs, chars.count)
  var advances = [CGSize](repeating: .zero, count: glyphs.count)
  CTFontGetAdvancesForGlyphs(font, .horizontal, glyphs, &advances, glyphs.count)

  let word = CGMutablePath()
  var x = 460 * s + cap * 0.07
  for (glyph, advance) in zip(glyphs, advances) {
    if let path = CTFontCreatePathForGlyph(font, glyph, nil) {
      word.addPath(path, transform: CGAffineTransform(translationX: x, y: 0))
    }
    x += advance.width - size * 0.01
  }
  return (f.union(word), handles, x)
}

/// Draws the outlined word: pale tint inside, heavy dark border, handles.
func drawWord(in ctx: CGContext, origin: CGPoint, cap: CGFloat, outline: CGColor, tint: [CGColor]) -> CGFloat {
  let (shape, handles, width) = letters(cap: cap)
  ctx.saveGState()
  ctx.translateBy(x: origin.x, y: origin.y)
  ctx.saveGState()
  ctx.addPath(shape); ctx.clip()
  let gradient = CGGradient(colorsSpace: space, colors: tint as CFArray, locations: nil)!
  ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: cap), end: CGPoint(x: width, y: 0), options: [])
  ctx.restoreGState()
  ctx.addPath(shape)
  ctx.setStrokeColor(outline)
  ctx.setLineWidth(cap * 0.085)
  ctx.setLineJoin(.round)
  ctx.strokePath()
  ctx.restoreGState()
  return width
}

func bloom(in ctx: CGContext, rect: CGRect) {
  // Three soft blobs; CG has no blur, so radial gradients stand in for one.
  let blobs: [(CGFloat, CGFloat, UInt32)] = [(0.22, 0.65, 0xFF7FB0), (0.55, 0.40, 0x7C86FF), (0.82, 0.62, 0x5BDDEA)]
  for (fx, fy, hex) in blobs {
    let centre = CGPoint(x: rect.minX + rect.width * fx, y: rect.minY + rect.height * fy)
    let g = CGGradient(colorsSpace: space, colors: [color(hex, 0.55), color(hex, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(g, startCenter: centre, startRadius: 0, endCenter: centre, endRadius: rect.height * 0.75, options: [])
  }
}

/// Fluted glass over an image, the same lens maths as the icon's "Subtle".
func fluted(_ scene: CGImage, in ctx: CGContext, rect: CGRect, rib: CGFloat = 14, magnify: CGFloat = 1.4, wobble: CGFloat = 4) {
  var x = rect.minX
  var i = 0
  while x < rect.maxX {
    let centre = x + rib / 2
    let shift = sin(CGFloat(i) * 0.77) * wobble + cos(CGFloat(i) * 0.31) * wobble * 0.6
    ctx.saveGState()
    ctx.clip(to: CGRect(x: x, y: rect.minY, width: rib, height: rect.height))
    ctx.translateBy(x: centre + shift, y: 0); ctx.scaleBy(x: magnify, y: 1); ctx.translateBy(x: -centre, y: 0)
    ctx.draw(scene, in: CGRect(x: 0, y: 0, width: scene.width, height: scene.height))
    ctx.restoreGState()
    let g = CGGradient(colorsSpace: space, colors: [CGColor(gray: 1, alpha: 0.38), CGColor(gray: 1, alpha: 0), CGColor(gray: 0, alpha: 0.07)] as CFArray,
                       locations: [0, 0.45, 1])!
    ctx.saveGState()
    ctx.clip(to: CGRect(x: x, y: rect.minY, width: rib, height: rect.height))
    ctx.drawLinearGradient(g, start: CGPoint(x: x, y: 0), end: CGPoint(x: x + rib, y: 0), options: [])
    ctx.restoreGState()
    x += rib; i += 1
  }
}

func save(_ image: CGImage, _ name: String) {
  let url = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(name)
  try! NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!.write(to: url)
}

let pale = [color(0xFFD3E6), color(0xD9D2FF), color(0xC9F2F6)]
let cap: CGFloat = 300
let wordWidth = letters(cap: cap).2

// 1. Glass banner: the whole word behind fluted glass, for a README header.
do {
  let w = Int(wordWidth + 360), h = 720
  let plate = CGRect(x: 0, y: 0, width: w, height: h)
  let scene = context(w, h)
  scene.setFillColor(color(0xF7F7FA)); scene.fill(plate)
  bloom(in: scene, rect: plate)
  _ = drawWord(in: scene, origin: CGPoint(x: 180, y: (CGFloat(h) - cap) / 2), cap: cap, outline: ink, tint: pale)
  let out = context(w, h)
  let rounded = CGPath(roundedRect: plate, cornerWidth: 120, cornerHeight: 120, transform: nil)
  out.addPath(rounded); out.clip()
  fluted(scene.makeImage()!, in: out, rect: plate)
  save(out.makeImage()!, "long-glass.png")
}

// 1b. The same banner for small sizes (a website header): identical plate,
// corners, glow and letters, but about 40 ribs across instead of a hundred,
// so the glass still shows when it is only a hundred-odd points wide.
do {
  let w = Int(wordWidth + 360), h = 720
  let plate = CGRect(x: 0, y: 0, width: w, height: h)
  let scene = context(w, h)
  scene.setFillColor(color(0xF7F7FA)); scene.fill(plate)
  bloom(in: scene, rect: plate)
  _ = drawWord(in: scene, origin: CGPoint(x: 180, y: (CGFloat(h) - cap) / 2), cap: cap, outline: ink, tint: pale)
  let out = context(w, h)
  let rounded = CGPath(roundedRect: plate, cornerWidth: 120, cornerHeight: 120, transform: nil)
  out.addPath(rounded); out.clip()
  let rib = CGFloat(w) / 40
  fluted(scene.makeImage()!, in: out, rect: plate, rib: rib, magnify: 1.4, wobble: rib * 0.28)
  save(out.makeImage()!, "long-glass-small.png")
}

// 2. Clean outline on white and 3. on dark: no glass, for small or busy places.
for (name, bg, outline, tint) in [("long-light.png", color(0xFFFFFF), ink, pale),
                                   ("long-dark.png", color(0x111216), color(0xF4F2FA), [color(0x3A2340), color(0x2B2A55), color(0x1D3D46)])] {
  let w = Int(wordWidth + 240), h = 560
  let ctx = context(w, h)
  ctx.setFillColor(bg); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
  _ = drawWord(in: ctx, origin: CGPoint(x: 120, y: (CGFloat(h) - cap) / 2), cap: cap, outline: outline, tint: tint)
  save(ctx.makeImage()!, name)
}

// 5. Transparent, tightly cropped: the wordmark for web headers and footers.
for (name, outline, tint) in [("long-clear.png", ink, pale),
                              ("long-clear-dark.png", color(0xF4F2FA), [color(0x3A2340), color(0x2B2A55), color(0x1D3D46)])] {
  let stroke = cap * 0.085
  let w = Int(wordWidth + stroke * 2 + 8), h = Int(cap + stroke * 2 + 8)
  let ctx = context(w, h)
  _ = drawWord(in: ctx, origin: CGPoint(x: stroke + 4, y: stroke + 4), cap: cap, outline: outline, tint: tint)
  save(ctx.makeImage()!, name)
}

// 6. The glass wordmark without its plate: the letters seen through fluted
// glass, on transparency, for web headers. Ribs are wider than the banner's
// so the stepped edges survive being shown small; their light only falls on
// the letters, not on the page around them.
for (name, ribs) in [("glass-mark.png", CGFloat(34)), ("glass-mark-fine.png", CGFloat(22))] {
  let stroke = cap * 0.085
  let pad: CGFloat = 40
  let w = Int(wordWidth + stroke * 2 + pad * 2), h = Int(cap + stroke * 2 + pad * 2)
  let rect = CGRect(x: 0, y: 0, width: w, height: h)
  let scene = context(w, h)
  _ = drawWord(in: scene, origin: CGPoint(x: stroke + pad, y: stroke + pad), cap: cap, outline: ink, tint: pale)
  let out = context(w, h)
  var x: CGFloat = 0
  var i = 0
  let image = scene.makeImage()!
  while x < CGFloat(w) {
    let centre = x + ribs / 2
    let shift = sin(CGFloat(i) * 0.77) * 6 + cos(CGFloat(i) * 0.31) * 3.6
    out.saveGState()
    out.clip(to: CGRect(x: x, y: 0, width: ribs, height: CGFloat(h)))
    out.translateBy(x: centre + shift, y: 0); out.scaleBy(x: 1.4, y: 1); out.translateBy(x: -centre, y: 0)
    out.draw(image, in: rect)
    out.restoreGState()
    x += ribs; i += 1
  }
  // Rib light, only where there is letter.
  out.setBlendMode(.sourceAtop)
  x = 0
  while x < CGFloat(w) {
    let g = CGGradient(colorsSpace: space, colors: [CGColor(gray: 1, alpha: 0.42), CGColor(gray: 1, alpha: 0), CGColor(gray: 0, alpha: 0.10)] as CFArray, locations: [0, 0.45, 1])!
    out.saveGState()
    out.clip(to: CGRect(x: x, y: 0, width: ribs, height: CGFloat(h)))
    out.drawLinearGradient(g, start: CGPoint(x: x, y: 0), end: CGPoint(x: x + ribs, y: 0), options: [])
    out.restoreGState()
    x += ribs
  }
  save(out.makeImage()!, name)
}

// 4. Icon + word, side by side.
do {
  let icon = NSImage(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("arc-1.png"))!
    .cgImage(forProposedRect: nil, context: nil, hints: nil)!
  let iconSize = cap * 1.75
  let w = Int(iconSize + 40 + wordWidth + 220), h = 640
  let ctx = context(w, h)
  ctx.setFillColor(color(0xFFFFFF)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
  ctx.interpolationQuality = .high
  ctx.draw(icon, in: CGRect(x: 80, y: (CGFloat(h) - iconSize) / 2, width: iconSize, height: iconSize))
  _ = drawWord(in: ctx, origin: CGPoint(x: 80 + iconSize + 40, y: (CGFloat(h) - cap) / 2), cap: cap, outline: ink, tint: pale)
  save(ctx.makeImage()!, "long-icon.png")
}
print("done")
