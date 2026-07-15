#!/usr/bin/env swift

import AppKit
import Foundation

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let output = root.appendingPathComponent("CloverPDF/Resources/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }
    let scale = size / 1024
    let canvas = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor(calibratedRed: 0.08, green: 0.34, blue: 0.22, alpha: 1).setFill()
    NSBezierPath(roundedRect: canvas.insetBy(dx: 42 * scale, dy: 42 * scale), xRadius: 210 * scale, yRadius: 210 * scale).fill()

    let paper = NSRect(x: 238 * scale, y: 148 * scale, width: 548 * scale, height: 728 * scale)
    NSColor(calibratedWhite: 0.98, alpha: 1).setFill()
    NSBezierPath(roundedRect: paper, xRadius: 64 * scale, yRadius: 64 * scale).fill()
    NSColor(calibratedWhite: 0.15, alpha: 0.16).setStroke()
    let outline = NSBezierPath(roundedRect: paper, xRadius: 64 * scale, yRadius: 64 * scale)
    outline.lineWidth = 14 * scale
    outline.stroke()

    let leafColor = NSColor(calibratedRed: 0.12, green: 0.56, blue: 0.33, alpha: 1)
    let leafSize = 172 * scale
    let centers = [
        NSPoint(x: 430 * scale, y: 560 * scale),
        NSPoint(x: 594 * scale, y: 560 * scale),
        NSPoint(x: 430 * scale, y: 396 * scale),
        NSPoint(x: 594 * scale, y: 396 * scale),
    ]
    leafColor.setFill()
    for center in centers {
        let rect = NSRect(x: center.x - leafSize / 2, y: center.y - leafSize / 2, width: leafSize, height: leafSize)
        NSBezierPath(ovalIn: rect).fill()
    }
    NSColor(calibratedRed: 0.96, green: 0.72, blue: 0.18, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: 474 * scale, y: 440 * scale, width: 76 * scale, height: 76 * scale)).fill()
    return image
}

func writePNG(size: Int) throws {
    let image = drawIcon(size: CGFloat(size))
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw CocoaError(.fileWriteUnknown)
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.current?.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try data.write(to: output.appendingPathComponent("icon_\(size).png"))
}

for size in [16, 32, 64, 128, 256, 512, 1024] {
    try writePNG(size: size)
}

let contents = """
{
  "images" : [
    { "filename" : "icon_16.png", "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_32.png", "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32.png", "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_64.png", "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128.png", "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_256.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256.png", "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_512.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512.png", "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_1024.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
"""
try contents.write(to: output.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
