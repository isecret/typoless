import Foundation

/// 最近记录持久化存储，最多保留 10 条
@MainActor
@Observable
final class RecentRecordStore {
    private(set) var records: [RecentRecord] = []

    private let maxCount = 10
    private let defaultsKey = "typoless.recent_records"

    init() {
        load()
    }

    func add(_ record: RecentRecord) {
        records.insert(record, at: 0)
        if records.count > maxCount {
            records = Array(records.prefix(maxCount))
        }
        save()
    }

    func clearAll() {
        records.removeAll()
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return }
        do {
            records = try JSONDecoder().decode([RecentRecord].self, from: data)
        } catch {
            records = []
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(records)
            UserDefaults.standard.set(data, forKey: defaultsKey)
        } catch {
            // 编码失败时静默忽略，不影响主链路
        }
    }
}
