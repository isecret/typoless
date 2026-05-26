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
    func testDebouncedEditCommitsAfterDelay() async {
        let viewModel = makeViewModel(debounceDuration: .milliseconds(20))
        viewModel.addPlaceholderTerm("旧词")
        let id = viewModel.entries[0].id

        viewModel.scheduleTermUpdate(id: id, term: " 新词 ")

        await waitUntil { viewModel.entries[0].term == "新词" }
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testEditRejectsEmptyAndDuplicateTerms() async {
        let viewModel = makeViewModel(debounceDuration: .milliseconds(20))
        viewModel.addPlaceholderTerm("Typoless")
        viewModel.addPlaceholderTerm("FunASR")
        let editedID = viewModel.entries[0].id

        viewModel.scheduleTermUpdate(id: editedID, term: " ")
        await waitUntil { viewModel.entries.count == 1 }
        XCTAssertEqual(viewModel.entries.map(\.term), ["FunASR"])

        let remainingID = viewModel.entries[0].id
        viewModel.addPlaceholderTerm("Typoless")
        let reloadedEditedID = viewModel.entries[1].id

        viewModel.scheduleTermUpdate(id: reloadedEditedID, term: "FunASR")
        await waitUntil { viewModel.errorMessage == PersonalDictionaryViewModel.ValidationError.duplicate.rawValue }
        XCTAssertEqual(viewModel.entries.first(where: { $0.id == reloadedEditedID })?.term, "Typoless")
        XCTAssertEqual(viewModel.entries.first(where: { $0.id == remainingID })?.term, "FunASR")
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
    func testFlushPendingEditsCommitsImmediately() {
        let viewModel = makeViewModel(debounceDuration: .seconds(10))
        viewModel.addPlaceholderTerm("旧词")
        let id = viewModel.entries[0].id

        viewModel.scheduleTermUpdate(id: id, term: "新词")
        viewModel.flushPendingEdits()

        XCTAssertEqual(viewModel.entries[0].term, "新词")
    }

    @MainActor
    func testEmptyEditDeletesPlaceholderTerm() async {
        let viewModel = makeViewModel(debounceDuration: .milliseconds(20))
        viewModel.addPlaceholderTerm("新词条")
        let id = viewModel.entries[0].id

        viewModel.scheduleTermUpdate(id: id, term: " ")

        await waitUntil { viewModel.entries.isEmpty }
        let reloaded = PersonalDictionaryStore(directoryURL: tempDirectory)
        XCTAssertTrue(reloaded.entries.isEmpty)
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
    private func makeViewModel(debounceDuration: Duration = .milliseconds(500)) -> PersonalDictionaryViewModel {
        PersonalDictionaryViewModel(
            store: PersonalDictionaryStore(directoryURL: tempDirectory),
            debounceDuration: debounceDuration
        )
    }

    @MainActor
    private func waitUntil(
        timeout: Duration = .seconds(1),
        condition: @escaping @MainActor () -> Bool
    ) async {
        let start = ContinuousClock.now
        while ContinuousClock.now - start < timeout {
            if condition() {
                return
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for condition")
    }
}
