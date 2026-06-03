import ApplicationServices
import Foundation

struct WindowContextCaptureResult: Sendable, Equatable {
    let snapshot: WindowContextSnapshot?
    let event: WindowContextCaptureEvent
    let rawCandidate: WindowContextCandidate?
}

enum WindowContextCaptureEvent: String, Sendable, Equatable {
    case captured = "window_context_captured"
    case redacted = "window_context_redacted"
    case unavailable = "window_context_unavailable"
    case captureFailed = "window_context_capture_failed"
    case timeout = "window_context_capture_timeout"
}

struct WindowContextBuildResult: Sendable, Equatable {
    let snapshot: WindowContextSnapshot?
    let redacted: Bool
}

struct WindowContextCandidate: Sendable, Equatable {
    var appName: String?
    var bundleID: String?
    var windowTitle: String?
    var elementRole: String?
    var elementSubrole: String?
    var placeholder: String?
    var selectedText: String?
    var surroundingTextBefore: String?
    var surroundingTextAfter: String?
    var nearbyLabels: [String] = []
}

/// 捕获当前聚焦输入环境的弱上下文，供 LLM 做有限消歧
struct WindowContextService: Sendable {
    typealias CandidateProvider = @MainActor @Sendable (pid_t?, String?) throws -> WindowContextCandidate?

    static let captureTimeout: Duration = .milliseconds(250)

    private let candidateProvider: CandidateProvider

    init(candidateProvider: @escaping CandidateProvider = Self.captureCandidate) {
        self.candidateProvider = candidateProvider
    }

    func captureContext(
        targetPID: pid_t?,
        targetBundleID: String?
    ) async -> WindowContextSnapshot? {
        let result = await captureContextResult(
            targetPID: targetPID,
            targetBundleID: targetBundleID
        )
        return result.snapshot
    }

    func captureContextResult(
        targetPID: pid_t?,
        targetBundleID: String?
    ) async -> WindowContextCaptureResult {
        enum AttemptResult: Sendable {
            case candidate(WindowContextCandidate?)
            case failed
            case timeout
        }

        let attempt = await withTaskGroup(of: AttemptResult.self) { group in
            group.addTask {
                do {
                    let candidate = try await MainActor.run {
                        try candidateProvider(targetPID, targetBundleID)
                    }
                    return .candidate(candidate)
                } catch {
                    return .failed
                }
            }

            group.addTask {
                try? await Task.sleep(for: Self.captureTimeout)
                return .timeout
            }

            let first = await group.next() ?? .timeout
            group.cancelAll()
            return first
        }

        switch attempt {
        case .candidate(let candidate):
            guard let candidate else {
                return WindowContextCaptureResult(snapshot: nil, event: .unavailable, rawCandidate: nil)
            }
            let build = Self.buildSnapshot(from: candidate)
            guard let snapshot = build.snapshot else {
                return WindowContextCaptureResult(snapshot: nil, event: .unavailable, rawCandidate: candidate)
            }
            return WindowContextCaptureResult(
                snapshot: snapshot,
                event: build.redacted ? .redacted : .captured,
                rawCandidate: candidate
            )
        case .failed:
            return WindowContextCaptureResult(snapshot: nil, event: .captureFailed, rawCandidate: nil)
        case .timeout:
            return WindowContextCaptureResult(snapshot: nil, event: .timeout, rawCandidate: nil)
        }
    }

    static func buildSnapshot(from candidate: WindowContextCandidate) -> WindowContextBuildResult {
        let appName = normalized(candidate.appName, limit: 120)
        let bundleID = normalized(candidate.bundleID, limit: 180)
        let windowTitle = normalized(candidate.windowTitle, limit: 160)
        let elementRole = normalized(candidate.elementRole, limit: 80)
        let elementSubrole = normalized(candidate.elementSubrole, limit: 80)
        let placeholder = normalized(candidate.placeholder, limit: 120)
        let selectedText = normalized(candidate.selectedText, limit: 200)
        let surroundingTextBefore = normalized(candidate.surroundingTextBefore, limit: 80)
        let surroundingTextAfter = normalized(candidate.surroundingTextAfter, limit: 80)
        let nearbyLabels = normalizedLabels(candidate.nearbyLabels)

        let surfaceKind = classifySurfaceKind(
            appName: appName,
            windowTitle: windowTitle,
            role: elementRole,
            subrole: elementSubrole,
            placeholder: placeholder,
            nearbyLabels: nearbyLabels,
            surroundingTextBefore: surroundingTextBefore,
            surroundingTextAfter: surroundingTextAfter
        )

        let normalizedCandidate = WindowContextCandidate(
            appName: appName,
            bundleID: bundleID,
            windowTitle: windowTitle,
            elementRole: elementRole,
            elementSubrole: elementSubrole,
            placeholder: placeholder,
            selectedText: selectedText,
            surroundingTextBefore: surroundingTextBefore,
            surroundingTextAfter: surroundingTextAfter,
            nearbyLabels: nearbyLabels
        )

        let sensitive = isSensitiveContext(candidate: normalizedCandidate)
        let snapshot = WindowContextSnapshot(
            appName: appName,
            bundleID: bundleID,
            windowTitle: windowTitle,
            surfaceKind: surfaceKind,
            elementRole: elementRole,
            elementSubrole: elementSubrole,
            placeholder: sensitive ? nil : placeholder,
            selectedText: sensitive ? nil : selectedText,
            surroundingTextBefore: sensitive ? nil : surroundingTextBefore,
            surroundingTextAfter: sensitive ? nil : surroundingTextAfter,
            nearbyLabels: sensitive ? [] : nearbyLabels
        )

        let hasPayload = snapshot.appName != nil
            || snapshot.bundleID != nil
            || snapshot.windowTitle != nil
            || snapshot.elementRole != nil
            || snapshot.elementSubrole != nil
            || snapshot.placeholder != nil
            || snapshot.selectedText != nil
            || snapshot.surroundingTextBefore != nil
            || snapshot.surroundingTextAfter != nil
            || !snapshot.nearbyLabels.isEmpty

        guard hasPayload else {
            return WindowContextBuildResult(snapshot: nil, redacted: sensitive)
        }

        return WindowContextBuildResult(snapshot: snapshot, redacted: sensitive)
    }

    private static func captureCandidate(
        targetPID: pid_t?,
        targetBundleID: String?
    ) throws -> WindowContextCandidate? {
        guard AXIsProcessTrusted() else {
            return nil
        }

        let resolver = FocusedElementResolver()
        guard let resolved = resolver.resolveFocusedElement(
            targetPID: targetPID,
            shouldRestoreTargetApplication: true
        ) else {
            return nil
        }

        let element = resolved.element
        let windowTitle = attributeElement(element, attribute: kAXWindowAttribute as CFString)
            .flatMap { attributeString($0, attribute: kAXTitleAttribute as CFString) }

        let role = attributeString(element, attribute: kAXRoleAttribute as CFString)
        let subrole = attributeString(element, attribute: kAXSubroleAttribute as CFString)
        let placeholder = attributeString(element, attribute: kAXPlaceholderValueAttribute as CFString)
        let selectedText = attributeString(element, attribute: kAXSelectedTextAttribute as CFString)
        let surrounding = surroundingText(for: element)
        let labels = nearbyLabels(for: element)

        return WindowContextCandidate(
            appName: resolved.appName,
            bundleID: targetBundleID ?? resolved.bundleID,
            windowTitle: windowTitle,
            elementRole: role,
            elementSubrole: subrole,
            placeholder: placeholder,
            selectedText: selectedText,
            surroundingTextBefore: surrounding.before,
            surroundingTextAfter: surrounding.after,
            nearbyLabels: labels
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

    private static func attributeElement(
        _ element: AXUIElement,
        attribute: CFString
    ) -> AXUIElement? {
        var valueRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &valueRef)
        guard result == .success,
              let valueRef else { return nil }
        return (valueRef as! AXUIElement)
    }

    private static func attributeElements(
        _ element: AXUIElement,
        attribute: CFString
    ) -> [AXUIElement] {
        var valueRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &valueRef)
        guard result == .success,
              let values = valueRef as? [AXUIElement] else {
            return []
        }
        return values
    }

    private static func surroundingText(for element: AXUIElement) -> (before: String?, after: String?) {
        guard let selectedRange = selectedTextRange(for: element),
              selectedRange.location >= 0,
              selectedRange.length >= 0 else {
            return (nil, nil)
        }

        let cursorLocation = selectedRange.location
        let selectionEnd = selectedRange.location + selectedRange.length

        let beforeRange = CFRange(
            location: max(0, cursorLocation - 80),
            length: min(80, cursorLocation)
        )
        let afterRange = CFRange(location: selectionEnd, length: 80)

        let before = string(for: beforeRange, element: element)
            ?? sliceValue(for: element, start: beforeRange.location, length: beforeRange.length)
        let after = string(for: afterRange, element: element)
            ?? sliceValue(for: element, start: afterRange.location, length: afterRange.length)

        return (before, after)
    }

    private static func selectedTextRange(for element: AXUIElement) -> CFRange? {
        var valueRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &valueRef
        )
        guard result == .success,
              let value = valueRef,
              AXValueGetType(value as! AXValue) == .cfRange else {
            return nil
        }

        var range = CFRange()
        let success = AXValueGetValue(value as! AXValue, .cfRange, &range)
        return success ? range : nil
    }

    private static func string(for range: CFRange, element: AXUIElement) -> String? {
        var mutableRange = range
        guard let axRange = AXValueCreate(.cfRange, &mutableRange) else {
            return nil
        }

        var valueRef: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            axRange,
            &valueRef
        )
        guard result == .success else { return nil }
        return valueRef as? String
    }

    private static func sliceValue(
        for element: AXUIElement,
        start: Int,
        length: Int
    ) -> String? {
        guard start >= 0,
              length > 0,
              let value = attributeString(element, attribute: kAXValueAttribute as CFString) else {
            return nil
        }

        let characters = Array(value)
        guard start < characters.count else { return nil }
        let end = min(characters.count, start + length)
        guard start < end else { return nil }
        return String(characters[start..<end])
    }

    private static func nearbyLabels(for element: AXUIElement) -> [String] {
        var labels: [String] = []

        collectLabelLikeStrings(from: element, into: &labels)

        if let parent = attributeElement(element, attribute: kAXParentAttribute as CFString) {
            collectLabelLikeStrings(from: parent, into: &labels)

            for sibling in attributeElements(parent, attribute: kAXChildrenAttribute as CFString) {
                guard !CFEqual(sibling, element) else { continue }
                let role = attributeString(sibling, attribute: kAXRoleAttribute as CFString)?.lowercased()
                guard role == "axstatictext"
                    || role == "axgroup"
                    || role == "axbutton"
                    || role == "axcheckbox"
                    || role == "axradiobutton" else {
                    continue
                }
                collectLabelLikeStrings(from: sibling, into: &labels)
            }
        }

        return normalizedLabels(labels)
    }

    private static func collectLabelLikeStrings(from element: AXUIElement, into labels: inout [String]) {
        let attributes: [CFString] = [
            kAXTitleAttribute as CFString,
            kAXDescriptionAttribute as CFString,
            kAXHelpAttribute as CFString,
            kAXPlaceholderValueAttribute as CFString
        ]

        for attribute in attributes {
            if let value = attributeString(element, attribute: attribute) {
                labels.append(value)
            }
        }
    }

    private static func normalized(_ value: String?, limit: Int) -> String? {
        guard let value else { return nil }
        let trimmed = value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let characters = Array(trimmed)
        guard characters.count > limit else { return trimmed }
        return String(characters.prefix(limit))
    }

    private static func normalizedLabels(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var labels: [String] = []

        for value in values {
            guard let normalized = normalized(value, limit: 120) else { continue }
            if seen.insert(normalized).inserted {
                labels.append(normalized)
            }
            if labels.count == 5 {
                break
            }
        }

        return labels
    }

    private static func classifySurfaceKind(
        appName: String?,
        windowTitle: String?,
        role: String?,
        subrole: String?,
        placeholder: String?,
        nearbyLabels: [String],
        surroundingTextBefore: String?,
        surroundingTextAfter: String?
    ) -> InputSurfaceKind {
        let loweredMetadata = (
            [appName, windowTitle, role, subrole, placeholder] + nearbyLabels.map(Optional.some)
        )
        .compactMap { $0?.lowercased() }
        .joined(separator: "\n")

        if loweredMetadata.contains("axsearchfield")
            || containsAny(
                loweredMetadata,
                keywords: ["search", "find", "搜索", "查找", "搜一搜"]
            ) {
            return .searchField
        }

        if containsAny(
            loweredMetadata,
            keywords: [
                "message", "reply", "comment", "chat", "composer",
                "消息", "回复", "评论", "发送", "说点什么"
            ]
        ) {
            return .chatComposer
        }

        let hasMultilineSignal = [surroundingTextBefore, surroundingTextAfter]
            .compactMap { $0 }
            .contains { $0.contains("\n") }
            || containsAny(
                loweredMetadata,
                keywords: [
                    "textarea", "editor", "document", "markdown", "notion",
                    "notes", "pages", "word", "文档", "笔记", "编辑器"
                ]
            )

        if hasMultilineSignal {
            return .documentEditor
        }

        if containsAny(
            loweredMetadata,
            keywords: ["axtextfield", "axtextarea", "field", "form", "输入", "表单"]
        ) {
            return .singleLineForm
        }

        return .unknown
    }

    private static func isSensitiveContext(candidate: WindowContextCandidate) -> Bool {
        let loweredBundleID = candidate.bundleID?.lowercased() ?? ""
        let loweredRole = candidate.elementRole?.lowercased() ?? ""
        let loweredSubrole = candidate.elementSubrole?.lowercased() ?? ""
        let metadata = (
            [
                candidate.appName,
                candidate.bundleID,
                candidate.windowTitle,
                candidate.placeholder
            ] + candidate.nearbyLabels.map(Optional.some)
        )
        .compactMap { $0?.lowercased() }
        .joined(separator: "\n")

        if sensitiveBundleIDs.contains(loweredBundleID) {
            return true
        }

        if loweredRole.contains("secure")
            || loweredRole.contains("password")
            || loweredSubrole.contains("secure")
            || loweredSubrole.contains("password") {
            return true
        }

        return containsAny(
            metadata,
            keywords: [
                "password", "passcode", "security code", "verification code",
                "one-time code", "otp", "2fa", "2-step", "1password",
                "bitwarden", "lastpass", "keepass", "terminal", "shell",
                "密码", "口令", "验证码", "校验码", "安全码", "动态码", "终端"
            ]
        )
    }

    private static func containsAny(_ text: String, keywords: [String]) -> Bool {
        keywords.contains { text.contains($0) }
    }

    private static let sensitiveBundleIDs: Set<String> = [
        "com.apple.securityagent",
        "com.apple.loginwindow",
        "com.apple.screensharing.agent",
        "com.apple.terminal",
        "com.googlecode.iterm2",
        "dev.warp.warp-stable",
        "dev.warp.warppreview",
        "io.alacritty",
        "net.kovidgoyal.kitty",
        "com.github.wez.wezterm",
        "co.zeit.hyper",
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.agilebits.onepassword8",
        "com.bitwarden.desktop",
        "com.lastpass.lpmac",
        "org.keepassxc.keepassxc",
        "com.dashlane.dashlanephonefinal"
    ]
}
