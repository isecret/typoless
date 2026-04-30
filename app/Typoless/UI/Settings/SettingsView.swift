import SwiftUI

struct SettingsView: View {
    @Bindable var appCoordinator: AppCoordinator

    var body: some View {
        Form {
            GeneralSettingsView(configStore: appCoordinator.configStore, onHotkeyChanged: {
                appCoordinator.setupHotkey()
            })
            ASRSettingsView(configStore: appCoordinator.configStore)
            LLMSettingsView(configStore: appCoordinator.configStore)
            PermissionsSettingsView(permissionsManager: appCoordinator.permissionsManager)
            ClipboardWhitelistSettingsView(configStore: appCoordinator.configStore)
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 680)
    }
}

private enum SettingsFormLayout {
    static let labelWidth: CGFloat = 104
    static let rowSpacing: CGFloat = 12
    static let rowMinHeight: CGFloat = 28
}

struct SettingsFormRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: SettingsFormLayout.rowSpacing) {
            Text(title)
                .frame(width: SettingsFormLayout.labelWidth, alignment: .leading)
                .frame(minHeight: SettingsFormLayout.rowMinHeight, alignment: .leading)

            content()
                .frame(maxWidth: .infinity, alignment: .trailing)
                .frame(minHeight: SettingsFormLayout.rowMinHeight, alignment: .trailing)
        }
    }
}

struct SettingsTextInputField: View {
    @Binding var text: String
    var width: CGFloat = 320
    var placeholder: String?

    var body: some View {
        SettingsTextFieldRepresentable(text: $text, width: width, placeholder: placeholder)
            .frame(width: width, height: SettingsFormLayout.rowMinHeight)
    }
}

struct SettingsSecureInputField: View {
    @Binding var text: String
    var width: CGFloat = 320

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
        textField.alignment = .right
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
        textField.alignment = .right
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
