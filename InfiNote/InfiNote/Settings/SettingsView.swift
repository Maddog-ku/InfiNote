//
//  SettingsView.swift
//  InfiNote
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettingsStore

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("settings.language.title", selection: $settings.language) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.titleKey).tag(language)
                        }
                    }
                    .pickerStyle(.inline)
                } header: {
                    Text("settings.section.language")
                } footer: {
                    Text("settings.language.footer")
                }
            }
            .navigationTitle("settings.title")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("settings.done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

