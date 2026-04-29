import Foundation

/// 个人词典存储，管理用户维护的专有名词、术语等词条
///
/// 存储位置：`~/.typoless/dictionary.json`（文件权限 0600）
/// 词条字段：`term`（必填）、`pronunciationHint`、`category`、`enabled`
/// 不存储历史输入文本或 ASR/LLM 响应正文
@MainActor
@Observable
final class PersonalDictionaryStore {

    private(set) var entries: [DictionaryEntry] = []

    /// 仅返回已启用的词条
    var enabledEntries: [DictionaryEntry] {
        entries.filter(\.enabled)
    }

    // MARK: - 存储路径

    private static let dictionaryURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".typoless", isDirectory: true)
            .appendingPathComponent("dictionary.json")
    }()

    private static let directoryURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".typoless", isDirectory: true)
    }()

    // MARK: - 初始化

    init() {
        loadEntries()
    }

    // MARK: - CRUD

    func addEntry(_ entry: DictionaryEntry) throws {
        entries.append(entry)
        try save()
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

    func toggleEnabled(id: String) throws {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].enabled.toggle()
        try save()
    }

    // MARK: - Hotwords 生成

    /// 为 sherpa-onnx 生成 hotwords 文件内容（每行一个词条）
    func generateHotwordsContent() -> String {
        enabledEntries
            .map(\.term)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    /// 将 hotwords 写入临时文件并返回路径
    func writeHotwordsFile() throws -> URL? {
        let content = generateHotwordsContent()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !content.isEmpty else {
            return nil
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("typoless-hotwords.txt")

        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// 为 LLM Prompt 提供术语参考列表
    func termsForPrompt() -> [String] {
        enabledEntries.map(\.term).filter { !$0.isEmpty }
    }

    // MARK: - 持久化

    private func loadEntries() {
        let url = Self.dictionaryURL

        guard FileManager.default.fileExists(atPath: url.path) else {
            entries = []
            return
        }

        do {
            let data = try Data(contentsOf: url)
            entries = try JSONDecoder().decode([DictionaryEntry].self, from: data)
        } catch {
            // 文件损坏时重置为空词典，不阻止应用启动
            entries = []
        }
    }

    private func save() throws {
        let fm = FileManager.default
        let dirURL = Self.directoryURL
        let fileURL = Self.dictionaryURL

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
}

// MARK: - Dictionary Entry Model

struct DictionaryEntry: Codable, Identifiable, Equatable, Sendable {
    var id: String = UUID().uuidString
    var term: String
    var pronunciationHint: String?
    var category: String?
    var enabled: Bool = true

    enum CodingKeys: String, CodingKey {
        case id, term, pronunciationHint, category, enabled
    }

    init(
        id: String = UUID().uuidString,
        term: String,
        pronunciationHint: String? = nil,
        category: String? = nil,
        enabled: Bool = true
    ) {
        self.id = id
        self.term = term
        self.pronunciationHint = pronunciationHint
        self.category = category
        self.enabled = enabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        term = try container.decode(String.self, forKey: .term)
        pronunciationHint = try container.decodeIfPresent(String.self, forKey: .pronunciationHint)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }
}
