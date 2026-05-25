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
        .onChange(of: viewModel.editRevision) {
            syncDraftTerms()
        }
        .onDisappear {
            viewModel.flushPendingEdits()
            syncDraftTerms()
        }
    }

    private var dictionaryContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            dictionaryList
            controls

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
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
                syncDraftTerms()
                pendingScrollTargetID = viewModel.entries.last?.id
            }
            .help("添加词条")

            Spacer()
        }
        .padding(.leading, Layout.leadingInset)
    }

    private func dictionaryRow(for entry: DictionaryEntry) -> some View {
        HStack(spacing: Layout.rowControlSpacing) {
            SettingsTextInputField(
                text: Binding(
                    get: { draftTerms[entry.id] ?? entry.term },
                    set: { value in
                        draftTerms[entry.id] = value
                        viewModel.scheduleTermUpdate(id: entry.id, term: value)
                    }
                ),
                width: Layout.editorWidth
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

    private func removeSelection() {
        guard let selection,
              let entry = viewModel.entries.first(where: { $0.id == selection }) else { return }
        viewModel.deleteEntry(entry)
        self.selection = nil
        focusedEntryID = nil
        syncDraftTerms()
    }

    private func syncDraftTerms() {
        draftTerms = Dictionary(uniqueKeysWithValues: viewModel.entries.map { ($0.id, $0.term) })
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
