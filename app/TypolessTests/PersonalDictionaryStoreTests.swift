import XCTest
@testable import Typoless

final class PersonalDictionaryStoreTests: XCTestCase {
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
    func testAddEntryPersistsAtTopWithDefaultEnabledAndNilOptionalFields() throws {
        let store = PersonalDictionaryStore(directoryURL: tempDirectory)

        try store.addEntry(DictionaryEntry(term: "Typoless"))
        try store.addEntry(DictionaryEntry(term: "FunASR"))

        XCTAssertEqual(store.entries.map(\.term), ["FunASR", "Typoless"])
        XCTAssertTrue(store.entries[0].enabled)
        XCTAssertNil(store.entries[0].pronunciationHint)
        XCTAssertNil(store.entries[0].category)

        let reloaded = PersonalDictionaryStore(directoryURL: tempDirectory)
        XCTAssertEqual(reloaded.entries.map(\.term), ["FunASR", "Typoless"])
        XCTAssertTrue(reloaded.entries[0].enabled)
        XCTAssertNil(reloaded.entries[0].pronunciationHint)
        XCTAssertNil(reloaded.entries[0].category)
    }

    @MainActor
    func testUpdateDeleteAndTogglePersistAfterReload() throws {
        let store = PersonalDictionaryStore(directoryURL: tempDirectory)
        let entry = DictionaryEntry(term: "旧词")
        try store.addEntry(entry)

        var updated = entry
        updated.term = "新词"
        try store.updateEntry(updated)
        try store.toggleEnabled(id: entry.id)

        var reloaded = PersonalDictionaryStore(directoryURL: tempDirectory)
        XCTAssertEqual(reloaded.entries, [DictionaryEntry(id: entry.id, term: "新词", enabled: false)])

        try reloaded.removeEntry(id: entry.id)
        reloaded = PersonalDictionaryStore(directoryURL: tempDirectory)
        XCTAssertTrue(reloaded.entries.isEmpty)
    }

    @MainActor
    func testDisabledEntriesAreExcludedFromHotwordsAndPromptTerms() throws {
        let store = PersonalDictionaryStore(directoryURL: tempDirectory)
        try store.addEntry(DictionaryEntry(term: "张三", pronunciationHint: "zhang san", enabled: true))
        try store.addEntry(DictionaryEntry(term: "李四", enabled: false))
        try store.addEntry(DictionaryEntry(term: "王五", pronunciationHint: nil, enabled: true))

        XCTAssertEqual(store.hotwordsForFunASR(), "王五 zhang san")
        XCTAssertEqual(
            store.termsForPrompt(),
            [
                TermReference(term: "王五", pronunciationHint: nil),
                TermReference(term: "张三", pronunciationHint: "zhang san")
            ]
        )
    }

    @MainActor
    func testEmptyTermsAreExcludedFromHotwordsAndPromptTerms() throws {
        let store = PersonalDictionaryStore(directoryURL: tempDirectory)
        try store.addEntry(DictionaryEntry(term: "", enabled: true))
        try store.addEntry(DictionaryEntry(term: "Typoless", enabled: true))

        XCTAssertEqual(store.hotwordsForFunASR(), "Typoless")
        XCTAssertEqual(store.termsForPrompt(), [TermReference(term: "Typoless", pronunciationHint: nil)])
    }
}
