import SwiftUI

struct PersonalDictionarySettingsView: View {
    @State private var viewModel: PersonalDictionaryViewModel
    @State private var draftTerms: [String: String] = [:]
    @State private var isDeleteConfirmationPresented = false
    @State private var entryPendingDeletion: DictionaryEntry?

    init(dictionaryStore: PersonalDictionaryStore) {
        _viewModel = State(wrappedValue: PersonalDictionaryViewModel(store: dictionaryStore))
    }

    var body: some View {
        SettingsPaneSection {
            SettingsFormRow(title: "新增词条") {
                HStack(spacing: 8) {
                    SettingsTextInputField(
                        text: $viewModel.newTerm,
                        width: 286,
                        placeholder: "添加人名、产品名、术语"
                    )

                    Button("添加") {
                        viewModel.addTerm()
                        syncDraftTerms()
                    }
                }
            }

            SettingsFormRow(title: "词条列表") {
                dictionaryList
            }

            if let errorMessage = viewModel.errorMessage {
                SettingsFormRow(title: "") {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        } footer: {
            Text("共 \(viewModel.totalCount) 个词条，启用 \(viewModel.enabledCount) 个")
        }
        .onAppear { syncDraftTerms() }
        .onChange(of: viewModel.editRevision) {
            syncDraftTerms()
        }
        .onDisappear {
            viewModel.flushPendingEdits()
            syncDraftTerms()
        }
        .confirmationDialog(
            "删除词条？",
            isPresented: $isDeleteConfirmationPresented
        ) {
            Button("删除", role: .destructive) {
                if let entry = entryPendingDeletion {
                    viewModel.deleteEntry(entry)
                }
                entryPendingDeletion = nil
                syncDraftTerms()
            }
            Button("取消", role: .cancel) {
                entryPendingDeletion = nil
            }
        } message: {
            if let term = entryPendingDeletion?.term {
                Text("将删除“\(term)”")
            }
        }
        .onChange(of: isDeleteConfirmationPresented) {
            if !isDeleteConfirmationPresented {
                entryPendingDeletion = nil
            }
        }
    }

    @ViewBuilder
    private var dictionaryList: some View {
        if viewModel.entries.isEmpty {
            Text("暂无词条")
                .foregroundStyle(.secondary)
                .frame(width: SettingsFormLayout.controlWidth, alignment: .leading)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(viewModel.entries) { entry in
                        dictionaryRow(entry)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(width: SettingsFormLayout.controlWidth, height: 190)
        }
    }

    private func dictionaryRow(_ entry: DictionaryEntry) -> some View {
        HStack(spacing: 8) {
            Toggle(
                "",
                isOn: Binding(
                    get: { entry.enabled },
                    set: { _ in viewModel.toggleEnabled(id: entry.id) }
                )
            )
            .toggleStyle(.checkbox)
            .labelsHidden()
            .help(entry.enabled ? "禁用词条" : "启用词条")

            SettingsTextInputField(
                text: Binding(
                    get: { draftTerms[entry.id] ?? entry.term },
                    set: { value in
                        draftTerms[entry.id] = value
                        viewModel.scheduleTermUpdate(id: entry.id, term: value)
                    }
                ),
                width: 282
            )

            Button {
                entryPendingDeletion = entry
                isDeleteConfirmationPresented = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13))
            }
            .buttonStyle(.borderless)
            .help("删除词条")
            .accessibilityLabel("删除词条")
        }
        .frame(height: 28)
    }

    private func syncDraftTerms() {
        draftTerms = Dictionary(uniqueKeysWithValues: viewModel.entries.map { ($0.id, $0.term) })
    }
}
