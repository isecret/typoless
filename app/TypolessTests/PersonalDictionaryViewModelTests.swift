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
        viewModel.addPlaceholderTerm("SenseVoice")
        let editedID = viewModel.entries[0].id

        viewModel.scheduleTermUpdate(id: editedID, term: " ")
        await waitUntil { viewModel.entries.count == 1 }
        XCTAssertEqual(viewModel.entries.map(\.term), ["SenseVoice"])

        let remainingID = viewModel.entries[0].id
        viewModel.addPlaceholderTerm("Typoless")
        let reloadedEditedID = viewModel.entries[1].id

        viewModel.scheduleTermUpdate(id: reloadedEditedID, term: "SenseVoice")
        await waitUntil { viewModel.errorMessage == PersonalDictionaryViewModel.ValidationError.duplicate.rawValue }
        XCTAssertEqual(viewModel.entries.first(where: { $0.id == reloadedEditedID })?.term, "Typoless")
        XCTAssertEqual(viewModel.entries.first(where: { $0.id == remainingID })?.term, "SenseVoice")
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
