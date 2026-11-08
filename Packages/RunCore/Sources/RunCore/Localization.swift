import Foundation

/// The two supported presentation languages. Persisted identifiers never use translated text.
public enum AppLanguage: String, Codable, Sendable, CaseIterable {
  case english = "en"
  case german = "de"

  public static var current: AppLanguage {
    let preferred = Bundle.main.preferredLocalizations.first ?? Locale.preferredLanguages.first ?? "en"
    return preferred.hasPrefix("de") ? .german : .english
  }

  public var locale: Locale { Locale(identifier: rawValue) }
}

public extension String {
  /// Resolves a stable key such as `HistoryScreen.EmptyState.title.text`.
  var localized: String { localized(language: .current) }

  func localized(language: AppLanguage) -> String {
    let bundle = Bundle.module.path(forResource: language.rawValue, ofType: "lproj")
      .flatMap(Bundle.init(path:)) ?? Bundle.module
    let value = bundle.localizedString(forKey: self, value: nil, table: "Localizable")
    guard value == self, language != .english,
      let path = Bundle.module.path(forResource: "en", ofType: "lproj"),
      let english = Bundle(path: path) else { return value }
    return english.localizedString(forKey: self, value: nil, table: "Localizable")
  }

  /// Positional placeholders allow translations to reorder arguments; catalog plurals are supported.
  func localized(_ arguments: CVarArg...) -> String {
    String(format: localized, locale: Locale.current, arguments: arguments)
  }
}
