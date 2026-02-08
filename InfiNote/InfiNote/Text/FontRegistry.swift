//
//  FontRegistry.swift
//  InfiNote
//

import Foundation
import CoreText
import UIKit

struct ImportedFont: Hashable {
    var fileURL: URL
    var postScriptNames: [String]
}

enum FontRegistryError: Error {
    case appSupportUnavailable
    case importFailed(URL)
}

final class FontRegistry {
    static let shared = FontRegistry()

    private let fileManager = FileManager.default
    private let folderName = "Fonts"

    private init() {}

    @discardableResult
    func registerPersistedFonts() throws -> [ImportedFont] {
        let folder = try fontsDirectory()
        guard let urls = try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else {
            return []
        }
        return try importFontFiles(urls: urls, persist: false)
    }

    @discardableResult
    func importFontFiles(urls: [URL], persist: Bool = true) throws -> [ImportedFont] {
        var results: [ImportedFont] = []
        let destinationFolder = try fontsDirectory()

        for sourceURL in urls {
            let scoped = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if scoped {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            let ext = sourceURL.pathExtension.lowercased()
            guard ext == "ttf" || ext == "otf" else { continue }

            let targetURL: URL
            if persist {
                targetURL = destinationFolder.appendingPathComponent(sourceURL.lastPathComponent)
                if fileManager.fileExists(atPath: targetURL.path) {
                    try? fileManager.removeItem(at: targetURL)
                }
                do {
                    try fileManager.copyItem(at: sourceURL, to: targetURL)
                } catch {
                    throw FontRegistryError.importFailed(sourceURL)
                }
            } else {
                targetURL = sourceURL
            }

            var registerError: Unmanaged<CFError>?
            CTFontManagerRegisterFontsForURL(targetURL as CFURL, .process, &registerError)
            let names = postScriptNames(from: targetURL)
            results.append(ImportedFont(fileURL: targetURL, postScriptNames: names))
        }

        return results
    }

    func allPostScriptNames() -> [String] {
        UIFont.familyNames
            .flatMap { UIFont.fontNames(forFamilyName: $0) }
            .sorted()
    }

    func uiFont(postScriptName: String, size: CGFloat) -> UIFont? {
        UIFont(name: postScriptName, size: size)
    }

    private func postScriptNames(from url: URL) -> [String] {
        guard let provider = CGDataProvider(url: url as CFURL),
              let cgFont = CGFont(provider) else {
            return []
        }
        if let name = cgFont.postScriptName as String? {
            return [name]
        }
        return []
    }

    private func fontsDirectory() throws -> URL {
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw FontRegistryError.appSupportUnavailable
        }
        let folder = appSupport.appendingPathComponent(folderName, isDirectory: true)
        if !fileManager.fileExists(atPath: folder.path) {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder
    }
}
