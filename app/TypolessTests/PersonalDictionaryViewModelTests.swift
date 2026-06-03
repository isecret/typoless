import XCTest
@testable import Typoless

final class PersonalDictionaryViewModelTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    @MainActor
    func testAddPlaceholderCreatesTermWithNilOptionalFields() {
        let viewModel = makeViewModel()

        viewModel.addPlaceholderTerm("Typoless")

        XCTAssertEqual(viewModel.entries.count, 1)
        XCTAssertEqual(viewModel.entries[0].term, "Typoless")
        XCTAssertNil(viewModel.entries[0].pronunciationHint)
        XCTAssertNil(viewModel.entries[0].category)
    }

    @MainActor
    func testCommittedEditPersistsImmediately() {
        let viewModel = makeViewModel()
        viewModel.addPlaceholderTerm("旧词")
        let id = viewModel.entries[0].id

        let didCommit = viewModel.commitTermUpdate(id: id, term: " 新词 ")

        XCTAssertTrue(didCommit)
        XCTAssertEqual(viewModel.entries[0].term, "新词")
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testEditRejectsEmptyAndDuplicateTerms() {
        let viewModel = makeViewModel()
        viewModel.addPlaceholderTerm("Typoless")
        viewModel.addPlaceholderTerm("SenseVoice")
        let editedID = viewModel.entries[0].id

        XCTAssertFalse(viewModel.commitTermUpdate(id: editedID, term: " "))
        XCTAssertEqual(viewModel.errorMessage, PersonalDictionaryViewModel.ValidationError.empty.rawValue)
        XCTAssertEqual(viewModel.entries.map(\.term), ["Typoless", "SenseVoice"])

        XCTAssertFalse(viewModel.commitTermUpdate(id: editedID, term: "SenseVoice"))
        XCTAssertEqual(viewModel.errorMessage, PersonalDictionaryViewModel.ValidationError.duplicate.rawValue)
        XCTAssertEqual(viewModel.entries.first(where: { $0.id == editedID })?.term, "Typoless")
        XCTAssertEqual(viewModel.entries.map(\.term), ["Typoless", "SenseVoice"])
    }

    @MainActor
    func testDeleteEntryRemovesPersistedTerm() {
        let viewModel = makeViewModel()
        viewModel.addPlaceholderTerm("Typoless")
        let entry = viewModel.entries[0]

        XCTAssertEqual(viewModel.entries.count, 1)

        viewModel.deleteEntry(entry)
        XCTAssertTrue(viewModel.entries.isEmpty)

        let reloaded = PersonalDictionaryStore(directoryURL: tempDirectory)
        XCTAssertTrue(reloaded.entries.isEmpty)
    }

    @MainActor
    func testEmptyEditKeepsPlaceholderTerm() {
        let viewModel = makeViewModel()
        viewModel.addPlaceholderTerm("新词条")
        let id = viewModel.entries[0].id

        XCTAssertFalse(viewModel.commitTermUpdate(id: id, term: " "))

        XCTAssertEqual(viewModel.errorMessage, PersonalDictionaryViewModel.ValidationError.empty.rawValue)
        XCTAssertEqual(viewModel.entries.map(\.term), ["新词条"])

        let reloaded = PersonalDictionaryStore(directoryURL: tempDirectory)
        XCTAssertEqual(reloaded.entries.map(\.term), ["新词条"])
    }

    @MainActor
    func testImportEntriesUpdatesListAndStatusMessage() throws {
        let viewModel = makeViewModel()
        viewModel.addPlaceholderTerm("Typoless")

        let importURL = tempDirectory.appendingPathComponent("import.json")
        let importJSON = """
        [
          {
            "id": "duplicate-id",
            "term": "Typoless"
          },
          {
            "id": "new-id",
            "term": "FunASR"
          }
        ]
        """
        try importJSON.write(to: importURL, atomically: true, encoding: .utf8)

        viewModel.importEntries(from: importURL)

        XCTAssertEqual(viewModel.entries.map(\.term), ["Typoless", "FunASR"])
        XCTAssertEqual(viewModel.statusMessage, "已导入 1 个词条，跳过 1 个重复词条")
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testImportInvalidJSONShowsError() throws {
        let viewModel = makeViewModel()
        viewModel.addPlaceholderTerm("Typoless")

        let importURL = tempDirectory.appendingPathComponent("invalid.json")
        try "{ invalid".write(to: importURL, atomically: true, encoding: .utf8)

        viewModel.importEntries(from: importURL)

        XCTAssertEqual(viewModel.entries.map(\.term), ["Typoless"])
        XCTAssertEqual(viewModel.errorMessage, PersonalDictionaryViewModel.ValidationError.importFailed.rawValue)
        XCTAssertNil(viewModel.statusMessage)
    }

    @MainActor
    func testExportEntriesWritesFileAndStatusMessage() throws {
        let viewModel = makeViewModel()
        viewModel.addPlaceholderTerm("Typoless")

        let exportURL = tempDirectory.appendingPathComponent("export.json")
        viewModel.exportEntries(to: exportURL)

        let exportedEntries = try JSONDecoder().decode([DictionaryEntry].self, from: Data(contentsOf: exportURL))
        XCTAssertEqual(exportedEntries.map(\.term), ["Typoless"])
        XCTAssertEqual(viewModel.statusMessage, "已导出 1 个词条")
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testValidEditAfterEmptyEditPersistsAndClearsError() {
        let viewModel = makeViewModel()
        viewModel.addPlaceholderTerm("新词条")
        let id = viewModel.entries[0].id

        XCTAssertFalse(viewModel.commitTermUpdate(id: id, term: " "))
        XCTAssertEqual(viewModel.errorMessage, PersonalDictionaryViewModel.ValidationError.empty.rawValue)

        XCTAssertTrue(viewModel.commitTermUpdate(id: id, term: "Typoless"))
        XCTAssertEqual(viewModel.entries[0].term, "Typoless")
        XCTAssertNil(viewModel.errorMessage)

        let reloaded = PersonalDictionaryStore(directoryURL: tempDirectory)
        XCTAssertEqual(reloaded.entries.map(\.term), ["Typoless"])
    }

    @MainActor
    func testRepeatedCommitsKeepLatestTerm() {
        let viewModel = makeViewModel()
        viewModel.addPlaceholderTerm("旧词")
        let id = viewModel.entries[0].id

        XCTAssertTrue(viewModel.commitTermUpdate(id: id, term: "第一次"))
        XCTAssertTrue(viewModel.commitTermUpdate(id: id, term: "第二次"))

        XCTAssertEqual(viewModel.entries[0].term, "第二次")
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testExternalLearnedTermAppearsWithoutManualRefresh() throws {
        let store = PersonalDictionaryStore(directoryURL: tempDirectory)
        let viewModel = PersonalDictionaryViewModel(store: store)

        XCTAssertTrue(viewModel.entries.isEmpty)

        XCTAssertTrue(try store.addLearnedTermIfNeeded("朴邻"))

        XCTAssertEqual(viewModel.entries.map(\.term), ["朴邻"])
        XCTAssertEqual(viewModel.entries.first?.source, .autoLearned)
    }

    @MainActor
    private func makeViewModel() -> PersonalDictionaryViewModel {
        PersonalDictionaryViewModel(
            store: PersonalDictionaryStore(directoryURL: tempDirectory)
        )
    }
}
