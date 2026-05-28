import AppKit
import SwiftUI

enum HUDLayout {
    static let scale: CGFloat = 1.2

    static let hiddenWidth = scaled(96)
    static let activeWidth = scaled(88)
    static let resultWidth = scaled(72)
    static let noticeWidth = scaled(104)
    static let capsuleHeight = scaled(26)

    static let recordingSpacing = scaled(4)
    static let waveformSpacing = scaled(2)
    static let waveformBarWidth = scaled(3)
    static let waveformWidth = scaled(34)

    static let iconSize = scaled(14)
    static let buttonSize = scaled(18)

    static let compactVerticalPadding = scaled(3)
    static let compactHorizontalPadding = scaled(5)
    static let regularHorizontalPadding = scaled(10)

    static let textSize = scaled(10)
    static let modeTracking = scaled(0.35)
    static let resultTracking = scaled(0.6)
    static let thinkingTracking = scaled(1)

    static let backgroundInnerStroke = scaled(0.5)
    static let backgroundOuterStroke = scaled(1)
    static let iconStroke = scaled(1.2)
    static let warningDotRadius = scaled(0.6)

    static let hiddenControlOffset = scaled(1)
    static let visibleControlOffset = scaled(2)
    static let resultOffset = scaled(2)
    static let processingResultOffset = scaled(1.5)
    static let transitionYOffset = scaled(0.5)

    static let resetBarHeight = scaled(1)
    static let waveformMinHeight = scaled(1.2)
    static let waveformMaxHeight = scaled(12.6)

    static let capsuleBackgroundColor = NSColor(white: 0.07, alpha: 1)
    static let capsuleInnerStrokeColor = NSColor(white: 0.16, alpha: 1)
    static let capsuleOuterStrokeColor = NSColor(white: 0.24, alpha: 1)
    static let primaryForegroundColor = NSColor(white: 1, alpha: 1)
    static let secondaryForegroundColor = NSColor(white: 0.9, alpha: 1)
    static let waveformColor = NSColor(white: 1, alpha: 1)
    static let cancelButtonBackgroundColor = NSColor(white: 0.18, alpha: 1)
    static let cancelButtonStrokeColor = NSColor(white: 0.28, alpha: 1)
    static let confirmButtonBackgroundColor = NSColor(white: 1, alpha: 1)
    static let confirmButtonForegroundColor = NSColor(white: 0.07, alpha: 1)
    static let thinkingBaseTextColor = NSColor(white: 0.34, alpha: 1)
    static let thinkingHighlightTextColor = NSColor(white: 1, alpha: 1)

    static let windowSize = NSSize(width: scaled(200), height: scaled(44))

    static func scaled(_ value: CGFloat) -> CGFloat {
        value * scale
    }
}
