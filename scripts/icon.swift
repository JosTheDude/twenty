// Draws the app icon. Regenerate Resources/AppIcon.icns with: swift scripts/icon.swift
import AppKit

// The mark: an eye whose iris is a timer ring two-thirds of the way round. Unit square, y up.
func mark(in r: NSRect, width w: CGFloat) -> (eye: NSBezierPath, ring: NSBezierPath, pupil: NSBezierPath) {
    func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
    let eye = NSBezierPath()
    eye.move(to: p(0.04, 0.5))
    eye.curve(to: p(0.96, 0.5), controlPoint1: p(0.3, 0.86), controlPoint2: p(0.7, 0.86))
    eye.curve(to: p(0.04, 0.5), controlPoint1: p(0.7, 0.14), controlPoint2: p(0.3, 0.14))
    eye.close()
    eye.lineWidth = w * r.width
    eye.lineJoinStyle = .round
    let ring = NSBezierPath()
    ring.appendArc(withCenter: p(0.5, 0.5), radius: 0.17 * r.width, startAngle: 90, endAngle: -150, clockwise: true)
    ring.lineWidth = w * r.width
    ring.lineCapStyle = .round
    let d = 0.055 * r.width
    let pupil = NSBezierPath(ovalIn: NSRect(x: p(0.5, 0.5).x - d, y: p(0.5, 0.5).y - d, width: 2 * d, height: 2 * d))
    return (eye, ring, pupil)
}

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px) / 1024
    NSGraphicsContext.current!.cgContext.scaleBy(x: s, y: s)

    // macOS icon grid: 824pt body inset 100pt, with a soft drop shadow
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = .black.withAlphaComponent(0.35)
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.shadowBlurRadius = 24
    shadow.set()
    NSColor.black.setFill()
    squircle.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    squircle.addClip()
    NSGradient(starting: NSColor(srgbRed: 0.13, green: 0.19, blue: 0.31, alpha: 1),
               ending: NSColor(srgbRed: 0.04, green: 0.06, blue: 0.11, alpha: 1))!.draw(in: body, angle: -90)
    NSGradient(starting: NSColor(srgbRed: 0.25, green: 0.82, blue: 0.79, alpha: 0.28), ending: .clear)!
        .draw(in: body, relativeCenterPosition: NSPoint(x: 0, y: -0.05))
    // hairline highlight on the top edge
    NSColor.white.withAlphaComponent(0.12).setStroke()
    let edge = NSBezierPath(roundedRect: body.insetBy(dx: 1.5, dy: 1.5), xRadius: 184, yRadius: 184)
    edge.lineWidth = 3
    edge.stroke()
    NSGraphicsContext.restoreGraphicsState()

    let (eye, ring, pupil) = mark(in: NSRect(x: 222, y: 222, width: 580, height: 580), width: 0.06)
    NSGraphicsContext.saveGraphicsState()
    let glow = NSShadow()
    glow.shadowColor = NSColor(srgbRed: 0.45, green: 0.95, blue: 0.9, alpha: 0.45)
    glow.shadowBlurRadius = 28
    glow.set()
    NSColor(srgbRed: 0.93, green: 0.99, blue: 0.98, alpha: 1).set()
    eye.stroke()
    ring.stroke()
    pupil.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.current = nil
    return rep.representation(using: .png, properties: [:])!
}

let dir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let set = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: set)
try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
for pt in [16, 32, 128, 256, 512] {
    try render(pt).write(to: set.appendingPathComponent("icon_\(pt)x\(pt).png"))
    try render(pt * 2).write(to: set.appendingPathComponent("icon_\(pt)x\(pt)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", set.path, "-o", dir.deletingLastPathComponent().appendingPathComponent("Resources/AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
