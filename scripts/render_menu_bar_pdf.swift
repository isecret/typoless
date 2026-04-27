import AppKit
import Foundation

enum RenderError: Error {
    case invalidArguments
    case imageLoadFailed(URL)
    case bitmapCreateFailed
}

final class PDFIconView: NSView {
    let image: NSImage
    let insetRatio: CGFloat

    init(frame: NSRect, image: NSImage, insetRatio: CGFloat) {
        self.image = image
        self.insetRatio = insetRatio
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()

        let inset = min(bounds.width, bounds.height) * insetRatio
        let targetRect = bounds.insetBy(dx: inset, dy: inset)
        image.draw(in: targetRect, from: .zero, operation: .sourceOver, fraction: 1.0)
    }
}

func makeTemplateMaskImage(from image: NSImage, canvasPixels: Int) throws -> NSImage {
    guard let sourceTIFF = image.tiffRepresentation,
          let sourceBitmap = NSBitmapImageRep(data: sourceTIFF) else {
        throw RenderError.imageLoadFailed(URL(fileURLWithPath: ""))
    }

    guard let outputBitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: canvasPixels,
        pixelsHigh: canvasPixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw RenderError.bitmapCreateFailed
    }

    outputBitmap.size = NSSize(width: canvasPixels, height: canvasPixels)

    guard let context = NSGraphicsContext(bitmapImageRep: outputBitmap) else {
        throw RenderError.bitmapCreateFailed
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: canvasPixels, height: canvasPixels))
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    for y in 0..<canvasPixels {
        for x in 0..<canvasPixels {
            guard let color = outputBitmap.colorAt(x: x, y: y) else { continue }
            let converted = color.usingColorSpace(.deviceRGB) ?? color
            let brightness = (converted.redComponent + converted.greenComponent + converted.blueComponent) / 3
            let alpha: CGFloat = brightness > 0.92 ? 0 : converted.alphaComponent
            outputBitmap.setColor(NSColor(calibratedRed: 0, green: 0, blue: 0, alpha: alpha), atX: x, y: y)
        }
    }

    let maskedImage = NSImage(size: NSSize(width: canvasPixels, height: canvasPixels))
    maskedImage.addRepresentation(outputBitmap)
    return maskedImage
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    throw RenderError.invalidArguments
}

let inputURL = URL(fileURLWithPath: arguments[1])
let outputURL = URL(fileURLWithPath: arguments[2])

guard let image = NSImage(contentsOf: inputURL) else {
    throw RenderError.imageLoadFailed(inputURL)
}

let maskedImage = try makeTemplateMaskImage(from: image, canvasPixels: 512)
let pageSize = NSSize(width: 18, height: 18)
let view = PDFIconView(frame: NSRect(origin: .zero, size: pageSize), image: maskedImage, insetRatio: 0.03)
let pdfData = view.dataWithPDF(inside: view.bounds)
try pdfData.write(to: outputURL, options: .atomic)
