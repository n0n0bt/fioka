import AppKit

/// The outlined drawer F as a menu bar template: black on transparent, macOS tints it.
func render(pixels: Int, light: Bool) -> Data {
  let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  let s = CGFloat(pixels) / 16   // design on a 16-point grid
  ctx.scaleBy(x: s, y: s)
  // F in a 16pt box, y-up: stem, top bar, middle bar (a pulled-out drawer).
  func bar(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGPath {
    CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: 1.6, cornerHeight: 1.6, transform: nil)
  }
  let f = bar(3.2, 1.2, 4.0, 13.6).union(bar(3.2, 10.6, 10.0, 4.2)).union(bar(3.2, 5.4, 7.8, 3.8))
  let colour = light ? CGColor(gray: 1, alpha: 1) : CGColor(gray: 0, alpha: 1)
  ctx.addPath(f)
  ctx.setStrokeColor(colour)
  ctx.setLineWidth(1.5)
  ctx.setLineJoin(.round)
  ctx.strokePath()
  return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
}

let dir = URL(fileURLWithPath: CommandLine.arguments[1])
for (pixels, suffix) in [(16, "16w"), (32, "32w")] {
  try! render(pixels: pixels, light: false).write(to: dir.appendingPathComponent("DarkMenuBar-\(suffix).png"))
  try! render(pixels: pixels, light: true).write(to: dir.appendingPathComponent("LightMenuBar-\(suffix).png"))
}
// A big preview to check the drawing.
try! render(pixels: 256, light: false).write(to: URL(fileURLWithPath: "/tmp/fioka-out/menubar-preview.png"))
print("done")
