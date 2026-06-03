import ApplicationServices
import AppKit
import Foundation

struct ResolvedFocusedElement {
    let element: AXUIElement
    let appName: String?
    let bundleID: String?
}

/// 统一解析当前聚焦输入元素，供注入与窗口上下文捕获复用
struct FocusedElementResolver {
    private static let focusRetryIntervals: [TimeInterval] = [0.01, 0.02, 0.04]
    private static let frontmostRetryIntervals: [TimeInterval] = [0.01, 0.02, 0.04]

    func resolveFocusedElement(
        targetPID: pid_t?,
        shouldRestoreTargetApplication: Bool = true
    ) -> ResolvedFocusedElement? {
        if let targetPID,
           (!shouldRestoreTargetApplication || restoreTargetApplication(pid: targetPID)),
           let app = NSRunningApplication(processIdentifier: targetPID),
           !app.isTerminated,
           let element = focusedElement(for: targetPID) {
            return ResolvedFocusedElement(
                element: element,
                appName: app.localizedName,
                bundleID: app.bundleIdentifier
            )
        }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedAppRef: CFTypeRef?
        let appResult = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &focusedAppRef
        )
        guard appResult == .success,
              let focusedAppRef else {
            return nil
        }
        let focusedApp = focusedAppRef as! AXUIElement

        var focusedElementRef: CFTypeRef?
        let elementResult = AXUIElementCopyAttributeValue(
            focusedApp,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementRef
        )
        guard elementResult == .success,
              let focusedElementRef else {
            return nil
        }
        let element = focusedElementRef as! AXUIElement

        var pid: pid_t = 0
        let pidResult = AXUIElementGetPid(focusedApp, &pid)
        let runningApp = pidResult == .success
            ? NSRunningApplication(processIdentifier: pid)
            : nil

        return ResolvedFocusedElement(
            element: element,
            appName: runningApp?.localizedName,
            bundleID: runningApp?.bundleIdentifier
        )
    }

    func restoreTargetApplication(pid: pid_t) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else {
            return false
        }

        if app.isHidden {
            app.unhide()
        }

        _ = app.activate(options: [.activateAllWindows])

        for interval in Self.frontmostRetryIntervals {
            if app.isActive || NSWorkspace.shared.frontmostApplication?.processIdentifier == pid {
                return true
            }

            RunLoop.current.run(until: Date().addingTimeInterval(interval))
        }

        return app.isActive || NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
    }

    func focusedElement(for pid: pid_t) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(pid)

        for interval in Self.focusRetryIntervals {
            var focusedElementRef: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(
                appElement,
                kAXFocusedUIElementAttribute as CFString,
                &focusedElementRef
            )

            if result == .success,
               let focusedElementRef {
                let focusedElement = focusedElementRef as! AXUIElement
                return focusedElement
            }

            RunLoop.current.run(until: Date().addingTimeInterval(interval))
        }

        return nil
    }
}
