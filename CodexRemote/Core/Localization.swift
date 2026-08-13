import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var id: String { rawValue }

    var nativeName: String {
        switch self {
        case .system: "System Default / 跟随系统"
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        }
    }

    var locale: Locale {
        switch self {
        case .system: .autoupdatingCurrent
        case .english: Locale(identifier: "en")
        case .simplifiedChinese: Locale(identifier: "zh-Hans")
        }
    }
}

func localizedString(_ key: String, locale: Locale) -> String {
    let languageCode = locale.language.languageCode?.identifier ?? "en"
    let resource = languageCode == "zh" ? "zh-Hans" : "en"
    guard
        let path = Bundle.main.path(forResource: resource, ofType: "lproj"),
        let bundle = Bundle(path: path)
    else {
        return key
    }
    return bundle.localizedString(forKey: key, value: key, table: nil)
}
