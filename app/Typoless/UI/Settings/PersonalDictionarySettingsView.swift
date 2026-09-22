import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PersonalDictionarySettingsView: View {
    private enum Layout {
        static let workspaceWidth: CGFloat = 440
        static let listHeight: CGFloat = 280
        static let accessoryHeight: CGFloat = 30
        static let searchWidth: CGFloat = 180
        static let headerSpacing: CGFloat = 12
        static let stackSpacing: CGFloat = 7
        static let listCornerRadius: CGFloat = 6
    }

    @State private var viewModel: PersonalDictionaryViewModel
    @State private var searchText = ""
    @State private var selectedEntryID: String?
    @FocusState private var isListFocused: Bool
    @State private var editorMode: DictionaryEditorMode?
    @State private var pendingScrollTargetID: String?
    @State private var statusMessage: String?
    @State private var alertMessage: String?
    @State private var statusTask: Task<Void, Never>?

    init(dictionaryStore: PersonalDictionaryStore) {
        _viewModel = State(wrappedValue: PersonalDictionaryViewModel(store: dictionaryStore))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.headerSpacing) {
            header
            VStack(alignment: .leading, spacing: Layout.stackSpacing) {
                listContainer
                toolbar
                footer
            }
        }
        .frame(width: Layout.workspaceWidth)
        .frame(width: SettingsFormLayout.contentWidth, alignment: .center)
        .sheet(item: $editorMode, onDismiss: { viewModel.errorMessage = nil }) { mode in
            DictionaryEntryEditorSheet(
                mode: mode,
                errorMessage: viewModel.errorMessage,
                onSubmit: { submitEditor(mode: mode, term: $0) },
                onDismiss: { editorMode = nil }
            )
        }
        .alert("词典操作失败", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("好", role: .cancel) { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
        .onChange(of: viewModel.entries) {
            reconcileSelection()
        }
        .onDisappear {
            statusTask?.cancel()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("常用词")
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 8)

            SettingsTextInputField(
                text: $searchText,
                width: Layout.searchWidth,
                placeholder: "搜索词条…"
            )
            .help("搜索词条")
            .accessibilityLabel("搜索词条")
        }
        .frame(width: Layout.workspaceWidth, alignment: .leading)
    }

    private var listContainer: some View {
        ScrollViewReader { proxy in
            List(selection: $selectedEntryID) {
                ForEach(displayedEntries) { entry in
                    Text(entry.term)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .tag(entry.id)
                        .id(entry.id)
                        .simultaneousGesture(
                            TapGesture(count: 2).onEnded {
                                editorMode = .edit(entry)
                            }
                        )
                        .contextMenu {
                            Button("编辑") {
                                editorMode = .edit(entry)
                            }
                            Button("删除", role: .destructive) {
                                delete(entry)
                            }
                        }
                        .accessibilityLabel(entry.term)
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: false))
            .environment(\.defaultMinListRowHeight, 28)
            .focused($isListFocused)
            .onChange(of: selectedEntryID) {
                if selectedEntryID != nil {
                    isListFocused = true
                }
            }
            .frame(width: Layout.workspaceWidth, height: Layout.listHeight)
            .clipShape(
                RoundedRectangle(cornerRadius: Layout.listCornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Layout.listCornerRadius, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .onDeleteCommand(perform: deleteSelection)
            .onKeyPress(.return) { handleReturnKey() }
            .overlay {
                if viewModel.entries.isEmpty {
                    dictionaryEmptyState
                        .allowsHitTesting(false)
                } else if displayedEntries.isEmpty {
                    searchEmptyState
                        .allowsHitTesting(false)
                }
            }
            .onChange(of: pendingScrollTargetID) {
                guard let targetID = pendingScrollTargetID else { return }
                DispatchQueue.main.async {
                    proxy.scrollTo(targetID, anchor: .center)
                    pendingScrollTargetID = nil
                }
            }
            .accessibilityLabel("词条列表")
        }
    }

    private var toolbar: some View {
        HStack(spacing: 0) {
            DictionaryAccessoryControl(
                canRemove: selectedEntryID != nil,
                onAdd: {
                    viewModel.errorMessage = nil
                    editorMode = .add
                },
                onRemove: deleteSelection,
                onImport: importDictionary,
                onExport: exportDictionary
            )

            ZStack {
                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity)

            Text("\(viewModel.totalCount) 个词条")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel("\(viewModel.totalCount) 个词条")
        }
        .frame(height: Layout.accessoryHeight)
    }

    private var footer: some View {
        Text("添加人名、产品名和专业术语，Typoless 会尽量保留这些写法。")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: Layout.workspaceWidth, alignment: .leading)
    }

    private var dictionaryEmptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "text.book.closed")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("还没有词条")
            Text("点击添加常用人名、产品名或专业术语，也可以从文件导入。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: Layout.workspaceWidth - 48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var searchEmptyState: some View {
        Text("未找到词条")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("未找到词条")
    }

    private var displayedEntries: [DictionaryEntry] {
        viewModel.filteredEntries(matching: searchText)
    }

    private var selectedEntry: DictionaryEntry? {
        guard let selectedEntryID else { return nil }
        return displayedEntries.first(where: { $0.id == selectedEntryID })
            ?? viewModel.entries.first(where: { $0.id == selectedEntryID })
    }

    private func handleReturnKey() -> KeyPress.Result {
        guard editorMode == nil, let selectedEntry else { return .ignored }
        editorMode = .edit(selectedEntry)
        return .handled
    }

    @discardableResult
    private func submitEditor(mode: DictionaryEditorMode, term: String) -> Bool {
        switch mode {
        case .add:
            guard viewModel.addTerm(term) else { return false }
            revealEntry(matching: term)
            return true
        case .edit(let entry):
            guard viewModel.commitTermUpdate(id: entry.id, term: term) else { return false }
            revealEntry(id: entry.id, matching: term)
            return true
        }
    }

    private func revealEntry(id: String? = nil, matching term: String) {
        let normalized = term.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty, !normalized.localizedCaseInsensitiveContains(query) {
            searchText = ""
        }

        let targetID = id ?? viewModel.entries.first(where: { $0.term == normalized })?.id
        selectedEntryID = targetID
        pendingScrollTargetID = targetID
    }

    private func deleteSelection() {
        guard let selectedEntryID,
              let entry = viewModel.entries.first(where: { $0.id == selectedEntryID }) else { return }
        delete(entry)
    }

    private func delete(_ entry: DictionaryEntry) {
        let nextSelection = viewModel.neighboringEntryID(afterDeleting: entry.id)
        guard viewModel.deleteEntry(entry) else {
            presentAlert(viewModel.errorMessage ?? PersonalDictionaryViewModel.ValidationError.saveFailed.rawValue)
            return
        }
        selectedEntryID = nextSelection
    }

    private func reconcileSelection() {
        if let selectedEntryID, viewModel.entries.contains(where: { $0.id == selectedEntryID }) == false {
            self.selectedEntryID = nil
        }
    }

    private func importDictionary() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.json]
        panel.prompt = "导入"
        panel.message = "选择一个 Typoless 词典 JSON 文件"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        viewModel.importEntries(from: url)
        presentOperationResult()
    }

    private func exportDictionary() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "typoless-dictionary.json"
        panel.prompt = "导出"
        panel.message = "导出 Typoless 词典 JSON 文件"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        viewModel.exportEntries(to: url)
        presentOperationResult()
    }

    private func presentOperationResult() {
        if let errorMessage = viewModel.errorMessage {
            presentAlert(errorMessage)
            return
        }
        showStatus(viewModel.statusMessage)
    }

    private func presentAlert(_ message: String) {
        alertMessage = message
        statusMessage = nil
    }

    private func showStatus(_ message: String?) {
        statusTask?.cancel()
        withAnimation(.easeInOut(duration: 0.16)) {
            statusMessage = message
        }
        guard message != nil else { return }
        statusTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.16)) {
                statusMessage = nil
            }
        }
    }
}
