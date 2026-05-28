import Foundation

/// 个人词典存储，管理用户维护的专有名词、术语等词条
///
/// 存储位置：`~/.typoless/dictionary.json`（文件权限 0600）
/// 词条字段：`term`（必填）、`pronunciationHint`、`category`
/// 不存储历史输入文本或 ASR/LLM 响应正文
@MainActor
@Observable
final class PersonalDictionaryStore {

    private(set) var entries: [DictionaryEntry] = []
    private let directoryURL: URL
    private let dictionaryURL: URL

    // MARK: - 存储路径

    private static let defaultDirectoryURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".typoless", isDirectory: true)
    }()

    // MARK: - 初始化

    init(directoryURL: URL? = nil) {
        self.directoryURL = directoryURL ?? Self.defaultDirectoryURL
        self.dictionaryURL = self.directoryURL.appendingPathComponent("dictionary.json")
        loadEntries()
    }

    // MARK: - CRUD

    func addEntry(_ entry: DictionaryEntry) throws {
        entries.append(entry)
        try save()
    }

    @discardableResult
    func addLearnedTermIfNeeded(_ term: String) throws -> Bool {
        let normalized = normalizedTerm(term)
        guard !normalized.isEmpty else { return false }

        let alreadyExists = entries.contains { normalizedTerm($0.term) == normalized }
        guard !alreadyExists else { return false }

        entries.append(DictionaryEntry(term: normalized, source: .autoLearned))
        try save()
        return true
    }

    func removeEntry(id: String) throws {
        entries.removeAll { $0.id == id }
        try save()
    }

    func updateEntry(_ entry: DictionaryEntry) throws {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index] = entry
        try save()
    }

    // MARK: - Hotwords 生成

    /// 为本地 ASR 生成 hotwords 参数字符串（空格分隔）
    ///
    /// 优先使用 `pronunciationHint`（帮助 ASR 识别发音），若缺失则退回 `term`。
    func hotwordsForLocalASR() -> String {
        entries
            .compactMap { entry -> String? in
                let hint = entry.pronunciationHint?.trimmingCharacters(in: .whitespaces)
                if let hint, !hint.isEmpty {
                    return hint
                }
                return entry.term.isEmpty ? nil : entry.term
            }
            .joined(separator: " ")
    }

    /// 为 LLM Prompt 提供结构化术语参考（包含 term 和 pronunciationHint）
    func termsForPrompt() -> [TermReference] {
        entries
            .filter { !$0.term.isEmpty }
            .map { TermReference(term: $0.term, pronunciationHint: $0.pronunciationHint) }
    }

    // MARK: - 持久化

    private func loadEntries() {
        let url = dictionaryURL

        guard FileManager.default.fileExists(atPath: url.path) else {
            entries = []
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let decodedEntries = try JSONDecoder().decode([StoredDictionaryEntry].self, from: data)
            let migratedEntries = decodedEntries
                .filter { $0.enabled != false }
                .map(\.dictionaryEntry)
            let shouldRewriteFile = decodedEntries.contains { $0.enabled != nil }
            entries = migratedEntries

            if shouldRewriteFile {
                try? save()
            }
        } catch {
            // 文件损坏时重置为空词典，不阻止应用启动
            entries = []
        }
    }

    private func save() throws {
        let fm = FileManager.default
        let dirURL = directoryURL
        let fileURL = dictionaryURL

        if !fm.fileExists(atPath: dirURL.path) {
            try fm.createDirectory(at: dirURL, withIntermediateDirectories: true)
        }
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dirURL.path)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(entries)

        try data.write(to: fileURL, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private func normalizedTerm(_ term: String) -> String {
        term.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Dictionary Entry Model

enum DictionaryEntrySource: String, Codable, Equatable, Sendable {
    case manual
    case autoLearned = "auto_learned"
}

struct DictionaryEntry: Codable, Identifiable, Equatable, Sendable {
    var id: String = UUID().uuidString
    var term: String
    var pronunciationHint: String?
    var category: String?
    var source: DictionaryEntrySource

    enum CodingKeys: String, CodingKey {
        case id, term, pronunciationHint, category, source
    }

    init(
        id: String = UUID().uuidString,
        term: String,
        pronunciationHint: String? = nil,
        category: String? = nil,
        source: DictionaryEntrySource = .manual
    ) {
        self.id = id
        self.term = term
        self.pronunciationHint = pronunciationHint
        self.category = category
        self.source = source
    }
}

private struct StoredDictionaryEntry: Decodable {
    let id: String
    let term: String
    let pronunciationHint: String?
    let category: String?
    let enabled: Bool?
    let source: DictionaryEntrySource?

    var dictionaryEntry: DictionaryEntry {
        DictionaryEntry(
            id: id,
            term: term,
            pronunciationHint: pronunciationHint,
            category: category,
            source: source ?? .manual
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        term = try container.decode(String.self, forKey: .term)
        pronunciationHint = try container.decodeIfPresent(String.self, forKey: .pronunciationHint)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled)
        source = try container.decodeIfPresent(DictionaryEntrySource.self, forKey: .source)
    }

    private enum CodingKeys: String, CodingKey {
        case id, term, pronunciationHint, category, enabled, source
    }
}

// MARK: - Term Reference for LLM

/// 传递给 LLM 的术语参考，包含目标写法和发音提示
struct TermReference: Sendable, Equatable {
    let term: String
    let pronunciationHint: String?
}
