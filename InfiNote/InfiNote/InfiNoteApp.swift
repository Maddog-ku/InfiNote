//
//  InfiNoteApp.swift
//  InfiNote
//

import SwiftUI

@main
struct InfiNoteApp: App {
    @StateObject private var settings = AppSettingsStore()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(settings)
                .environment(\.locale, settings.locale ?? .autoupdatingCurrent)
        }
    }
}
