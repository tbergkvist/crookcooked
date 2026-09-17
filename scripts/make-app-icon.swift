// Renders the crookcooked app icon — the website's blob mark on a night tile —
// into Config/AppIcon.icns plus PNGs for the website and phone web client.
//
//   swift scripts/make-app-icon.swift
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let night = NSColor(srgbRed: 0.063, green: 0.031, blue: 0.027, alpha: 1)
let ember = NSColor(srgbRed: 0.357, green: 0.043, blue: 0.063, alpha: 1)
let red = NSColor(srgbRed: 0.949, green: 0.243, blue: 0.196, alpha: 1)
let white = NSColor(srgbRed: 0.980, green: 0.960, blue: 0.950, alpha: 1)

/// `macTile` draws Apple's rounded tile with its standard 10% margin; without it
/// the art fills the square, which suits favicons and iOS home-screen icons
/// (iOS applies its own mask).
func render(pixels: Int, macTile: Bool) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(pixels) / 1024

    let tile = macTile ? NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s) : NSRect(x: 0, y: 0, width: 1024 * s, height: 1024 * s)
    let tilePath = macTile ? NSBezierPath(roundedRect: tile, xRadius: 185 * s, yRadius: 185 * s) : NSBezierPath(rect: tile)
    if macTile {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
        shadow.shadowBlurRadius = 24 * s
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        night.setFill()
        tilePath.fill()
        NSGraphicsContext.restoreGraphicsState()
    }
    NSGraphicsContext.saveGraphicsState()
    tilePath.addClip()
    NSGradient(colors: [ember, night])!.draw(in: tilePath, relativeCenterPosition: NSPoint(x: 0, y: -0.15))
    NSGraphicsContext.restoreGraphicsState()

    // The blob: three round corners, one sharp at the bottom left, tilted like the CSS rotate(-7deg) (AppKit is y-up),
    // with the eyes set high — the same proportions as `.brand-mark` on the site.
    let size = tile.width * 0.56
    let mark = NSRect(x: tile.midX - size / 2, y: tile.midY - size / 2 - tile.height * 0.01, width: size, height: size)
    let transform = NSAffineTransform()
    transform.translateX(by: mark.midX, yBy: mark.midY)
    transform.rotate(byDegrees: 7)
    transform.translateX(by: -mark.midX, yBy: -mark.midY)

    let round = size * 0.5
    let sharp = size * (5.0 / 22.0)
    let blob = NSBezierPath()
    blob.move(to: NSPoint(x: mark.minX, y: mark.midY))
    blob.appendArc(from: NSPoint(x: mark.minX, y: mark.maxY), to: NSPoint(x: mark.maxX, y: mark.maxY), radius: round)
    blob.appendArc(from: NSPoint(x: mark.maxX, y: mark.maxY), to: NSPoint(x: mark.maxX, y: mark.minY), radius: round)
    blob.appendArc(from: NSPoint(x: mark.maxX, y: mark.minY), to: NSPoint(x: mark.minX, y: mark.minY), radius: round)
    blob.appendArc(from: NSPoint(x: mark.minX, y: mark.minY), to: NSPoint(x: mark.minX, y: mark.maxY), radius: sharp)
    blob.close()
    blob.transform(using: transform as AffineTransform)

    let glow = NSShadow()
    glow.shadowColor = red.withAlphaComponent(0.55)
    glow.shadowBlurRadius = 90 * s
    NSGraphicsContext.saveGraphicsState()
    glow.set()
    red.setFill()
    blob.fill()
    NSGraphicsContext.restoreGraphicsState()

    let eye = size * (5.0 / 22.0)
    let eyeY = mark.maxY - size * (9.5 / 22.0)
    for x in [mark.minX + size * (7.5 / 22.0), mark.maxX - size * (7.5 / 22.0)] {
        let dot = NSBezierPath(ovalIn: NSRect(x: x - eye / 2, y: eyeY - eye / 2, width: eye, height: eye))
        dot.transform(using: transform as AffineTransform)
        white.setFill()
        dot.fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let iconset = fm.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try render(pixels: points, macTile: true).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try render(pixels: points * 2, macTile: true).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Config/AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
precondition(iconutil.terminationStatus == 0, "iconutil failed")

try render(pixels: 1024, macTile: true).write(to: root.appendingPathComponent("Config/AppIcon-1024.png"))
try render(pixels: 180, macTile: false).write(to: root.appendingPathComponent("website/apple-touch-icon.png"))
try render(pixels: 64, macTile: true).write(to: root.appendingPathComponent("website/favicon.png"))
try fm.createDirectory(at: root.appendingPathComponent("relay/public"), withIntermediateDirectories: true)
try render(pixels: 180, macTile: false).write(to: root.appendingPathComponent("relay/public/apple-touch-icon.png"))
try render(pixels: 512, macTile: false).write(to: root.appendingPathComponent("relay/public/icon-512.png"))
try render(pixels: 64, macTile: true).write(to: root.appendingPathComponent("relay/public/favicon.png"))
print("Wrote Config/AppIcon.icns and web icons")
