import AppKit
import SwiftUI

enum DictionaryEditorMode: Identifiable, Equatable {
    case add
    case edit(DictionaryEntry)

    var id: String {
        switch self {
        case .add:
            "add"
        case .edit(let entry):
            "edit-\(entry.id)"
        }
    }

    var title: String {
        switch self {
        case .add:
            "添加词条"
        case .edit:
            "编辑词条"
        }
    }

    var primaryButtonTitle: String {
        switch self {
        case .add:
            "添加"
        case .edit:
            "保存"
        }
    }

    var initialTerm: String {
        switch self {
        case .add:
            ""
        case .edit(let entry):
            entry.term
        }
    }
}

struct DictionaryEntryEditorSheet: View {
    let mode: DictionaryEditorMode
    let errorMessage: String?
    let onSubmit: (String) -> Bool
    let onDismiss: () -> Void

    @State private var term: String

    init(
        mode: DictionaryEditorMode,
        errorMessage: String?,
        onSubmit: @escaping (String) -> Bool,
        onDismiss: @escaping () -> Void
    ) {
        self.mode = mode
        self.errorMessage = errorMessage
        self.onSubmit = onSubmit
        self.onDismiss = onDismiss
        _term = State(initialValue: mode.initialTerm)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(mode.title)
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 12) {
                    Text("词条")
                        .frame(width: 36, alignment: .trailing)

                    DictionarySheetTermField(
                        text: $term,
                        placeholder: "例如 Typoless",
                        selectAllOnFocus: mode != .add,
                        onSubmit: submit,
                        onCancel: onDismiss
                    )
                    .frame(height: SettingsFormLayout.rowMinHeight)
                    .accessibilityLabel("词条")
                }

                Text(errorMessage ?? " ")
                    .font(.caption)
                    .foregroundStyle(errorMessage == nil ? Color.clear : Color.red)
                    .padding(.leading, 48)
                    .accessibilityHidden(errorMessage == nil)
            }

            HStack {
                Spacer()
                Button("取消") {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)
                .help("取消")

                Button(mode.primaryButtonTitle) {
                    submit()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit)
                .help(mode.primaryButtonTitle)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onExitCommand(perform: onDismiss)
    }

    private var canSubmit: Bool {
        !term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        guard canSubmit else { return }
        if onSubmit(term) {
            onDismiss()
        }
    }
}

private struct DictionarySheetTermField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let selectAllOnFocus: Bool
    let onSubmit: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit, onCancel: onCancel)
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
        textField.usesSingleLineMode = true
        textField.placeholderString = placeholder
        textField.stringValue = text
        textField.setAccessibilityLabel("词条")
        textField.target = context.coordinator
        textField.action = #selector(Coordinator.submitFromAction(_:))
        DispatchQueue.main.async {
            guard let window = textField.window else { return }
            window.makeFirstResponder(textField)
            if selectAllOnFocus {
                textField.currentEditor()?.selectAll(nil)
            }
        }
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.onSubmit = onSubmit
        context.coordinator.onCancel = onCancel
        nsView.placeholderString = placeholder
        if nsView.stringValue != text, nsView.currentEditor() == nil {
            nsView.stringValue = text
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        var onSubmit: () -> Void
        var onCancel: () -> Void

        init(text: Binding<String>, onSubmit: @escaping () -> Void, onCancel: @escaping () -> Void) {
            _text = text
            self.onSubmit = onSubmit
            self.onCancel = onCancel
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField else { return }
            text = textField.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                onCancel()
                return true
            }
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
            if textView.hasMarkedText() {
                return false
            }
            text = control.stringValue
            onSubmit()
            return true
        }

        @objc func submitFromAction(_ sender: NSTextField) {
            text = sender.stringValue
            onSubmit()
        }
    }
}
