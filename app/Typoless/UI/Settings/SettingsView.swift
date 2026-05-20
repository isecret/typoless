import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case asr
    case ai
    case permissions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            "通用"
        case .asr:
            "语音"
        case .ai:
            "模型"
        case .permissions:
            "权限"
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            "gearshape"
        case .asr:
            "waveform"
        case .ai:
            "sparkles"
        case .permissions:
            "lock.shield"
        }
    }

    var defaultContentSize: NSSize {
        switch self {
        case .general:
            NSSize(width: SettingsFormLayout.windowContentWidth, height: 320)
        case .asr:
            NSSize(width: SettingsFormLayout.windowContentWidth, height: 270)
        case .ai:
            NSSize(width: SettingsFormLayout.windowContentWidth, height: 250)
        case .permissions:
            NSSize(width: SettingsFormLayout.windowContentWidth, height: 170)
        }
    }
}

struct SettingsView: View {
    @Bindable var appCoordinator: AppCoordinator

    var body: some View {
        SettingsPaneContainer {
            switch appCoordinator.selectedSettingsTab {
            case .general:
                GeneralSettingsView(configStore: appCoordinator.configStore, updateService: appCoordinator.updateService, onHotkeyChanged: {
                    appCoordinator.setupHotkey()
                })
            case .asr:
                ASRSettingsView(configStore: appCoordinator.configStore)
            case .ai:
                LLMSettingsView(configStore: appCoordinator.configStore)
            case .permissions:
                PermissionsSettingsView(permissionsManager: appCoordinator.permissionsManager)
            }
        }
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: SettingsContentSizePreferenceKey.self, value: proxy.size)
            }
        )
        .onPreferenceChange(SettingsContentSizePreferenceKey.self) { size in
            appCoordinator.updateSettingsContentSize(size, for: appCoordinator.selectedSettingsTab)
        }
    }
}

enum SettingsFormLayout {
    static let contentWidth: CGFloat = 520
    static let horizontalPadding: CGFloat = 28
    static let windowContentWidth: CGFloat = contentWidth + horizontalPadding * 2
    static let labelWidth: CGFloat = 116
    static let rowSpacing: CGFloat = 12
    static let rowMinHeight: CGFloat = 26
    static let controlWidth: CGFloat = 360
    static let sectionSpacing: CGFloat = 0
    static let sectionVerticalPadding: CGFloat = 9
}

struct SettingsFormRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: SettingsFormLayout.rowSpacing) {
            Text(title)
                .frame(width: SettingsFormLayout.labelWidth, alignment: .trailing)
                .frame(minHeight: SettingsFormLayout.rowMinHeight, alignment: .trailing)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: SettingsFormLayout.rowMinHeight, alignment: .leading)
        }
    }
}

struct SettingsPaneContainer<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsFormLayout.sectionSpacing) {
            content()
        }
        .padding(.top, 16)
        .padding(.bottom, 16)
        .frame(width: SettingsFormLayout.contentWidth, alignment: .leading)
        .padding(.horizontal, SettingsFormLayout.horizontalPadding)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct SettingsPaneSection<Content: View, Footer: View>: View {
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: () -> Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            content()

            footer()
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(
                    width: SettingsFormLayout.contentWidth - SettingsFormLayout.labelWidth - SettingsFormLayout.rowSpacing,
                    alignment: .leading
                )
                .padding(.leading, SettingsFormLayout.labelWidth + SettingsFormLayout.rowSpacing)
        }
        .padding(.vertical, SettingsFormLayout.sectionVerticalPadding)
    }
}

struct SettingsTextInputField: View {
    @Binding var text: String
    var width: CGFloat = SettingsFormLayout.controlWidth
    var placeholder: String?

    var body: some View {
        SettingsTextFieldRepresentable(text: $text, width: width, placeholder: placeholder)
            .frame(width: width, height: SettingsFormLayout.rowMinHeight)
    }
}

struct SettingsSecureInputField: View {
    @Binding var text: String
    var width: CGFloat = SettingsFormLayout.controlWidth

    var body: some View {
        SettingsSecureTextFieldRepresentable(text: $text, width: width)
            .frame(width: width, height: SettingsFormLayout.rowMinHeight)
    }
}

struct SettingsTextFieldRepresentable: NSViewRepresentable {
    @Binding var text: String
    var width: CGFloat
    var placeholder: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField(frame: .zero)
        textField.delegate = context.coordinator
        textField.isBordered = true
        textField.isBezeled = true
        textField.bezelStyle = .roundedBezel
        textField.controlSize = .regular
        textField.focusRingType = .default
        textField.lineBreakMode = .byTruncatingTail
        textField.maximumNumberOfLines = 1
        textField.alignment = .natural
        textField.font = .systemFont(ofSize: NSFont.systemFontSize)
        textField.placeholderString = placeholder
        textField.stringValue = text
        configureAppKitField(textField, width: width, identifier: "SettingsTextFixedWidthConstraint")
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.placeholderString = placeholder
        configureAppKitField(nsView, width: width, identifier: "SettingsTextFixedWidthConstraint")
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField else { return }
            text = textField.stringValue
        }
    }
}

struct SettingsSecureTextFieldRepresentable: NSViewRepresentable {
    @Binding var text: String
    var width: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSSecureTextField {
        let textField = NSSecureTextField(frame: .zero)
        textField.delegate = context.coordinator
        textField.isBordered = true
        textField.isBezeled = true
        textField.bezelStyle = .roundedBezel
        textField.controlSize = .regular
        textField.focusRingType = .default
        textField.lineBreakMode = .byTruncatingTail
        textField.maximumNumberOfLines = 1
        textField.alignment = .natural
        textField.font = .systemFont(ofSize: NSFont.systemFontSize)
        textField.stringValue = text
        configureAppKitField(textField, width: width, identifier: "SettingsSecureFixedWidthConstraint")
        return textField
    }

    func updateNSView(_ nsView: NSSecureTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        configureAppKitField(nsView, width: width, identifier: "SettingsSecureFixedWidthConstraint")
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let textField = obj.object as? NSSecureTextField else { return }
            text = textField.stringValue
        }
    }
}

@MainActor
private func configureAppKitField(_ textField: NSTextField, width: CGFloat, identifier: String) {
    textField.translatesAutoresizingMaskIntoConstraints = false
    textField.lineBreakMode = .byTruncatingTail
    textField.maximumNumberOfLines = 1
    textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
    textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    if let widthConstraint = textField.constraints.first(where: { $0.identifier == identifier }) {
        widthConstraint.constant = width
    } else {
        let widthConstraint = textField.widthAnchor.constraint(equalToConstant: width)
        widthConstraint.identifier = identifier
        widthConstraint.priority = .required
        widthConstraint.isActive = true
    }
}

private struct SettingsContentSizePreferenceKey: PreferenceKey {
    static let defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let nextValue = nextValue()
        guard nextValue != .zero else { return }
        value = nextValue
    }
}
