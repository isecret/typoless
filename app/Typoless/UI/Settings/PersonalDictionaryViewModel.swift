import Foundation

@MainActor
@Observable
final class PersonalDictionaryViewModel {
    enum ValidationError: String, Equatable {
        case empty = "请输入词条"
        case duplicate = "词条已存在"
        case saveFailed = "保存失败"
    }

    var errorMessage: String?
    private let store: PersonalDictionaryStore

    init(store: PersonalDictionaryStore) {
        self.store = store
    }

    var entries: [DictionaryEntry] {
        store.entries
    }

    var totalCount: Int {
        entries.count
    }

    func addPlaceholderTerm(_ term: String) {
        do {
            try store.addEntry(DictionaryEntry(term: term))
            clearError()
        } catch {
            showError(.saveFailed)
        }
    }

    func deleteEntry(_ entry: DictionaryEntry) {
        do {
            try store.removeEntry(id: entry.id)
            clearError()
        } catch {
            showError(.saveFailed)
        }
    }

    @discardableResult
    func commitTermUpdate(id: String, term: String) -> Bool {
        let term = normalizedTerm(term)
        guard let entry = entries.first(where: { $0.id == id }) else { return false }
        guard term != normalizedTerm(entry.term) else {
            clearError()
            return true
        }

        if term.isEmpty {
            showError(.empty)
            return false
        }

        guard validateEditedTerm(term, editingID: id) else { return false }

        var updated = entry
        updated.term = term

        do {
            try store.updateEntry(updated)
            clearError()
            return true
        } catch {
            showError(.saveFailed)
            return false
        }
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

    private func showError(_ error: ValidationError) {
        errorMessage = error.rawValue
    }

    private func clearError() {
        errorMessage = nil
    }
}
