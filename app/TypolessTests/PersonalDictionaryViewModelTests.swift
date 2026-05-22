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
    func testAddRejectsEmptyTerm() {
        let viewModel = makeViewModel()

        viewModel.newTerm = "   "
        viewModel.addTerm()

        XCTAssertEqual(viewModel.errorMessage, PersonalDictionaryViewModel.ValidationError.empty.rawValue)
        XCTAssertTrue(viewModel.entries.isEmpty)
    }

    @MainActor
    func testAddRejectsDuplicateTerm() {
        let viewModel = makeViewModel()

        viewModel.newTerm = "Typoless"
        viewModel.addTerm()
        viewModel.newTerm = " Typoless "
        viewModel.addTerm()

        XCTAssertEqual(viewModel.errorMessage, PersonalDictionaryViewModel.ValidationError.duplicate.rawValue)
        XCTAssertEqual(viewModel.entries.map(\.term), ["Typoless"])
    }

    @MainActor
    func testAddCreatesEnabledTermWithNilOptionalFields() {
        let viewModel = makeViewModel()

        viewModel.newTerm = " Typoless "
        viewModel.addTerm()

        XCTAssertEqual(viewModel.entries.count, 1)
        XCTAssertEqual(viewModel.entries[0].term, "Typoless")
        XCTAssertTrue(viewModel.entries[0].enabled)
        XCTAssertNil(viewModel.entries[0].pronunciationHint)
        XCTAssertNil(viewModel.entries[0].category)
        XCTAssertEqual(viewModel.newTerm, "")
    }

    @MainActor
    func testDebouncedEditCommitsAfterDelay() async {
        let viewModel = makeViewModel(debounceDuration: .milliseconds(20))
        viewModel.newTerm = "旧词"
        viewModel.addTerm()
        let id = viewModel.entries[0].id

        viewModel.scheduleTermUpdate(id: id, term: " 新词 ")

        await waitUntil { viewModel.entries[0].term == "新词" }
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testEditRejectsEmptyAndDuplicateTerms() async {
        let viewModel = makeViewModel(debounceDuration: .milliseconds(20))
        viewModel.newTerm = "Typoless"
        viewModel.addTerm()
        viewModel.newTerm = "FunASR"
        viewModel.addTerm()
        let editedID = viewModel.entries[0].id

        viewModel.scheduleTermUpdate(id: editedID, term: " ")
        await waitUntil { viewModel.errorMessage == PersonalDictionaryViewModel.ValidationError.empty.rawValue }
        XCTAssertEqual(viewModel.entries[0].term, "FunASR")

        viewModel.scheduleTermUpdate(id: editedID, term: "Typoless")
        await waitUntil { viewModel.errorMessage == PersonalDictionaryViewModel.ValidationError.duplicate.rawValue }
        XCTAssertEqual(viewModel.entries[0].term, "FunASR")
    }

    @MainActor
    func testDeleteEntryRemovesPersistedTerm() {
        let viewModel = makeViewModel()
        viewModel.newTerm = "Typoless"
        viewModel.addTerm()
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
        viewModel.newTerm = "旧词"
        viewModel.addTerm()
        let id = viewModel.entries[0].id

        viewModel.scheduleTermUpdate(id: id, term: "新词")
        viewModel.flushPendingEdits()

        XCTAssertEqual(viewModel.entries[0].term, "新词")
    }

    @MainActor
    func testToggleEnabledSavesImmediately() {
        let store = PersonalDictionaryStore(directoryURL: tempDirectory)
        let viewModel = PersonalDictionaryViewModel(store: store)
        viewModel.newTerm = "Typoless"
        viewModel.addTerm()
        let id = viewModel.entries[0].id

        viewModel.toggleEnabled(id: id)

        XCTAssertFalse(viewModel.entries[0].enabled)
        let reloaded = PersonalDictionaryStore(directoryURL: tempDirectory)
        XCTAssertFalse(reloaded.entries[0].enabled)
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
