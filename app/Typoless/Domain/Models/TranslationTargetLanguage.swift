import Foundation

enum TranslationTargetLanguage: String, Codable, Equatable, Sendable, CaseIterable {
    case english
    case japanese
    case korean
    case french
    case german
    case spanish
    case traditionalChinese
    case simplifiedChinese

    var displayName: String {
        switch self {
        case .english: return "English"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        case .french: return "Français"
        case .german: return "Deutsch"
        case .spanish: return "Español"
        case .traditionalChinese: return "繁體中文"
        case .simplifiedChinese: return "简体中文"
        }
    }
}
