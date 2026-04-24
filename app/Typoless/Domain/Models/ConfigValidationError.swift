import Foundation

enum ConfigValidationError: LocalizedError, Equatable {
    case emptyField(String)
    case invalidURL(String)

    var errorDescription: String? {
        switch self {
        case .emptyField(let field):
            "\(field) 不能为空"
        case .invalidURL(let value):
            "URL 格式无效：\(value)"
        }
    }
}
