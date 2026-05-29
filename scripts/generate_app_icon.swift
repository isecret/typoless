#!/usr/bin/env swift
// generate_app_icon.swift
//
// 基于项目根目录 typoless.svg 生成 macOS App Icon 全套 PNG 资源。
// 风格：白底卡片 + 圆角底板 + 居中 SVG 图形 + 内边距
//
// 用法：swift scripts/generate_app_icon.swift <svg_path> <output_dir>
// 示例：swift scripts/generate_app_icon.swift typoless.svg app/Typoless/Resources/Assets.xcassets/AppIcon.appiconset

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

    // 2. 将底板缩进到透明画布内，避免在桌面/启动台里显得比周边图标更大
    let plateInset = s * 0.075
    let iconRect = canvasRect.insetBy(dx: plateInset, dy: plateInset)
    let cornerRadius = iconRect.width * 0.2237 // macOS 标准圆角比例
    let iconPath = macOSIconPath(in: iconRect, cornerRadius: cornerRadius)

    let shadow = NSShadow()
    shadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.14)
    shadow.shadowBlurRadius = s * 0.022
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.008)
    shadow.set()

    // 轻微偏冷灰白，避免暖黄感，同时保留与 Finder 背景的分离度
    NSColor(calibratedRed: 0.972, green: 0.976, blue: 0.982, alpha: 1.0).setFill()
    iconPath.fill()
    NSShadow().set()

    // 3. 给主体更保守的安全区，兼容 macOS 15 上更敏感的视觉缩放
    let contentPadding = iconRect.width * 0.18
    let iconAreaSize = iconRect.width - contentPadding * 2

    // SVG 原始尺寸为 756x756，等比例缩放
    let svgOrigSize = svgImage.size
    let scaleX = iconAreaSize / svgOrigSize.width
    let scaleY = iconAreaSize / svgOrigSize.height
    let scale = min(scaleX, scaleY)
    let drawW = svgOrigSize.width * scale
    let drawH = svgOrigSize.height * scale
    let drawX = iconRect.minX + (iconRect.width - drawW) / 2
    let drawY = iconRect.minY + (iconRect.height - drawH) / 2
    let drawRect = NSRect(x: drawX, y: drawY, width: drawW, height: drawH)

    NSGraphicsContext.saveGraphicsState()
    iconPath.addClip()

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
