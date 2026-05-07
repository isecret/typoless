#!/usr/bin/env swift

import AppKit
import Foundation

let args = CommandLine.arguments.dropFirst()
guard args.count == 1 else {
    fputs("Usage: render-dmg-background.swift <output-path>\n", stderr)
    exit(1)
}

let outputPath = String(args[args.startIndex])
let size = NSSize(width: 640, height: 400)
let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size.width),
    pixelsHigh: Int(size.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)

guard let bitmap else {
    fputs("error: failed to allocate bitmap for DMG background image\n", stderr)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("error: failed to create graphics context for DMG background image\n", stderr)
    exit(1)
}
NSGraphicsContext.current = context
defer {
    NSGraphicsContext.restoreGraphicsState()
}

let backgroundRect = NSRect(origin: .zero, size: size)
NSColor(calibratedWhite: 1.0, alpha: 1.0).setFill()
backgroundRect.fill()

let accentColor = NSColor(calibratedWhite: 0.22, alpha: 1.0)

let titleStyle = NSMutableParagraphStyle()
titleStyle.alignment = .center

let titleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 30, weight: .semibold),
    .foregroundColor: accentColor,
    .paragraphStyle: titleStyle
]

let subtitleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 16, weight: .regular),
    .foregroundColor: accentColor,
    .paragraphStyle: titleStyle
]

("Install Typoless").draw(
    in: NSRect(x: 70, y: 298, width: 500, height: 40),
    withAttributes: titleAttributes
)

("Drag the app into Applications").draw(
    in: NSRect(x: 120, y: 262, width: 400, height: 24),
    withAttributes: subtitleAttributes
)

let arrowLineWidth: CGFloat = 5
let arrowTip = NSPoint(x: 390, y: 172)

let arrowPath = NSBezierPath()
arrowPath.lineWidth = arrowLineWidth
arrowPath.lineCapStyle = .round
arrowPath.lineJoinStyle = .round
arrowPath.move(to: NSPoint(x: 246, y: 182))
arrowPath.curve(to: arrowTip,
                controlPoint1: NSPoint(x: 286, y: 206),
                controlPoint2: NSPoint(x: 346, y: 148))

accentColor.setStroke()
arrowPath.stroke()

let arrowDirection = NSPoint(x: 46, y: 18)
let arrowWingLength: CGFloat = 15
let arrowSpreadAngle = CGFloat.pi / 7
let directionMagnitude = sqrt((arrowDirection.x * arrowDirection.x) + (arrowDirection.y * arrowDirection.y))
let unitDirection = NSPoint(x: arrowDirection.x / directionMagnitude, y: arrowDirection.y / directionMagnitude)
let arrowAngle = atan2(unitDirection.y, unitDirection.x)
let upperWingAngle = arrowAngle + .pi - arrowSpreadAngle
let lowerWingAngle = arrowAngle + .pi + arrowSpreadAngle
let arrowHeadUpper = NSPoint(
    x: arrowTip.x + (cos(upperWingAngle) * arrowWingLength),
    y: arrowTip.y + (sin(upperWingAngle) * arrowWingLength)
)
let arrowHeadLower = NSPoint(
    x: arrowTip.x + (cos(lowerWingAngle) * arrowWingLength),
    y: arrowTip.y + (sin(lowerWingAngle) * arrowWingLength)
)

let arrowHead = NSBezierPath()
arrowHead.lineWidth = arrowLineWidth
arrowHead.lineCapStyle = .round
arrowHead.lineJoinStyle = .round
arrowHead.move(to: arrowHeadUpper)
arrowHead.line(to: arrowTip)
arrowHead.line(to: arrowHeadLower)
arrowHead.stroke()

guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fputs("error: failed to render DMG background image\n", stderr)
    exit(1)
}

do {
    try pngData.write(to: URL(fileURLWithPath: outputPath))
} catch {
    fputs("error: failed to write PNG: \(error)\n", stderr)
    exit(1)
}
