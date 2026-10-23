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

let variants = [
  Variant(name: "1 · Subtle", stroke: 62, ribWidth: 14, magnify: 1.4, wobble: 4),
  Variant(name: "2 · Wavy", stroke: 64, ribWidth: 16, magnify: 1.7, wobble: 9),
  Variant(name: "3 · Wide ribs", stroke: 66, ribWidth: 24, magnify: 1.6, wobble: 8),
  Variant(name: "4 · Bold", stroke: 74, ribWidth: 18, magnify: 1.75, wobble: 10),
]

let out = URL(fileURLWithPath: CommandLine.arguments[1])
let dockURL = URL(fileURLWithPath: CommandLine.arguments[2])
MainActor.assumeIsolated {
  var icons: [CGImage] = []
  for (index, v) in variants.enumerated() {
    let renderer = ImageRenderer(content: Scene(stroke: v.stroke))
    let icon = fluted(renderer.cgImage!, v)
    icons.append(icon)
    try! NSBitmapImageRep(cgImage: icon).representation(using: .png, properties: [:])!
      .write(to: out.appendingPathComponent("arc-\(index + 1).png"))
  }

  let dock = NSImage(contentsOf: dockURL)!
  let rep = dock.representations.first!
  let size = CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
  let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  ctx.interpolationQuality = .high
  ctx.draw(dock.cgImage(forProposedRect: nil, context: nil, hints: nil)!, in: CGRect(origin: .zero, size: size))
  let centres: [CGFloat] = [1916, 2049, 2183, 2318]
  let canvas: CGFloat = 101 / 0.805
  for (slot, icon) in icons.enumerated() {
    ctx.draw(icon, in: CGRect(x: centres[slot] - canvas / 2, y: size.height - 99.6 - canvas / 2, width: canvas, height: canvas))
  }
  try! NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
    .write(to: out.appendingPathComponent("dock7.png"))

  let sheet = HStack(spacing: 36) {
    ForEach(icons.indices, id: \.self) { index in
      VStack(spacing: 10) {
        Image(decorative: icons[index], scale: 1).resizable().interpolation(.high).frame(width: 300, height: 300)
        Text(variants[index].name).font(.system(size: 21, weight: .semibold))
        HStack(alignment: .bottom, spacing: 14) {
          Image(decorative: icons[index], scale: 1).resizable().interpolation(.high).frame(width: 64, height: 64)
          Image(decorative: icons[index], scale: 1).resizable().interpolation(.high).frame(width: 32, height: 32)
        }
      }
    }
  }
  .padding(40)
  .background(Color(white: 0.86))
  try! NSBitmapImageRep(cgImage: ImageRenderer(content: sheet).cgImage!).representation(using: .png, properties: [:])!
    .write(to: out.appendingPathComponent("sheet7.png"))
}
print("done")
