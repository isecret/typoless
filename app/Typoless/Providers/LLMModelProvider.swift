import Foundation

struct LLMModelProvider: Sendable {
    typealias DataLoader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private static let timeout: TimeInterval = 10

    let baseURL: String
    let apiKey: String
    let dataLoader: DataLoader

    init(
        baseURL: String,
        apiKey: String,
        dataLoader: @escaping DataLoader = LLMModelProvider.defaultDataLoader
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.dataLoader = dataLoader
    }

    func fetchModels() async throws -> [String] {
        let url = try buildURL()

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = Self.timeout

        do {
            let (responseData, response) = try await dataLoader(request)

            if let httpResponse = response as? HTTPURLResponse {
                switch httpResponse.statusCode {
                case 200:
                    return try parseResponse(responseData)
                case 401, 403:
                    throw TypolessError.invalidLLMConfiguration(detail: "认证失败，请检查 API Key")
                case 404, 405:
                    throw TypolessError.invalidLLMConfiguration(detail: "当前服务不支持模型列表，可手动输入 Model")
                default:
                    let body = String(data: responseData, encoding: .utf8) ?? ""
                    throw TypolessError.llmNetworkFailure(message: "HTTP \(httpResponse.statusCode): \(body)")
                }
            }

            return try parseResponse(responseData)
        } catch let error as TypolessError {
            throw error
        } catch let error as URLError {
            throw TypolessError.llmNetworkFailure(message: error.localizedDescription)
        } catch {
            throw TypolessError.llmNetworkFailure(message: error.localizedDescription)
        }
    }

    private func buildURL() throws -> URL {
        let trimmed = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(trimmed)/models") else {
            throw TypolessError.invalidLLMConfiguration(detail: "Base URL 格式无效")
        }
        return url
    }

    private static let defaultDataLoader: DataLoader = { request in
        try await URLSession.shared.data(for: request)
    }

    private func parseResponse(_ data: Data) throws -> [String] {
        let response: ModelListResponse
        do {
            response = try JSONDecoder().decode(ModelListResponse.self, from: data)
        } catch {
            throw TypolessError.llmNetworkFailure(message: "模型列表响应格式异常")
        }

        let models = response.data
            .map(\.id)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .uniqued()
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }

        guard !models.isEmpty else {
            throw TypolessError.llmNetworkFailure(message: "模型列表为空")
        }

        return models
    }
}

private struct ModelListResponse: Decodable {
    let data: [ModelItem]
}

private struct ModelItem: Decodable {
    let id: String
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
