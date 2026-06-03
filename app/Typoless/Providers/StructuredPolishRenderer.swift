import Foundation

/// 将结构化结果渲染为最终可注入的文本
enum StructuredPolishRenderer {

    /// 根据 mode 和结构化字段，渲染最终文本
    /// - Parameters:
    ///   - response: LLM 返回的结构化响应
    /// - Returns: 渲染后的最终文本
    static func render(response: LLMStructuredResponse) -> String {
        switch response.mode {
        case .plainText:
            return response.text.trimmingCharacters(in: .whitespacesAndNewlines)

        case .list:
            return renderList(response: response)
        }
    }

    // MARK: - Private

    /// list 模式：按条目换行，统一列表样式
    private static func renderList(response: LLMStructuredResponse) -> String {
        guard let items = response.items, !items.isEmpty else {
            return response.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let renderedItems = items
            .enumerated()
            .map { index, item in
                let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
                return "\(index + 1). \(trimmed)"
            }
            .joined(separator: "\n")

        if let intro = normalizedListIntro(from: response.intro) {
            var parts = [intro, renderedItems]
            if let outro = normalizedListOutro(from: response.outro) {
                parts.append(outro)
            }
            return parts.joined(separator: "\n")
        }

        if let outro = normalizedListOutro(from: response.outro) {
            return "\(renderedItems)\n\(outro)"
        }

        return renderedItems
    }

    private static func normalizedListIntro(from intro: String?) -> String? {
        guard let intro else { return nil }

        let trimmed = intro.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let terminalPunctuation = CharacterSet(charactersIn: "：:。！？!?；;")
        if let scalar = trimmed.unicodeScalars.last,
           terminalPunctuation.contains(scalar) {
            return trimmed
        }

        return trimmed + "："
    }

    private static func normalizedListOutro(from outro: String?) -> String? {
        guard let outro else { return nil }

        let trimmed = outro.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        return trimmed
    }
}
