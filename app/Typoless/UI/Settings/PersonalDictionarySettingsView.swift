import SwiftUI

struct PersonalDictionarySettingsView: View {
    private static let dictionaryListBottomAnchorID = "dictionary-list-bottom-anchor"

    private enum Layout {
        static let listHeight: CGFloat = 315
        static let rowHeight: CGFloat = 28
        static let rowSpacing: CGFloat = 6
        static let leadingInset: CGFloat = 4
        static let trailingInset: CGFloat = 0
        static let scrollbarReserve: CGFloat = 20
        static let deleteButtonWidth: CGFloat = 22
        static let rowControlSpacing: CGFloat = 3
        static let footerOffset: CGFloat =
            (SettingsFormLayout.contentWidth - SettingsFormLayout.controlWidth) / 2
            - (SettingsFormLayout.labelWidth + SettingsFormLayout.rowSpacing)
            + leadingInset
        static let editorWidth: CGFloat =
            SettingsFormLayout.controlWidth
            - leadingInset
            - trailingInset
            - scrollbarReserve
            - deleteButtonWidth
            - rowControlSpacing
    }

    @State private var viewModel: PersonalDictionaryViewModel
    @State private var draftTerms: [String: String] = [:]
    @State private var selection: String?
    @State private var pendingScrollTargetID: String?
    @FocusState private var focusedEntryID: String?

    init(dictionaryStore: PersonalDictionaryStore) {
        _viewModel = State(wrappedValue: PersonalDictionaryViewModel(store: dictionaryStore))
    }

    var body: some View {
        SettingsPaneSection {
            VStack(alignment: .leading, spacing: 0) {
                dictionaryContent
            }
            .frame(maxWidth: .infinity, alignment: .center)
        } footer: {
            Text("词典将辅助语音识别和模型处理文本提高识别率。")
                .offset(x: Layout.footerOffset)
        }
        .onAppear { syncDraftTerms() }
    }

    private var dictionaryContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            dictionaryList

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.leading, Layout.leadingInset)
            }

            controls
        }
        .frame(width: SettingsFormLayout.controlWidth, alignment: .leading)
    }

    private var dictionaryList: some View {
        ScrollViewReader { proxy in
            Group {
                if viewModel.entries.isEmpty {
                    Text("暂无词条")
                        .foregroundStyle(.secondary)
                        .frame(width: SettingsFormLayout.controlWidth, alignment: .leading)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: Layout.rowSpacing) {
                            ForEach(viewModel.entries) { entry in
                                dictionaryRow(for: entry)
                                    .id(entry.id)
                            }

                            Color.clear
                                .frame(height: 1)
                                .id(Self.dictionaryListBottomAnchorID)
                        }
                        .padding(.vertical, 2)
                        .padding(.leading, Layout.leadingInset)
                        .padding(.trailing, Layout.trailingInset + Layout.scrollbarReserve)
                    }
                    .frame(width: SettingsFormLayout.controlWidth, height: Layout.listHeight)
                }
            }
            .onChange(of: pendingScrollTargetID) {
                guard let targetID = pendingScrollTargetID else { return }
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.16)) {
                        proxy.scrollTo(Self.dictionaryListBottomAnchorID, anchor: .bottom)
                    }
                    focusedEntryID = targetID
                    selection = targetID
                    pendingScrollTargetID = nil
                }
            }
        }
        .onDeleteCommand {
            removeSelection()
        }
    }

    private var controls: some View {
        HStack {
            Button("添加") {
                let placeholder = makePlaceholderTerm()
                viewModel.addPlaceholderTerm(placeholder)
                syncDraftTerms(preservingExistingDrafts: true)
                pendingScrollTargetID = viewModel.entries.last?.id
            }
            .help("添加词条")

            Spacer()
        }
        .padding(.leading, Layout.leadingInset)
    }

    private func dictionaryRow(for entry: DictionaryEntry) -> some View {
        HStack(spacing: Layout.rowControlSpacing) {
            DictionaryTermInputField(
                text: draftTerms[entry.id] ?? entry.term,
                width: Layout.editorWidth,
                onCommit: { value in
                    commitDraft(id: entry.id, term: value)
                }
            )
            .focused($focusedEntryID, equals: entry.id)
            .frame(width: Layout.editorWidth, height: Layout.rowHeight, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                selection = entry.id
                if focusedEntryID != entry.id {
                    focusedEntryID = entry.id
                }
            }

            Button {
                viewModel.deleteEntry(entry)
                draftTerms.removeValue(forKey: entry.id)
                if selection == entry.id {
                    selection = nil
                }
                if focusedEntryID == entry.id {
                    focusedEntryID = nil
                }
            } label: {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: Layout.deleteButtonWidth, height: Layout.rowHeight)
            .help("删除词条")
        }
        .onChange(of: focusedEntryID) {
            if focusedEntryID == entry.id {
                selection = entry.id
            }
        }
    }

    @discardableResult
    private func commitDraft(id: String, term: String) -> Bool {
        draftTerms[id] = term
        if viewModel.commitTermUpdate(id: id, term: term),
           let updatedEntry = viewModel.entries.first(where: { $0.id == id }) {
            draftTerms[id] = updatedEntry.term
            return true
        }
        return false
    }

    private func removeSelection() {
        guard let selection,
              let entry = viewModel.entries.first(where: { $0.id == selection }) else { return }
        viewModel.deleteEntry(entry)
        self.selection = nil
        focusedEntryID = nil
        syncDraftTerms(preservingExistingDrafts: true)
    }

    private func syncDraftTerms(preservingExistingDrafts: Bool = false) {
        draftTerms = Dictionary(
            uniqueKeysWithValues: viewModel.entries.map { entry in
                let term = preservingExistingDrafts ? draftTerms[entry.id] ?? entry.term : entry.term
                return (entry.id, term)
            }
        )
    }

    private func makePlaceholderTerm() -> String {
        let base = "新词条"
        guard viewModel.entries.contains(where: { $0.term == base }) else {
            return base
        }

        var index = 2
        while viewModel.entries.contains(where: { $0.term == "\(base) \(index)" }) {
            index += 1
        }
        return "\(base) \(index)"
    }
}

private struct DictionaryTermInputField: NSViewRepresentable {
    let text: String
    let width: CGFloat
    let onCommit: (String) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(onCommit: onCommit)
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
        textField.stringValue = text
        context.coordinator.resetCommittedText(text)
        textField.target = context.coordinator
        textField.action = #selector(Coordinator.commitFromAction(_:))
        configureDictionaryTermField(textField, width: width)
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.onCommit = onCommit
        if !context.coordinator.isEditing, nsView.stringValue != text {
            nsView.stringValue = text
            context.coordinator.resetCommittedText(text)
        }
        configureDictionaryTermField(nsView, width: width)
    }

    static func dismantleNSView(_ nsView: NSTextField, coordinator: Coordinator) {
        coordinator.commit(nsView)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var onCommit: (String) -> Bool
        var isEditing = false
        private var lastCommittedText: String?

        init(onCommit: @escaping (String) -> Bool) {
            self.onCommit = onCommit
        }

        func resetCommittedText(_ text: String) {
            lastCommittedText = text
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            isEditing = true
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField else { return }
            isEditing = false
            commit(textField)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
            if textView.hasMarkedText() {
                return false
            }
            commit(control)
            control.window?.makeFirstResponder(nil)
            return true
        }

        @objc func commitFromAction(_ sender: NSTextField) {
            commit(sender)
        }

        func commit(_ control: NSControl) {
            let text = control.stringValue
            guard text != lastCommittedText else { return }
            if onCommit(text) {
                lastCommittedText = text
            }
        }
    }
}

@MainActor
private func configureDictionaryTermField(_ textField: NSTextField, width: CGFloat) {
    let identifier = "DictionaryTermFixedWidthConstraint"
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
