import AppKit
import SwiftUI

/// 悬浮 HUD 窗口 — 透明面板，承载胶囊条 SwiftUI 内容
final class HUDWindow: NSPanel {
    /// 窗口尺寸需大于任何状态的胶囊条内容，由 SwiftUI 内容自适应
    private static let windowSize = HUDLayout.windowSize

    init(contentView: NSView) {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.windowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )

        self.contentView = contentView
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        // 默认不拦截鼠标事件，录音态由 controller 动态切换
        ignoresMouseEvents = true
    }

    /// 定位到当前活跃屏幕（光标所在屏幕）的底部中间
    func positionOnActiveScreen() {
        let screen = Self.screenContainingMouse() ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }

        setFrameOrigin(
            Self.frameOrigin(
                windowSize: Self.windowSize,
                screenFrame: screen.frame,
                visibleFrame: screen.visibleFrame
            )
        )
    }

    static func frameOrigin(
        windowSize: NSSize,
        screenFrame: NSRect,
        visibleFrame: NSRect
    ) -> NSPoint {
        let x = visibleFrame.midX - windowSize.width / 2
        let y = screenFrame.minY + HUDLayout.baseBottomMargin + bottomReservedHeight(
            screenFrame: screenFrame,
            visibleFrame: visibleFrame
        )

        return NSPoint(x: x, y: y)
    }

    static func bottomReservedHeight(screenFrame: NSRect, visibleFrame: NSRect) -> CGFloat {
        max(0, visibleFrame.minY - screenFrame.minY)
    }

    /// 查找光标所在屏幕
    private static func screenContainingMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { screen in
            screen.frame.contains(mouseLocation)
        }
    }
}
