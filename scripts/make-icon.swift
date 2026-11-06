#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let output = root.appendingPathComponent("Resources/AppIcon.iconset", isDirectory: true)
try? FileManager.default.removeItem(at: output)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func render(size: Int) -> NSBitmapImageRep {
    let dimension = CGFloat(size)
    let rep = NSBitmapImageRep(
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
    )!

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let cg = NSGraphicsContext.current!.cgContext
    cg.setShouldAntialias(true)

    let inset = dimension * 0.045
    let rect = CGRect(x: inset, y: inset, width: dimension - inset * 2, height: dimension - inset * 2)
    let radius = dimension * 0.225
    let background = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    let colors = [
        color(0x0B2B2E).cgColor,
        color(0x0A1020).cgColor,
        color(0x17152E).cgColor,
    ] as CFArray
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: colors,
        locations: [0, 0.55, 1]
    )!

    cg.saveGState()
    cg.addPath(background.cgPath)
    cg.clip()
    cg.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: dimension),
        end: CGPoint(x: dimension, y: 0),
        options: []
    )
    cg.restoreGState()

    cg.saveGState()
    cg.addPath(background.cgPath)
    cg.setStrokeColor(color(0x5EEAD4, 0.32).cgColor)
    cg.setLineWidth(max(0.8, dimension * 0.006))
    cg.strokePath()
    cg.restoreGState()

    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: dimension * x, y: dimension * y)
    }

    let center = point(0.50, 0.52)
    let upperLeft = point(0.27, 0.70)
    let upperRight = point(0.73, 0.70)
    let bottom = point(0.50, 0.28)
    let lineWidth = dimension * 0.046

    cg.saveGState()
    cg.setShadow(offset: .zero, blur: dimension * 0.075, color: color(0x5EEAD4, 0.55).cgColor)
    cg.setLineCap(.round)
    cg.setLineJoin(.round)
    cg.setLineWidth(lineWidth)
    cg.setStrokeColor(color(0x5EEAD4, 0.92).cgColor)

    cg.move(to: upperLeft)
    cg.addLine(to: center)
    cg.addLine(to: bottom)
    cg.strokePath()

    cg.setStrokeColor(color(0xA78BFA, 0.92).cgColor)
    cg.move(to: center)
    cg.addLine(to: upperRight)
    cg.strokePath()
    cg.restoreGState()

    func node(_ position: CGPoint, radius: CGFloat, fill: NSColor, glow: NSColor) {
        cg.saveGState()
        cg.setShadow(offset: .zero, blur: dimension * 0.05, color: glow.cgColor)
        cg.setFillColor(fill.cgColor)
        cg.fillEllipse(in: CGRect(
            x: position.x - radius,
            y: position.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
        cg.restoreGState()
    }

    let outer = dimension * 0.046
    node(upperLeft, radius: outer, fill: color(0x5EEAD4), glow: color(0x5EEAD4, 0.8))
    node(upperRight, radius: outer, fill: color(0xA78BFA), glow: color(0xA78BFA, 0.8))
    node(bottom, radius: outer, fill: color(0x5EEAD4), glow: color(0x5EEAD4, 0.8))

    node(center, radius: dimension * 0.078, fill: color(0xF2FFFC), glow: color(0x5EEAD4, 0.95))
    node(center, radius: dimension * 0.034, fill: color(0x0E2A2C), glow: .clear)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func write(_ size: Int, _ names: [String]) {
    let rep = render(size: size)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("Could not encode icon at \(size)")
    }
    for name in names {
        try! data.write(to: output.appendingPathComponent(name))
    }
}

write(16, ["icon_16x16.png"])
write(32, ["icon_16x16@2x.png", "icon_32x32.png"])
write(64, ["icon_32x32@2x.png"])
write(128, ["icon_128x128.png"])
write(256, ["icon_128x128@2x.png", "icon_256x256.png"])
write(512, ["icon_256x256@2x.png", "icon_512x512.png"])
write(1024, ["icon_512x512@2x.png"])

print("Wrote \(output.path)")
