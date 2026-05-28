import ApplicationServices
import AppKit
import Foundation

struct FocusedElementTextSnapshot: Sendable, Equatable {
    let pid: pid_t
    let bundleID: String?
    let value: String
}

struct FocusedElementTextSnapshotReader: Sendable {
    private let resolver: FocusedElementResolver

    init(resolver: FocusedElementResolver = FocusedElementResolver()) {
        self.resolver = resolver
    }

    @MainActor
    func read(targetPID: pid_t?, targetBundleID: String?) -> FocusedElementTextSnapshot? {
        guard AXIsProcessTrusted() else { return nil }
        guard let targetPID else { return nil }

        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == targetPID else {
            return nil
        }

        guard let resolved = resolver.resolveFocusedElement(
            targetPID: targetPID,
            shouldRestoreTargetApplication: false
        ) else {
            return nil
        }

        guard let value = Self.attributeString(
            resolved.element,
            attribute: kAXValueAttribute as CFString
        ),
        !value.isEmpty else {
            return nil
        }

        let bundleID = resolved.bundleID ?? targetBundleID
        if let targetBundleID, let bundleID, bundleID != targetBundleID {
            return nil
        }

        return FocusedElementTextSnapshot(
            pid: targetPID,
            bundleID: bundleID,
            value: value
        )
    }

    private static func attributeString(
        _ element: AXUIElement,
        attribute: CFString
    ) -> String? {
        var valueRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &valueRef)
        guard result == .success else { return nil }
        return valueRef as? String
    }
}
