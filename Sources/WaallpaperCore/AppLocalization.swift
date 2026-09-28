import Foundation

public enum AppLanguage: String, Codable, CaseIterable, Sendable {
    case system
    case korean
    case english

    /// Match the first supported language in the user's ordered preferences.
    /// English is the fallback for a system with neither Korean nor English selected.
    public func resolvedCode(preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        switch self {
        case .korean: return "ko"
        case .english: return "en"
        case .system:
            for identifier in preferredLanguages {
                let code = identifier.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first
                if code == "ko" { return "ko" }
                if code == "en" { return "en" }
            }
            return "en"
        }
    }
}

/// Every lookup receives a language, so rendering tasks do not share mutable locale state.
public enum AppLocalization {
    public static func text(_ key: String, language: AppLanguage = .system, arguments: [CVarArg] = []) -> String {
        let code = language.resolvedCode()
        let format = bundle(for: code).localizedString(forKey: key, value: key, table: nil)
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: Locale(identifier: code), arguments: arguments)
    }

    public static func description(for error: Error, language: AppLanguage) -> String {
        (error as? AppLocalizableError)?.localizedDescription(language: language) ?? error.localizedDescription
    }

    static func bundle(for code: String) -> Bundle {
        guard let url = resourceBundle.url(forResource: code, withExtension: "lproj"),
              let bundle = Bundle(url: url) else { return resourceBundle }
        return bundle
    }

    // Used to verify language completeness and packaged native resources.
    static var resourceBundleURL: URL { resourceBundle.bundleURL }

    private static var resourceBundle: Bundle {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("Waallpaper_WaallpaperCore.bundle"),
           let bundle = Bundle(url: url) { return bundle }
        return Bundle.module
    }
}

public protocol AppLocalizableError: LocalizedError {
    func localizedDescription(language: AppLanguage) -> String
}

public extension AppLocalizableError {
    var errorDescription: String? { localizedDescription(language: .system) }
}
