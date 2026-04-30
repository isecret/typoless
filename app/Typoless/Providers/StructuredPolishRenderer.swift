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

        case .message:
            return renderMessage(response: response)
        }
    }

    // MARK: - Private

    /// list 模式：按条目换行，统一列表样式
    private static func renderList(response: LLMStructuredResponse) -> String {
        guard let items = response.items, !items.isEmpty else {
            return response.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let rendered = items
            .enumerated()
            .map { index, item in
                let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
                return "\(index + 1). \(trimmed)"
            }
            .joined(separator: "\n")

        return rendered
    }

    /// message 模式：称呼 + 正文 + 结尾，缺失部分不强补
    private static func renderMessage(response: LLMStructuredResponse) -> String {
        guard let body = response.body, !body.isEmpty else {
            return response.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var parts: [String] = []

        if let salutation = response.salutation?.trimmingCharacters(in: .whitespacesAndNewlines),
           !salutation.isEmpty {
            parts.append(salutation)
        }

        let bodyText = body
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        if !bodyText.isEmpty {
            parts.append(bodyText)
        }

        if let closing = response.closing?.trimmingCharacters(in: .whitespacesAndNewlines),
           !closing.isEmpty {
            parts.append(closing)
        }

        return parts.joined(separator: "\n")
    }
}
