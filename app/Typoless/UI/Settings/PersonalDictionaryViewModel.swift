import Foundation

@MainActor
@Observable
final class PersonalDictionaryViewModel {
    enum ValidationError: String, Equatable {
        case empty = "请输入词条"
        case duplicate = "词条已存在"
        case saveFailed = "保存失败"
        case importFailed = "导入失败，请选择有效的 JSON 词典文件"
        case exportFailed = "导出失败"
    }

    var errorMessage: String?
    var statusMessage: String?
    private(set) var entries: [DictionaryEntry]
    private(set) var editRevision = 0

    private let store: PersonalDictionaryStore
    private var editTasks: [String: Task<Void, Never>] = [:]
    private var pendingEdits: [String: String] = [:]
    private let debounceDuration: Duration

    init(store: PersonalDictionaryStore, debounceDuration: Duration = .milliseconds(500)) {
        self.store = store
        self.entries = store.entries
        self.debounceDuration = debounceDuration
    }

    var totalCount: Int {
        entries.count
    }

    func addPlaceholderTerm(_ term: String) {
        do {
            try store.addEntry(DictionaryEntry(term: term))
            refreshEntries()
            statusMessage = nil
            clearError()
        } catch {
            showError(.saveFailed)
        }
    }

    func scheduleTermUpdate(id: String, term: String) {
        editTasks[id]?.cancel()
        let normalized = normalizedTerm(term)
        pendingEdits[id] = normalized

        editTasks[id] = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: debounceDuration)
            guard !Task.isCancelled else { return }
            self.commitTermUpdate(id: id, term: normalized)
        }
    }

    func deleteEntry(_ entry: DictionaryEntry) {
        editTasks[entry.id]?.cancel()
        editTasks[entry.id] = nil
        pendingEdits[entry.id] = nil

        do {
            try store.removeEntry(id: entry.id)
            refreshEntries()
            statusMessage = nil
            clearError()
        } catch {
            showError(.saveFailed)
        }
    }

    func importEntries(from fileURL: URL) {
        flushPendingEdits()

        do {
            let summary = try store.importEntries(from: fileURL)
            refreshEntries()
            editRevision += 1
            clearError()
            if summary.importedCount == 0 {
                statusMessage = summary.skippedDuplicateCount > 0 ? "没有新增词条，重复词条已跳过" : "没有可导入的词条"
            } else if summary.skippedDuplicateCount > 0 {
                statusMessage = "已导入 \(summary.importedCount) 个词条，跳过 \(summary.skippedDuplicateCount) 个重复词条"
            } else {
                statusMessage = "已导入 \(summary.importedCount) 个词条"
            }
        } catch {
            showError(.importFailed)
        }
    }

    func exportEntries(to fileURL: URL) {
        flushPendingEdits()

        do {
            try store.exportEntries(to: fileURL)
            clearError()
            statusMessage = "已导出 \(entries.count) 个词条"
        } catch {
            showError(.exportFailed)
        }
    }

    func flushPendingEdits() {
        let pending = pendingEdits
        editTasks.values.forEach { $0.cancel() }
        editTasks.removeAll()
        pendingEdits.removeAll()

        for (id, term) in pending {
            commitTermUpdate(id: id, term: term)
        }
    }

    private func commitTermUpdate(id: String, term: String) {
        editTasks[id] = nil
        pendingEdits[id] = nil
        guard let entry = entries.first(where: { $0.id == id }) else { return }
        guard term != normalizedTerm(entry.term) else {
            clearError()
            return
        }

        if term.isEmpty {
            deleteEntry(entry)
            clearError()
            return
        }

        guard validateEditedTerm(term, editingID: id) else { return }

        var updated = entry
        updated.term = term

        do {
            try store.updateEntry(updated)
            refreshEntries()
            editRevision += 1
            statusMessage = nil
            clearError()
        } catch {
            showError(.saveFailed)
        }
    }

    private func validateNewTerm(_ term: String) -> Bool {
        validateTerm(term, editingID: nil)
    }

    private func validateEditedTerm(_ term: String, editingID: String) -> Bool {
        validateTerm(term, editingID: editingID)
    }

    private func validateTerm(_ term: String, editingID: String?) -> Bool {
        guard !term.isEmpty else {
            showError(.empty)
            return false
        }

        let hasDuplicate = entries.contains { entry in
            entry.id != editingID && normalizedTerm(entry.term) == term
        }
        guard !hasDuplicate else {
            showError(.duplicate)
            return false
        }

        return true
    }

    private func normalizedTerm(_ term: String) -> String {
        term.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func refreshEntries() {
        entries = store.entries
    }

    private func showError(_ error: ValidationError) {
        errorMessage = error.rawValue
        statusMessage = nil
    }

    private func clearError() {
        errorMessage = nil
    }
}
