import SwiftUI

/// HUD 内容视图 — 极简胶囊条
///
/// 录音态：`X + 声波 + ✓`
/// 处理态：Thinking 黑白灰渐变动画
/// 结果态：失败短文案或新词提示
struct HUDContentView: View {
    let controller: HUDFeedbackController
    var onCancel: () -> Void = {}
    var onConfirm: () -> Void = {}

    @State private var phase: VisualPhase = .hidden
    @State private var capsuleWidth: CGFloat = HUDLayout.hiddenWidth
    @State private var capsuleScale: CGFloat = 1
    @State private var capsuleYOffset: CGFloat = 0
    @State private var recordingOpacity: Double = 0
    @State private var processingOpacity: Double = 0
    @State private var resultOpacity: Double = 0
    @State private var recordingControlsOpacity: Double = 0
    @State private var recordingWaveOpacity: Double = 0
    @State private var resultOffsetY: CGFloat = HUDLayout.resultOffset
    @State private var resultState: HUDState?
    @State private var transitionTask: Task<Void, Never>?

    private let capsuleHeight: CGFloat = HUDLayout.capsuleHeight

    var body: some View {
        Group {
            if phase != .hidden {
                ZStack {
                    recordingCapsule
                        .opacity(controller.modeCueLabel == nil ? recordingOpacity : 0)
                    thinkingCapsule
                        .opacity(processingOpacity)
                    if let label = controller.modeCueLabel, controller.hudState == .recording {
                        modeCueCapsule(label: label)
                            .opacity(recordingOpacity)
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    }
                    if let resultState {
                        resultCapsule(for: resultState)
                            .opacity(resultOpacity)
                            .offset(y: resultOffsetY)
                    }
                }
                .frame(width: capsuleWidth, height: capsuleHeight)
                .background(capsuleBackground)
                .clipShape(Capsule())
                .contentShape(Capsule())
                .scaleEffect(capsuleScale)
                .offset(y: capsuleYOffset)
                .animation(.easeOut(duration: 0.12), value: controller.modeCueLabel)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .onAppear { syncImmediately(to: controller.hudState) }
        .onChange(of: controller.hudState) { oldValue, newValue in
            transitionTask?.cancel()
            transitionTask = Task { @MainActor in
                await animateStateHandoff(from: oldValue, to: newValue)
            }
        }
    }

    // MARK: - Recording Capsule

    private var recordingCapsule: some View {
        HStack(spacing: HUDLayout.recordingSpacing) {
            hudButton(icon: .xMark) { onCancel() }
                .opacity(recordingControlsOpacity)
                .offset(x: recordingControlsOpacity == 0 ? HUDLayout.hiddenControlOffset : -HUDLayout.visibleControlOffset)
            waveformView
            hudButton(icon: .checkMark, isConfirm: true) { onConfirm() }
                .opacity(recordingControlsOpacity)
                .offset(x: recordingControlsOpacity == 0 ? -HUDLayout.hiddenControlOffset : HUDLayout.visibleControlOffset)
        }
        .padding(.vertical, HUDLayout.compactVerticalPadding)
        .padding(.horizontal, HUDLayout.compactHorizontalPadding)
    }

    // MARK: - Thinking Capsule

    private var thinkingCapsule: some View {
        ThinkingShimmerView()
            .padding(.vertical, HUDLayout.compactVerticalPadding)
            .padding(.horizontal, HUDLayout.regularHorizontalPadding)
    }

    // MARK: - Mode Cue Capsule

    private func modeCueCapsule(label: String) -> some View {
        Text(label)
            .font(.system(size: HUDLayout.textSize, weight: .semibold))
            .tracking(HUDLayout.modeTracking)
            .textCase(.uppercase)
            .foregroundStyle(Color(nsColor: HUDLayout.secondaryForegroundColor))
            .padding(.vertical, HUDLayout.compactVerticalPadding)
            .padding(.horizontal, HUDLayout.regularHorizontalPadding)
    }

    // MARK: - Result Capsule

    private func resultCapsule(for state: HUDState) -> some View {
        let payload = resultPayload(for: state)
        let isNotice = state.isNotice
        return HStack(spacing: isNotice ? HUDLayout.noticeSpacing : HUDLayout.compactHorizontalPadding) {
            if !payload.icon.isEmpty {
                HUDIcon(type: payload.icon)
                    .frame(width: HUDLayout.iconSize, height: HUDLayout.iconSize)
                    .foregroundStyle(Color(nsColor: HUDLayout.primaryForegroundColor))
                    .offset(y: isNotice ? HUDLayout.noticeIconYOffset : 0)
            }
            Text(payload.text)
                .font(.system(size: HUDLayout.textSize, weight: .semibold))
                .tracking(isNotice ? HUDLayout.noticeTracking : HUDLayout.resultTracking)
                .textCase(isNotice ? nil : .uppercase)
                .foregroundStyle(Color(nsColor: HUDLayout.secondaryForegroundColor))
        }
        .padding(.vertical, HUDLayout.compactVerticalPadding)
        .padding(.leading, isNotice ? HUDLayout.noticeLeadingPadding : HUDLayout.regularHorizontalPadding)
        .padding(.trailing, isNotice ? HUDLayout.noticeTrailingPadding : HUDLayout.regularHorizontalPadding)
    }

    // MARK: - Waveform

    private var waveformView: some View {
        return HStack(spacing: HUDLayout.waveformSpacing) {
            ForEach(0..<controller.barHeights.count, id: \.self) { i in
                RoundedRectangle(cornerRadius: 999)
                    .fill(Color(nsColor: HUDLayout.waveformColor))
                    .frame(width: HUDLayout.waveformBarWidth, height: controller.barHeights[i])
            }
        }
        .frame(width: HUDLayout.waveformWidth, height: capsuleHeight - HUDLayout.scaled(6))
        .clipped()
        .opacity(recordingWaveOpacity)
        .scaleEffect(x: 1, y: 0.88 + 0.12 * recordingWaveOpacity, anchor: .center)
    }

    // MARK: - Button

    private enum ButtonIcon { case xMark, checkMark }

    private func hudButton(icon: ButtonIcon, isConfirm: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                switch icon {
                case .xMark:
                    HUDIcon(type: "x")
                case .checkMark:
                    HUDIcon(type: "check")
                }
            }
            .frame(width: HUDLayout.iconSize, height: HUDLayout.iconSize)
        }
        .buttonStyle(HUDButtonStyle(isConfirm: isConfirm))
        .frame(width: HUDLayout.buttonSize, height: HUDLayout.buttonSize)
    }

    // MARK: - Common Background

    private var capsuleBackground: some View {
        ZStack {
            Capsule()
                .fill(Color(nsColor: HUDLayout.capsuleBackgroundColor))
                .overlay {
                    Capsule()
                        .strokeBorder(Color(nsColor: HUDLayout.capsuleInnerStrokeColor), lineWidth: HUDLayout.backgroundInnerStroke)
                }
            Capsule()
                .strokeBorder(Color(nsColor: HUDLayout.capsuleOuterStrokeColor), lineWidth: HUDLayout.backgroundOuterStroke)
        }
        .environment(\.colorScheme, .dark)
    }

    // MARK: - State Sync

    private func syncImmediately(to state: HUDState) {
        transitionTask?.cancel()
        resultState = state.isResult ? state : nil

        switch state {
        case .hidden:
            phase = .hidden
            capsuleWidth = HUDLayout.hiddenWidth
            capsuleScale = 1
            capsuleYOffset = 0
            recordingOpacity = 0
            processingOpacity = 0
            resultOpacity = 0
            recordingControlsOpacity = 0
            recordingWaveOpacity = 0
            resultOffsetY = HUDLayout.resultOffset

        case .recording:
            phase = .recording
            capsuleWidth = HUDLayout.activeWidth
            capsuleScale = 1
            capsuleYOffset = 0
            recordingOpacity = 1
            processingOpacity = 0
            resultOpacity = 0
            recordingControlsOpacity = 1
            recordingWaveOpacity = 1
            resultOffsetY = HUDLayout.resultOffset

        case .processing:
            phase = .processing
            capsuleWidth = HUDLayout.activeWidth
            capsuleScale = 1
            capsuleYOffset = 0
            recordingOpacity = 0
            processingOpacity = 1
            resultOpacity = 0
            recordingControlsOpacity = 0
            recordingWaveOpacity = 0
            resultOffsetY = HUDLayout.resultOffset

        case .failure, .notice:
            phase = .result
            capsuleWidth = resultCapsuleWidth(for: state)
            capsuleScale = 1
            capsuleYOffset = 0
            recordingOpacity = 0
            processingOpacity = 0
            resultOpacity = 1
            recordingControlsOpacity = 0
            recordingWaveOpacity = 0
            resultOffsetY = 0
        }
    }

    private func animateStateHandoff(from oldValue: HUDState, to newValue: HUDState) async {
        switch (oldValue, newValue) {
        case (_, .hidden):
            withAnimation(.easeOut(duration: 0.18)) {
                recordingOpacity = 0
                processingOpacity = 0
                resultOpacity = 0
                capsuleScale = 0.985
            }
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            syncImmediately(to: .hidden)

        case (.recording, .processing):
            phase = .recording
            resultState = nil
            withAnimation(.easeOut(duration: 0.12)) {
                recordingControlsOpacity = 0
                recordingWaveOpacity = 0.18
                capsuleWidth = HUDLayout.activeWidth
                capsuleScale = 0.985
                capsuleYOffset = HUDLayout.transitionYOffset
            }
            try? await Task.sleep(for: .milliseconds(90))
            guard !Task.isCancelled else { return }
            phase = .processing
            withAnimation(.easeOut(duration: 0.16)) {
                recordingOpacity = 0
                processingOpacity = 1
                capsuleScale = 1
                capsuleYOffset = 0
            }
            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled else { return }
            recordingControlsOpacity = 1
            recordingWaveOpacity = 1

        case (.processing, let next) where next.isResult:
            resultState = next
            phase = .processing
            withAnimation(.easeOut(duration: 0.12)) {
                processingOpacity = 0.14
                capsuleWidth = HUDLayout.resultWidth
                capsuleScale = 0.992
            }
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            phase = .result
            resultOffsetY = HUDLayout.processingResultOffset
            withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                processingOpacity = 0
                resultOpacity = 1
                resultOffsetY = 0
                capsuleScale = 1
            }

        default:
            syncImmediately(to: newValue)
            withAnimation(.easeOut(duration: 0.16)) {
                capsuleScale = 1
                capsuleYOffset = 0
            }
        }
    }

    private func resultPayload(for state: HUDState) -> (icon: String, text: String) {
        switch state {
        case .notice(let text):
            return ("dictionary", text)
        case .failure(let reason):
            return ("warn", reason.shortLabel)
        default:
            return ("check", "")
        }
    }

    private func resultCapsuleWidth(for state: HUDState) -> CGFloat {
        switch state {
        case .notice(let text):
            HUDLayout.noticeWidth(for: text)
        default:
            HUDLayout.resultWidth
        }
    }
}

private enum VisualPhase {
    case hidden
    case recording
    case processing
    case result
}

private extension HUDState {
    var isResult: Bool {
        switch self {
        case .failure, .notice:
            true
        default:
            false
        }
    }

    var isNotice: Bool {
        if case .notice = self {
            true
        } else {
            false
        }
    }
}

// MARK: - HUD Button Style

private struct HUDButtonStyle: ButtonStyle {
    let isConfirm: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: HUDLayout.buttonSize, height: HUDLayout.buttonSize)
            .background(
                Circle().fill(
                    Color(
                        nsColor: isConfirm
                            ? HUDLayout.confirmButtonBackgroundColor
                            : HUDLayout.cancelButtonBackgroundColor
                    )
                )
            )
            .overlay(
                Circle()
                    .strokeBorder(
                        Color(
                            nsColor: isConfirm
                                ? HUDLayout.confirmButtonBackgroundColor
                                : HUDLayout.cancelButtonStrokeColor
                        ),
                        lineWidth: HUDLayout.backgroundOuterStroke
                    )
            )
            .foregroundStyle(
                Color(
                    nsColor: isConfirm
                        ? HUDLayout.confirmButtonForegroundColor
                        : HUDLayout.primaryForegroundColor
                )
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - HUD SVG-style Icons

private struct HUDIcon: View {
    let type: String

    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height)
            switch type {
            case "x":
                var path = Path()
                path.move(to: CGPoint(x: s * 0.175, y: s * 0.175))
                path.addLine(to: CGPoint(x: s * 0.825, y: s * 0.825))
                path.move(to: CGPoint(x: s * 0.825, y: s * 0.175))
                path.addLine(to: CGPoint(x: s * 0.175, y: s * 0.825))
                context.stroke(path, with: .foreground, style: StrokeStyle(lineWidth: HUDLayout.iconStroke, lineCap: .round))
            case "check":
                var path = Path()
                path.move(to: CGPoint(x: s * 0.14, y: s * 0.53))
                path.addLine(to: CGPoint(x: s * 0.38, y: s * 0.77))
                path.addLine(to: CGPoint(x: s * 0.87, y: s * 0.26))
                context.stroke(path, with: .foreground, style: StrokeStyle(lineWidth: HUDLayout.iconStroke, lineCap: .round, lineJoin: .round))
            case "warn":
                // 光学对齐：上方竖线略短，底部点不超过竖线视觉宽度
                var path = Path()
                path.move(to: CGPoint(x: s * 0.5, y: s * 0.25))
                path.addLine(to: CGPoint(x: s * 0.5, y: s * 0.56))
                context.stroke(path, with: .foreground, style: StrokeStyle(lineWidth: HUDLayout.iconStroke, lineCap: .round))
                let dotRadius = HUDLayout.warningDotRadius
                let dotCenter = CGPoint(x: s * 0.5, y: s * 0.765)
                context.fill(Circle().path(in: CGRect(x: dotCenter.x - dotRadius, y: dotCenter.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2)), with: .foreground)
            case "dictionary":
                let drawSize = s * HUDLayout.noticeFilledIconScale
                let inset = (s - drawSize) / 2

                func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                    CGPoint(
                        x: inset + drawSize * (x / 1024),
                        y: inset + drawSize * (y / 1024)
                    )
                }

                var frontCover = Path()
                frontCover.move(to: point(110.933333, 829.44))
                frontCover.addCurve(
                    to: point(85.333333, 803.84),
                    control1: point(97.28, 829.44),
                    control2: point(85.333333, 817.493333)
                )
                frontCover.addLine(to: point(85.333333, 220.16))
                frontCover.addCurve(
                    to: point(245.76, 59.733333),
                    control1: point(85.333333, 131.413333),
                    control2: point(157.013333, 59.733333)
                )
                frontCover.addLine(to: point(738.986667, 59.733333))
                frontCover.addCurve(
                    to: point(764.586667, 85.333333),
                    control1: point(752.64, 59.733333),
                    control2: point(764.586667, 71.68)
                )
                frontCover.addLine(to: point(764.586667, 669.013333))
                frontCover.addCurve(
                    to: point(738.986667, 694.613333),
                    control1: point(764.586667, 682.666667),
                    control2: point(752.64, 694.613333)
                )
                frontCover.addLine(to: point(245.76, 694.613333))
                frontCover.addCurve(
                    to: point(136.533333, 803.84),
                    control1: point(186.026667, 694.613333),
                    control2: point(136.533333, 744.106667)
                )
                frontCover.addCurve(
                    to: point(110.933333, 829.44),
                    control1: point(136.533333, 817.493333),
                    control2: point(126.293333, 829.44)
                )
                frontCover.closeSubpath()

                frontCover.move(to: point(245.76, 110.933333))
                frontCover.addCurve(
                    to: point(136.533333, 220.16),
                    control1: point(186.026667, 110.933333),
                    control2: point(136.533333, 160.426667)
                )
                frontCover.addLine(to: point(136.533333, 686.08))
                frontCover.addCurve(
                    to: point(245.76, 643.413333),
                    control1: point(165.546667, 658.773333),
                    control2: point(203.093333, 643.413333)
                )
                frontCover.addLine(to: point(713.386667, 643.413333))
                frontCover.addLine(to: point(713.386667, 110.933333))
                frontCover.addLine(to: point(245.76, 110.933333))
                frontCover.closeSubpath()
                context.fill(frontCover, with: .foreground, style: FillStyle(eoFill: true))

                var pageBlock = Path()
                pageBlock.move(to: point(875.52, 964.266667))
                pageBlock.addLine(to: point(245.76, 964.266667))
                pageBlock.addCurve(
                    to: point(85.333333, 803.84),
                    control1: point(157.013333, 964.266667),
                    control2: point(85.333333, 892.586667)
                )
                pageBlock.addCurve(
                    to: point(245.76, 643.413333),
                    control1: point(85.333333, 715.093333),
                    control2: point(157.013333, 643.413333)
                )
                pageBlock.addLine(to: point(738.986667, 643.413333))
                pageBlock.addCurve(
                    to: point(764.586667, 669.013333),
                    control1: point(752.64, 643.413333),
                    control2: point(764.586667, 655.36)
                )
                pageBlock.addCurve(
                    to: point(738.986667, 694.613333),
                    control1: point(764.586667, 682.666667),
                    control2: point(752.64, 694.613333)
                )
                pageBlock.addLine(to: point(245.76, 694.613333))
                pageBlock.addCurve(
                    to: point(136.533333, 803.84),
                    control1: point(186.026667, 694.613333),
                    control2: point(136.533333, 744.106667)
                )
                pageBlock.addCurve(
                    to: point(245.76, 913.066667),
                    control1: point(136.533333, 863.573333),
                    control2: point(186.026667, 913.066667)
                )
                pageBlock.addLine(to: point(848.213333, 913.066667))
                pageBlock.addLine(to: point(848.213333, 129.706667))
                pageBlock.addCurve(
                    to: point(873.813333, 104.106667),
                    control1: point(848.213333, 116.053333),
                    control2: point(860.16, 104.106667)
                )
                pageBlock.addCurve(
                    to: point(899.413333, 129.706667),
                    control1: point(887.466667, 104.106667),
                    control2: point(899.413333, 116.053333)
                )
                pageBlock.addLine(to: point(899.413333, 938.666667))
                pageBlock.addCurve(
                    to: point(875.52, 964.266667),
                    control1: point(901.12, 952.32),
                    control2: point(889.173333, 964.266667)
                )
                pageBlock.closeSubpath()
                context.fill(pageBlock, with: .foreground)

                var bottomRule = Path()
                bottomRule.move(to: point(718.506667, 829.44))
                bottomRule.addLine(to: point(269.653333, 829.44))
                bottomRule.addCurve(
                    to: point(244.053333, 803.84),
                    control1: point(256, 829.44),
                    control2: point(244.053333, 817.493333)
                )
                bottomRule.addCurve(
                    to: point(269.653333, 778.24),
                    control1: point(244.053333, 790.186667),
                    control2: point(256, 778.24)
                )
                bottomRule.addLine(to: point(718.506667, 778.24))
                bottomRule.addCurve(
                    to: point(744.106667, 803.84),
                    control1: point(732.16, 778.24),
                    control2: point(744.106667, 790.186667)
                )
                bottomRule.addCurve(
                    to: point(718.506667, 829.44),
                    control1: point(744.106667, 817.493333),
                    control2: point(732.16, 829.44)
                )
                bottomRule.closeSubpath()
                context.fill(bottomRule, with: .foreground)
            default:
                break
            }
        }
    }
}

// MARK: - Thinking Shimmer

private struct ThinkingShimmerView: View {
    var body: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let cycle = 1.55
            let phase = time.truncatingRemainder(dividingBy: cycle) / cycle
            // center 从 -0.6 扫到 1.6（从左往右），复刻原型 CSS shimmer
            let center = -0.6 + phase * 2.2

            ZStack {
                thinkingText
                    .foregroundStyle(Color(nsColor: HUDLayout.thinkingBaseTextColor))

                thinkingText
                    .foregroundStyle(Color(nsColor: HUDLayout.thinkingHighlightTextColor))
                    .mask {
                        GeometryReader { geo in
                            let w = geo.size.width
                            let gradWidth = w * 2.2
                            let offset = center * w - gradWidth / 2 + w / 2
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0),
                                    .init(color: .clear, location: 0.3),
                                    .init(color: .white, location: 0.48),
                                    .init(color: .clear, location: 0.7),
                                    .init(color: .clear, location: 1)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: gradWidth)
                            .offset(x: offset)
                        }
                    }
            }
        }
    }

    private var thinkingText: some View {
        Text("THINKING")
            .font(.system(size: HUDLayout.textSize, weight: .semibold))
            .tracking(HUDLayout.thinkingTracking)
    }
}
