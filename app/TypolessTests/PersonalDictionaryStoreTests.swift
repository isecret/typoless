import XCTest
@testable import Typoless

final class PersonalDictionaryStoreTests: XCTestCase {
    private var tempDirectory: URL!
    private var dictionaryFileURL: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        dictionaryFileURL = tempDirectory.appendingPathComponent("dictionary.json")
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    @MainActor
    func testAddEntryPersistsAtTopWithNilOptionalFields() throws {
        let store = PersonalDictionaryStore(directoryURL: tempDirectory)

        try store.addEntry(DictionaryEntry(term: "Typoless"))
        try store.addEntry(DictionaryEntry(term: "FunASR"))

        XCTAssertEqual(store.entries.map(\.term), ["FunASR", "Typoless"])
        XCTAssertNil(store.entries[0].pronunciationHint)
        XCTAssertNil(store.entries[0].category)

        let reloaded = PersonalDictionaryStore(directoryURL: tempDirectory)
        XCTAssertEqual(reloaded.entries.map(\.term), ["FunASR", "Typoless"])
        XCTAssertNil(reloaded.entries[0].pronunciationHint)
        XCTAssertNil(reloaded.entries[0].category)
    }

    @MainActor
    func testUpdateAndDeletePersistAfterReload() throws {
        let store = PersonalDictionaryStore(directoryURL: tempDirectory)
        let entry = DictionaryEntry(term: "旧词")
        try store.addEntry(entry)

        var updated = entry
        updated.term = "新词"
        try store.updateEntry(updated)

        var reloaded = PersonalDictionaryStore(directoryURL: tempDirectory)
        XCTAssertEqual(reloaded.entries, [DictionaryEntry(id: entry.id, term: "新词")])

        try reloaded.removeEntry(id: entry.id)
        reloaded = PersonalDictionaryStore(directoryURL: tempDirectory)
        XCTAssertTrue(reloaded.entries.isEmpty)
    }

    @MainActor
    func testAllEntriesParticipateInHotwordsAndPromptTerms() throws {
        let store = PersonalDictionaryStore(directoryURL: tempDirectory)
        try store.addEntry(DictionaryEntry(term: "张三", pronunciationHint: "zhang san"))
        try store.addEntry(DictionaryEntry(term: "李四"))
        try store.addEntry(DictionaryEntry(term: "王五", pronunciationHint: nil))

        XCTAssertEqual(store.hotwordsForFunASR(), "王五 李四 zhang san")
        XCTAssertEqual(
            store.termsForPrompt(),
            [
                TermReference(term: "王五", pronunciationHint: nil),
                TermReference(term: "李四", pronunciationHint: nil),
                TermReference(term: "张三", pronunciationHint: "zhang san")
            ]
        )
    }

    @MainActor
    func testEmptyTermsAreExcludedFromHotwordsAndPromptTerms() throws {
        let store = PersonalDictionaryStore(directoryURL: tempDirectory)
        try store.addEntry(DictionaryEntry(term: ""))
        try store.addEntry(DictionaryEntry(term: "Typoless"))

        XCTAssertEqual(store.hotwordsForFunASR(), "Typoless")
        XCTAssertEqual(store.termsForPrompt(), [TermReference(term: "Typoless", pronunciationHint: nil)])
    }

    @MainActor
    func testLegacyDisabledEntriesAreDroppedDuringMigration() throws {
        let legacyJSON = """
        [
          {
            "id": "enabled-entry",
            "term": "Typoless",
            "enabled": true
          },
          {
            "id": "disabled-entry",
            "term": "Obsolete",
            "enabled": false
          }
        ]
        """

        let data = try XCTUnwrap(legacyJSON.data(using: .utf8))
        try data.write(to: dictionaryFileURL, options: .atomic)

        let store = PersonalDictionaryStore(directoryURL: tempDirectory)
        XCTAssertEqual(store.entries, [DictionaryEntry(id: "enabled-entry", term: "Typoless")])

        let persistedData = try Data(contentsOf: dictionaryFileURL)
        let persistedJSON = try XCTUnwrap(String(data: persistedData, encoding: .utf8))
        XCTAssertFalse(persistedJSON.contains("\"enabled\""))
        XCTAssertFalse(persistedJSON.contains("Obsolete"))
    }
}
