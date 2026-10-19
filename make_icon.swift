import AppKit

let size = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let rect = NSRect(x: 0, y: 0, width: size, height: size)
let path = NSBezierPath(roundedRect: rect.insetBy(dx: 48, dy: 48), xRadius: 210, yRadius: 210)
let gradient = NSGradient(colors: [
  NSColor(calibratedRed: 0.14, green: 0.48, blue: 0.98, alpha: 1),
  NSColor(calibratedRed: 0.30, green: 0.24, blue: 0.86, alpha: 1),
])!
gradient.draw(in: path, angle: -45)

let symbolConfig = NSImage.SymbolConfiguration(pointSize: 560, weight: .semibold)
  .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
if let symbol = NSImage(
  systemSymbolName: "arrow.left.arrow.right", accessibilityDescription: nil)?
  .withSymbolConfiguration(symbolConfig)
{
  let symbolSize = symbol.size
  let target = NSRect(
    x: (CGFloat(size) - symbolSize.width) / 2,
    y: (CGFloat(size) - symbolSize.height) / 2,
    width: symbolSize.width,
    height: symbolSize.height)
  NSColor.white.set()
  symbol.isTemplate = true
  symbol.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1.0)
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
  let rep = NSBitmapImageRep(data: tiff),
  let png = rep.representation(using: .png, properties: [:])
else {
  fatalError("could not render icon")
}
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
try png.write(to: URL(fileURLWithPath: output))
print(output)
