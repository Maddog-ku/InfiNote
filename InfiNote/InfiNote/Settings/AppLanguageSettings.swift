//
//  AppLanguageSettings.swift
//  InfiNote
//

import Foundation
import Combine
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case traditionalChinese = "zh-Hant"

    var id: String { rawValue }

    var locale: Locale? {
        switch self {
        case .system:
            return nil
        case .english:
            return Locale(identifier: "en")
        case .traditionalChinese:
            return Locale(identifier: "zh-Hant")
        }
    }

    var titleKey: LocalizedStringKey {
        switch self {
        case .system:
            return "settings.language.system"
        case .english:
            return "settings.language.english"
        case .traditionalChinese:
            return "settings.language.traditional_chinese"
        }
    }
}

@MainActor
final class AppSettingsStore: ObservableObject {
    @Published var language: AppLanguage {
        didSet {
            userDefaults.set(language.rawValue, forKey: Self.languageKey)
        }
    }

    var locale: Locale? {
        language.locale
    }

    private let userDefaults: UserDefaults
    private static let languageKey = "app.settings.language"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let saved = userDefaults.string(forKey: Self.languageKey)
        self.language = AppLanguage(rawValue: saved ?? "") ?? .system
    }
}

