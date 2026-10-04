#!/usr/bin/env swift
import AppKit
import Foundation

// Original vector artwork. Rendered with system frameworks; no external assets or fonts.
let destination = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Resources/ClipOCR.png")
let size: CGFloat = 1024
let context = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}
func rounded(_ rect: NSRect, radius: CGFloat, fill: NSColor) {
    fill.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}
func stroke(_ points: [NSPoint], width: CGFloat, color: NSColor) {
    let path = NSBezierPath()
    path.lineWidth = width
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.move(to: points[0])
    for point in points.dropFirst() { path.line(to: point) }
    color.setStroke()
    path.stroke()
}

let tile = NSBezierPath(roundedRect: NSRect(x: 72, y: 72, width: 880, height: 880), xRadius: 196, yRadius: 196)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = color(0.08, 0.04, 0.05, 0.30)
shadow.shadowBlurRadius = 38
shadow.shadowOffset = NSSize(width: 0, height: -16)
shadow.set()
color(0.19, 0.06, 0.10).setFill()
tile.fill()
NSGraphicsContext.restoreGraphicsState()
let background = NSGradient(colors: [color(0.09, 0.06, 0.07), color(0.27, 0.07, 0.13), color(0.43, 0.12, 0.20)])!
background.draw(in: tile, angle: 65)

NSGraphicsContext.saveGraphicsState()
tile.addClip()
let glow = NSGradient(starting: color(0.87, 0.56, 0.47, 0.20), ending: color(0.87, 0.56, 0.47, 0))!
glow.draw(fromCenter: NSPoint(x: 310, y: 960), radius: 0,
          toCenter: NSPoint(x: 310, y: 960), radius: 710, options: [.drawsAfterEndingLocation])
NSGraphicsContext.restoreGraphicsState()

// Warm ivory paper with a burgundy clipboard tab.
NSGraphicsContext.saveGraphicsState()
let paperShadow = NSShadow()
paperShadow.shadowColor = color(0.05, 0.02, 0.03, 0.35)
paperShadow.shadowBlurRadius = 25
paperShadow.shadowOffset = NSSize(width: 0, height: -14)
paperShadow.set()
rounded(NSRect(x: 300, y: 278, width: 424, height: 492), radius: 52, fill: color(0.97, 0.92, 0.87))
NSGraphicsContext.restoreGraphicsState()
rounded(NSRect(x: 402, y: 726, width: 220, height: 84), radius: 27, fill: color(0.77, 0.51, 0.47))
rounded(NSRect(x: 438, y: 751, width: 148, height: 31), radius: 15, fill: color(0.30, 0.09, 0.14))

// A letter T and text lines, not a wordmark.
stroke([NSPoint(x: 379, y: 627), NSPoint(x: 529, y: 627)], width: 30, color: color(0.36, 0.10, 0.17))
stroke([NSPoint(x: 454, y: 627), NSPoint(x: 454, y: 509)], width: 30, color: color(0.36, 0.10, 0.17))
rounded(NSRect(x: 574, y: 560, width: 73, height: 24), radius: 12, fill: color(0.64, 0.39, 0.39))
rounded(NSRect(x: 574, y: 511, width: 73, height: 24), radius: 12, fill: color(0.64, 0.39, 0.39))
rounded(NSRect(x: 378, y: 422, width: 268, height: 25), radius: 12.5, fill: color(0.64, 0.39, 0.39))
rounded(NSRect(x: 378, y: 369, width: 193, height: 25), radius: 12.5, fill: color(0.64, 0.39, 0.39))

// Screenshot-selection corners.
let frame = color(0.90, 0.72, 0.63)
let brackets: [[NSPoint]] = [
    [NSPoint(x: 217, y: 671), NSPoint(x: 217, y: 785), NSPoint(x: 331, y: 785)],
    [NSPoint(x: 693, y: 785), NSPoint(x: 807, y: 785), NSPoint(x: 807, y: 671)],
    [NSPoint(x: 217, y: 353), NSPoint(x: 217, y: 239), NSPoint(x: 331, y: 239)],
    [NSPoint(x: 693, y: 239), NSPoint(x: 807, y: 239), NSPoint(x: 807, y: 353)]
]
for bracket in brackets { stroke(bracket, width: 30, color: frame) }

rounded(NSRect(x: 646, y: 229, width: 152, height: 152), radius: 76, fill: color(0.89, 0.66, 0.55))
stroke([NSPoint(x: 687, y: 303), NSPoint(x: 712, y: 280), NSPoint(x: 758, y: 331)],
       width: 18, color: color(0.24, 0.07, 0.11))
NSGraphicsContext.restoreGraphicsState()

let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
try bitmap.representation(using: .png, properties: [:])!.write(to: destination)
print(destination.path)
