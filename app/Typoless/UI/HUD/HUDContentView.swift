import SwiftUI

/// HUD 内容视图 — 极简胶囊条
///
/// 录音态：`X + 声波 + ✓`
/// 处理态：Thinking 黑白灰渐变动画
/// 结果态：图标 + 文字
struct HUDContentView: View {
    let controller: HUDFeedbackController
    var onCancel: () -> Void = {}
    var onConfirm: () -> Void = {}

    @State private var phase: VisualPhase = .hidden
    @State private var capsuleWidth: CGFloat = 96
    @State private var capsuleScale: CGFloat = 1
    @State private var capsuleYOffset: CGFloat = 0
    @State private var recordingOpacity: Double = 0
    @State private var processingOpacity: Double = 0
    @State private var resultOpacity: Double = 0
    @State private var recordingControlsOpacity: Double = 0
    @State private var recordingWaveOpacity: Double = 0
    @State private var resultOffsetY: CGFloat = 2
    @State private var resultState: HUDState?
    @State private var transitionTask: Task<Void, Never>?

    private let capsuleHeight: CGFloat = 26

    var body: some View {
        Group {
            if phase != .hidden {
                ZStack {
                    recordingCapsule
                        .opacity(recordingOpacity)
                    thinkingCapsule
                        .opacity(processingOpacity)
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
        HStack(spacing: 4) {
            hudButton(icon: .xMark) { onCancel() }
                .opacity(recordingControlsOpacity)
                .offset(x: recordingControlsOpacity == 0 ? 1 : -2)
            waveformView
            hudButton(icon: .checkMark, isConfirm: true) { onConfirm() }
                .opacity(recordingControlsOpacity)
                .offset(x: recordingControlsOpacity == 0 ? -1 : 2)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 5)
    }

    // MARK: - Thinking Capsule

    private var thinkingCapsule: some View {
        ThinkingShimmerView()
            .padding(.vertical, 3)
            .padding(.horizontal, 10)
    }

    // MARK: - Result Capsule

    private func resultCapsule(for state: HUDState) -> some View {
        let payload = resultPayload(for: state)
        return HStack(spacing: 5) {
            HUDIcon(type: payload.icon)
                .frame(width: 14, height: 14)
                .foregroundStyle(Color.white.opacity(0.92))
            Text(payload.text)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(Color.white.opacity(0.88))
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 10)
    }

    // MARK: - Waveform

    private var waveformView: some View {
        return HStack(spacing: 2) {
            ForEach(0..<controller.barHeights.count, id: \.self) { i in
                RoundedRectangle(cornerRadius: 999)
                    .fill(
                        LinearGradient(
                            colors: [Color.white, Color.white.opacity(0.34)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 3, height: controller.barHeights[i])
                    .opacity(controller.barOpacities[i])
            }
        }
        .frame(width: 34, height: capsuleHeight - 6)
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
            .frame(width: 14, height: 14)
        }
        .buttonStyle(HUDButtonStyle(isConfirm: isConfirm))
        .frame(width: 18, height: 18)
    }

    // MARK: - Common Background

    private var capsuleBackground: some View {
        ZStack {
            Capsule()
                .fill(Color(white: 0.043).opacity(0.93))
                .overlay {
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
                }
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.08), Color.white.opacity(0.03)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            Capsule()
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
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
            capsuleWidth = 96
            capsuleScale = 1
            capsuleYOffset = 0
            recordingOpacity = 0
            processingOpacity = 0
            resultOpacity = 0
            recordingControlsOpacity = 0
            recordingWaveOpacity = 0
            resultOffsetY = 2

        case .recording:
            phase = .recording
            capsuleWidth = 88
            capsuleScale = 1
            capsuleYOffset = 0
            recordingOpacity = 1
            processingOpacity = 0
            resultOpacity = 0
            recordingControlsOpacity = 1
            recordingWaveOpacity = 1
            resultOffsetY = 2

        case .processing:
            phase = .processing
            capsuleWidth = 88
            capsuleScale = 1
            capsuleYOffset = 0
            recordingOpacity = 0
            processingOpacity = 1
            resultOpacity = 0
            recordingControlsOpacity = 0
            recordingWaveOpacity = 0
            resultOffsetY = 2

        case .success, .failure, .cancelled:
            phase = .result
            capsuleWidth = 72
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
                capsuleWidth = 88
                capsuleScale = 0.985
                capsuleYOffset = 0.5
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
                capsuleWidth = 72
                capsuleScale = 0.992
            }
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            phase = .result
            resultOffsetY = 1.5
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
        case .success:
            ("check", "完成")
        case .failure:
            ("warn", "失败")
        case .cancelled:
            ("x", "已取消")
        default:
            ("check", "")
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
        case .success, .failure, .cancelled:
            true
        default:
            false
        }
    }
}

// MARK: - HUD Button Style

private struct HUDButtonStyle: ButtonStyle {
    let isConfirm: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 18, height: 18)
            .background(
                Circle().fill(isConfirm ? Color.white.opacity(0.96) : Color.white.opacity(0.08))
            )
            .overlay(
                Circle()
                    .strokeBorder(Color.white.opacity(isConfirm ? 0 : 0.06), lineWidth: 1)
            )
            .foregroundStyle(isConfirm ? Color(white: 0.043) : Color.white.opacity(0.92))
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
                context.stroke(path, with: .foreground, style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
            case "check":
                var path = Path()
                path.move(to: CGPoint(x: s * 0.14, y: s * 0.53))
                path.addLine(to: CGPoint(x: s * 0.38, y: s * 0.77))
                path.addLine(to: CGPoint(x: s * 0.87, y: s * 0.26))
                context.stroke(path, with: .foreground, style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
            case "warn":
                // 光学对齐：上方竖线略短，底部点不超过竖线视觉宽度
                var path = Path()
                path.move(to: CGPoint(x: s * 0.5, y: s * 0.25))
                path.addLine(to: CGPoint(x: s * 0.5, y: s * 0.56))
                context.stroke(path, with: .foreground, style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                let dotRadius: CGFloat = 0.6
                let dotCenter = CGPoint(x: s * 0.5, y: s * 0.765)
                context.fill(Circle().path(in: CGRect(x: dotCenter.x - dotRadius, y: dotCenter.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2)), with: .foreground)
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
                    .foregroundStyle(Color.white.opacity(0.18))

                thinkingText
                    .foregroundStyle(Color.white.opacity(0.98))
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
            .font(.system(size: 10, weight: .semibold))
            .tracking(1)
    }
}
