import AppKit
import SwiftUI

func rgb(_ hex: UInt32) -> Color {
  Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
}
let ink = rgb(0x17151F)
let squircle = Path(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerRadius: 185, style: .continuous)

func bar(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> Path {
  Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: 50, style: .continuous)
}
// Slightly larger than before: an outline needs room to breathe.
// Bars far enough apart that a heavy outline leaves a clear gap between them.
let fShape = Path(bar(300, 222, 170, 580).cgPath.union(bar(300, 222, 460, 150).cgPath).union(bar(300, 470, 360, 140).cgPath))
let handles = [
  Path(roundedRect: CGRect(x: 590, y: 280, width: 92, height: 34), cornerRadius: 17),
  Path(roundedRect: CGRect(x: 512, y: 523, width: 84, height: 34), cornerRadius: 17)
]

struct Variant {
  var name: String
  var stroke: CGFloat
  var ribWidth: CGFloat
  var magnify: CGFloat
  var wobble: CGFloat
}

/// What sits behind the glass: a soft colour bloom and the outlined F.
struct Scene: View {
  let stroke: CGFloat
  var body: some View {
    Canvas { c, _ in
      c.fill(Path(CGRect(x: 0, y: 0, width: 1024, height: 1024)), with: .linearGradient(
        Gradient(colors: [rgb(0xFFFFFF), rgb(0xEEEEF3)]), startPoint: CGPoint(x: 512, y: 100), endPoint: CGPoint(x: 512, y: 924)))
      var bloom = c
      bloom.addFilter(.blur(radius: 90))
      bloom.fill(Path(ellipseIn: CGRect(x: 200, y: 160, width: 440, height: 400)), with: .color(rgb(0xFF7FB0).opacity(0.75)))
      bloom.fill(Path(ellipseIn: CGRect(x: 440, y: 300, width: 440, height: 440)), with: .color(rgb(0x7C86FF).opacity(0.75)))
      bloom.fill(Path(ellipseIn: CGRect(x: 230, y: 540, width: 400, height: 360)), with: .color(rgb(0x5BDDEA).opacity(0.7)))

      // Pale tinted inside, heavy dark outline, as in Arc's mark.
      c.fill(fShape, with: .linearGradient(Gradient(colors: [rgb(0xFFD3E6), rgb(0xD9D2FF), rgb(0xC9F2F6)]),
        startPoint: CGPoint(x: 300, y: 225), endPoint: CGPoint(x: 760, y: 800)))
      let style = StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round)
      c.stroke(fShape, with: .color(ink), style: style)
    }
    .frame(width: 1024, height: 1024)
  }
}

/// Fluted glass: each vertical rib is a small lens that magnifies the strip
/// behind it about its own centre and shifts it a little, so straight edges
/// break into steps and lines change thickness from rib to rib.
func fluted(_ scene: CGImage, _ v: Variant) -> CGImage {
  let ctx = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  // CG is y-up; build the squircle in that space.
  let shape = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 185, cornerHeight: 185, transform: nil)

  ctx.saveGState()
  ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 36, color: CGColor(gray: 0, alpha: 0.28))
  ctx.addPath(shape); ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fillPath()
  ctx.restoreGState()

  ctx.saveGState()
  ctx.addPath(shape); ctx.clip()
  var x: CGFloat = 100
  var index = 0
  while x < 924 {
    let centre = x + v.ribWidth / 2
    let shift = sin(CGFloat(index) * 0.77) * v.wobble + cos(CGFloat(index) * 0.31) * v.wobble * 0.6
    ctx.saveGState()
    ctx.clip(to: CGRect(x: x, y: 0, width: v.ribWidth, height: 1024))
    ctx.translateBy(x: centre + shift, y: 0)
    ctx.scaleBy(x: v.magnify, y: 1)
    ctx.translateBy(x: -centre, y: 0)
    ctx.draw(scene, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
    ctx.restoreGState()

    // The rib's own light: bright on the left, a faint shade on the right.
    let colors = [CGColor(gray: 1, alpha: 0.38), CGColor(gray: 1, alpha: 0), CGColor(gray: 0, alpha: 0.07)] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: colors, locations: [0, 0.45, 1])!
    ctx.saveGState()
    ctx.clip(to: CGRect(x: x, y: 0, width: v.ribWidth, height: 1024))
    ctx.drawLinearGradient(gradient, start: CGPoint(x: x, y: 0), end: CGPoint(x: x + v.ribWidth, y: 0), options: [])
    ctx.restoreGState()

    x += v.ribWidth
    index += 1
  }
  // Soft light from the top, as on Apple's icons.
  let sheen = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                         colors: [CGColor(gray: 1, alpha: 0.22), CGColor(gray: 1, alpha: 0)] as CFArray, locations: [0, 1])!
  ctx.drawLinearGradient(sheen, start: CGPoint(x: 0, y: 924), end: CGPoint(x: 0, y: 520), options: [])
  ctx.restoreGState()
  return ctx.makeImage()!
}

/// Full-bleed for Icon Composer: the scene enlarged so the F keeps its size
/// relative to the icon shape (824 → 1024), and the glass across the whole
/// square, since macOS applies the rounded mask itself.
@MainActor func fullBleed(stroke: CGFloat) -> CGImage {
  let scene = ImageRenderer(content: Scene(stroke: stroke)).cgImage!
  let ctx = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  let zoom: CGFloat = 1024 / 824
  ctx.translateBy(x: 512, y: 512); ctx.scaleBy(x: zoom, y: zoom); ctx.translateBy(x: -512, y: -512)
  ctx.draw(scene, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
  let enlarged = ctx.makeImage()!

  let out = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  let rib: CGFloat = 14 * zoom, magnify: CGFloat = 1.4, wobble: CGFloat = 4 * zoom
  var x: CGFloat = 0
  var index = 0
  while x < 1024 {
    let centre = x + rib / 2
    let shift = sin(CGFloat(index) * 0.77) * wobble + cos(CGFloat(index) * 0.31) * wobble * 0.6
    out.saveGState()
    out.clip(to: CGRect(x: x, y: 0, width: rib, height: 1024))
    out.translateBy(x: centre + shift, y: 0); out.scaleBy(x: magnify, y: 1); out.translateBy(x: -centre, y: 0)
    out.draw(enlarged, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
    out.restoreGState()
    let colors = [CGColor(gray: 1, alpha: 0.38), CGColor(gray: 1, alpha: 0), CGColor(gray: 0, alpha: 0.07)] as CFArray
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: colors, locations: [0, 0.45, 1])!
    out.saveGState()
    out.clip(to: CGRect(x: x, y: 0, width: rib, height: 1024))
    out.drawLinearGradient(g, start: CGPoint(x: x, y: 0), end: CGPoint(x: x + rib, y: 0), options: [])
    out.restoreGState()
    x += rib; index += 1
  }
  let sheen = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                         colors: [CGColor(gray: 1, alpha: 0.22), CGColor(gray: 1, alpha: 0)] as CFArray, locations: [0, 1])!
  out.drawLinearGradient(sheen, start: CGPoint(x: 0, y: 1024), end: CGPoint(x: 0, y: 520), options: [])
  return out.makeImage()!
}

MainActor.assumeIsolated {
  let image = fullBleed(stroke: 62)
  try! NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
}
print("done")
