// Draws the Spare app icon (the ring on the night gradient) into a PNG.
// Usage: swift scripts/make-icon.swift <size> <output.png>
import AppKit
import CoreGraphics

let arguments = CommandLine.arguments
guard arguments.count == 3, let size = Int(arguments[1]), size > 0 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <size> <output.png>\n".utf8))
    exit(64)
}

let s = CGFloat(size)
let space = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(70) }

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [r, g, b, a])!
}
// Tokens of the app (Sources/SpareApp/Design/Theme.swift).
let night = color(0.09, 0.08, 0.22)
let tide = color(0.04, 0.17, 0.23)
let mint = color(0.37, 0.95, 0.75)
let used = color(1, 1, 1, 0.22)
let track = color(1, 1, 1, 0.10)

// macOS icon grid: the squircle fills 824 of 1024 points.
let inset = s * 100 / 1024
let tile = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
let radius = tile.width * 0.2237
ctx.saveGState()
ctx.addPath(CGPath(roundedRect: tile, cornerWidth: radius, cornerHeight: radius, transform: nil))
ctx.clip()
// CoreGraphics origin is bottom left: night at the top left, tide at the bottom right.
ctx.drawLinearGradient(CGGradient(colorsSpace: space, colors: [night, tide] as CFArray, locations: [0, 1])!,
                       start: CGPoint(x: tile.minX, y: tile.maxY), end: CGPoint(x: tile.maxX, y: tile.minY), options: [])
ctx.drawRadialGradient(CGGradient(colorsSpace: space, colors: [color(0.16, 0.72, 0.78, 0.30), color(0.16, 0.72, 0.78, 0)] as CFArray,
                                  locations: [0, 1])!,
                       startCenter: CGPoint(x: tile.minX + tile.width * 0.62, y: tile.maxY), startRadius: 0,
                       endCenter: CGPoint(x: tile.minX + tile.width * 0.62, y: tile.maxY), endRadius: tile.width * 0.9, options: [])
ctx.restoreGState()

// The ring: a faint track, the used part in white, and the reclaimable slice in mint with a glow.
let center = CGPoint(x: s / 2, y: s / 2)
let ringRadius = tile.width * 0.30
let lineWidth = tile.width * 0.085

func arc(from startFraction: CGFloat, to endFraction: CGFloat, color: CGColor, cap: CGLineCap = .butt) {
    // Fractions run clockwise from 12 o'clock.
    let start = CGFloat.pi / 2 - startFraction * 2 * .pi
    let end = CGFloat.pi / 2 - endFraction * 2 * .pi
    ctx.beginPath()
    ctx.addArc(center: center, radius: ringRadius, startAngle: start, endAngle: end, clockwise: true)
    ctx.setStrokeColor(color)
    ctx.setLineWidth(lineWidth)
    ctx.setLineCap(cap)
    ctx.strokePath()
}

arc(from: 0, to: 1, color: track)
arc(from: 0, to: 0.64, color: used)
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: tile.width * 0.05, color: color(0.37, 0.95, 0.75, 0.6))
arc(from: 0.64, to: 0.92, color: mint)
ctx.restoreGState()

guard let image = ctx.makeImage() else { exit(70) }
let rep = NSBitmapImageRep(cgImage: image)
guard let data = rep.representation(using: .png, properties: [:]) else { exit(70) }
try data.write(to: URL(fileURLWithPath: arguments[2]))
