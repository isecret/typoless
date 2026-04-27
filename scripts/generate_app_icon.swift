#!/usr/bin/env swift
// generate_app_icon.swift
//
// 基于项目根目录 svg.svg 生成 macOS App Icon 全套 PNG 资源。
// 风格：圆角底板 + 石墨灰渐变 + 居中 SVG 图形 + 内边距
//
// 用法：swift scripts/generate_app_icon.swift <svg_path> <output_dir>
// 示例：swift scripts/generate_app_icon.swift svg.svg app/Typoless/Resources/Assets.xcassets/AppIcon.appiconset

import AppKit
import Foundation

// MARK: - Error

enum GenerateError: Error, CustomStringConvertible {
    case invalidArguments
    case imageLoadFailed(URL)
    case bitmapCreateFailed
    case writeFailed(String)

    var description: String {
        switch self {
        case .invalidArguments:
            return "Usage: generate_app_icon.swift <svg_path> <output_dir>"
        case .imageLoadFailed(let url):
            return "Failed to load image: \(url.path)"
        case .bitmapCreateFailed:
            return "Failed to create bitmap context"
        case .writeFailed(let path):
            return "Failed to write: \(path)"
        }
    }
}

// MARK: - macOS Icon Shape

/// 绘制 macOS 风格连续曲率圆角矩形（squircle 近似）
func macOSIconPath(in rect: CGRect, cornerRadius: CGFloat) -> NSBezierPath {
    // macOS 图标使用约 22.37% 的圆角比例
    NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
}

// MARK: - Rendering

/// 渲染单个 App Icon PNG
func renderAppIcon(svgImage: NSImage, pixels: Int) throws -> Data {
    let size = NSSize(width: pixels, height: pixels)

    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw GenerateError.bitmapCreateFailed
    }

    bitmap.size = size

    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw GenerateError.bitmapCreateFailed
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high

    let canvasRect = NSRect(origin: .zero, size: size)
    let s = CGFloat(pixels)

    // 1. 透明背景
    NSColor.clear.setFill()
    canvasRect.fill()

    // 2. 圆角底板 —— 石墨灰渐变
    let cornerRadius = s * 0.2237 // macOS 标准圆角比例
    let iconPath = macOSIconPath(in: canvasRect, cornerRadius: cornerRadius)

    // 渐变：顶部浅银灰 → 底部石墨灰
    let topColor = NSColor(calibratedRed: 0.62, green: 0.63, blue: 0.64, alpha: 1.0)    // 银灰
    let bottomColor = NSColor(calibratedRed: 0.28, green: 0.29, blue: 0.30, alpha: 1.0) // 石墨灰
    let gradient = NSGradient(starting: topColor, ending: bottomColor)!

    NSGraphicsContext.saveGraphicsState()
    iconPath.addClip()
    gradient.draw(in: canvasRect, angle: 270) // 从上到下

    // 3. 微妙内发光（顶部高光线）
    let highlightRect = NSRect(x: s * 0.05, y: s * 0.88, width: s * 0.9, height: s * 0.06)
    let highlightColor = NSColor(calibratedWhite: 1.0, alpha: 0.08)
    highlightColor.setFill()
    let highlightPath = NSBezierPath(roundedRect: highlightRect, xRadius: s * 0.03, yRadius: s * 0.03)
    highlightPath.fill()

    NSGraphicsContext.restoreGraphicsState()

    // 4. 底板边框（极淡）
    NSGraphicsContext.saveGraphicsState()
    let borderColor = NSColor(calibratedWhite: 0.0, alpha: 0.15)
    borderColor.setStroke()
    iconPath.lineWidth = max(1, s * 0.005)
    iconPath.stroke()
    NSGraphicsContext.restoreGraphicsState()

    // 5. 绘制 SVG 图形，居中 + 内边距 18%
    let padding = s * 0.18
    let iconAreaSize = s - padding * 2

    // SVG 原始尺寸为 756x756，等比例缩放
    let svgOrigSize = svgImage.size
    let scaleX = iconAreaSize / svgOrigSize.width
    let scaleY = iconAreaSize / svgOrigSize.height
    let scale = min(scaleX, scaleY)
    let drawW = svgOrigSize.width * scale
    let drawH = svgOrigSize.height * scale
    let drawX = (s - drawW) / 2
    let drawY = (s - drawH) / 2

    // 略微上移使视觉重心居中（SVG 底部有留白）
    let visualOffset = s * 0.01
    let drawRect = NSRect(x: drawX, y: drawY + visualOffset, width: drawW, height: drawH)

    NSGraphicsContext.saveGraphicsState()
    iconPath.addClip()

    // 图形投影（微弱）
    let shadow = NSShadow()
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.008)
    shadow.shadowBlurRadius = s * 0.02
    shadow.shadowColor = NSColor(calibratedWhite: 0.0, alpha: 0.35)
    shadow.set()

    svgImage.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)

    NSGraphicsContext.restoreGraphicsState()

    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let pngData = bitmap.representation(using: .png, properties: [.interlaced: false]) else {
        throw GenerateError.bitmapCreateFailed
    }

    return pngData
}

// MARK: - Contents.json

struct ContentsJSON: Codable {
    var images: [ImageEntry]
    var info: Info

    struct ImageEntry: Codable {
        var filename: String?
        var idiom: String
        var scale: String
        var size: String
    }

    struct Info: Codable {
        var author: String
        var version: Int
    }
}

// MARK: - Main

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    throw GenerateError.invalidArguments
}

let svgURL = URL(fileURLWithPath: arguments[1])
let outputDir = URL(fileURLWithPath: arguments[2])

guard let svgImage = NSImage(contentsOf: svgURL) else {
    throw GenerateError.imageLoadFailed(svgURL)
}

// macOS AppIcon 标准尺寸列表
let iconSizes: [(logicalSize: Int, scale: Int)] = [
    (16, 1),
    (16, 2),
    (32, 1),
    (32, 2),
    (128, 1),
    (128, 2),
    (256, 1),
    (256, 2),
    (512, 1),
    (512, 2),
]

var contentsImages: [ContentsJSON.ImageEntry] = []

for spec in iconSizes {
    let pixels = spec.logicalSize * spec.scale
    let filename = "app_icon_\(spec.logicalSize)x\(spec.logicalSize)@\(spec.scale)x.png"
    let fileURL = outputDir.appendingPathComponent(filename)

    print("Generating \(filename) (\(pixels)px) …")

    let pngData = try renderAppIcon(svgImage: svgImage, pixels: pixels)
    try pngData.write(to: fileURL, options: .atomic)

    contentsImages.append(ContentsJSON.ImageEntry(
        filename: filename,
        idiom: "mac",
        scale: "\(spec.scale)x",
        size: "\(spec.logicalSize)x\(spec.logicalSize)"
    ))
}

// 写入 Contents.json
let contents = ContentsJSON(
    images: contentsImages,
    info: ContentsJSON.Info(author: "xcode", version: 1)
)

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
let jsonData = try encoder.encode(contents)
let contentsURL = outputDir.appendingPathComponent("Contents.json")
try jsonData.write(to: contentsURL, options: .atomic)

print("✅ App icon generation complete. \(iconSizes.count) PNGs + Contents.json written to \(outputDir.path)")
