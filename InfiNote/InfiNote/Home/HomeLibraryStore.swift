//
//  HomeLibraryStore.swift
//  InfiNote
//

import Foundation
import Combine

@MainActor
final class HomeLibraryStore: ObservableObject {
    @Published private(set) var folders: [NoteFolder] = []
    @Published private(set) var notebooks: [NotebookRecord] = []
    @Published var currentFolderID: UUID?

    private let fileManager = FileManager.default
    private let pdfImportService = PDFImportService()

    init() {
        do {
            try load()
        } catch {
            folders = []
            notebooks = []
        }
    }

    var currentPathFolders: [NoteFolder] {
        var path: [NoteFolder] = []
        var cursor = currentFolderID
        while let id = cursor, let folder = folder(with: id) {
            path.append(folder)
            cursor = folder.parentFolderID
        }
        return path.reversed()
    }

    func enterFolder(_ id: UUID?) {
        currentFolderID = id
    }

    func createFolder(name: String, parentFolderID: UUID?) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let parentFolderID, folder(with: parentFolderID) == nil {
            throw HomeLibraryError.folderNotFound(parentFolderID)
        }
        let now = Self.nowMillis()
        folders.append(
            NoteFolder(
                id: UUID(),
                name: trimmed,
                parentFolderID: parentFolderID,
                createdAtMillis: now,
                updatedAtMillis: now
            )
        )
        folders.sort { $0.updatedAtMillis > $1.updatedAtMillis }
        try save()
    }

    func createNotebook(
        title: String,
        template: NotebookTemplate,
        orientation: NotebookOrientation,
        parentFolderID: UUID?,
        pageCount: Int = 1
    ) throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let parentFolderID, folder(with: parentFolderID) == nil {
            throw HomeLibraryError.folderNotFound(parentFolderID)
        }
        let now = Self.nowMillis()
        notebooks.append(
            NotebookRecord(
                id: UUID(),
                title: trimmed,
                folderID: parentFolderID,
                template: template,
                orientation: orientation,
                pageCount: max(1, pageCount),
                sourcePDFFileName: nil,
                thumbnailRevision: 1,
                createdAtMillis: now,
                updatedAtMillis: now,
                lastEditedAtMillis: now
            )
        )
        notebooks.sort { $0.lastEditedAtMillis > $1.lastEditedAtMillis }
        try save()
    }

    func importPDFs(urls: [URL], parentFolderID: UUID?) throws {
        if let parentFolderID, folder(with: parentFolderID) == nil {
            throw HomeLibraryError.folderNotFound(parentFolderID)
        }
        let imported = try pdfImportService.importPDFs(urls: urls)
        let now = Self.nowMillis()

        for pdfNotebook in imported {
            let fileName = pdfNotebook.sourceFileURL.lastPathComponent
            notebooks.append(
                NotebookRecord(
                    id: pdfNotebook.id,
                    title: pdfNotebook.title,
                    folderID: parentFolderID,
                    template: .blank,
                    orientation: .portrait,
                    pageCount: max(1, pdfNotebook.pages.count),
                    sourcePDFFileName: fileName,
                    thumbnailRevision: 1,
                    createdAtMillis: now,
                    updatedAtMillis: now,
                    lastEditedAtMillis: now
                )
            )
        }

        notebooks.sort { $0.lastEditedAtMillis > $1.lastEditedAtMillis }
        try save()
    }

    func touchNotebook(_ id: UUID) throws {
        guard let index = notebooks.firstIndex(where: { $0.id == id }) else { return }
        let now = Self.nowMillis()
        notebooks[index].lastEditedAtMillis = now
        notebooks[index].updatedAtMillis = now
        notebooks[index].thumbnailRevision &+= 1
        notebooks.sort { $0.lastEditedAtMillis > $1.lastEditedAtMillis }
        try save()
    }

    func folders(in parentID: UUID?) -> [NoteFolder] {
        folders
            .filter { $0.parentFolderID == parentID }
            .sorted { lhs, rhs in
                if lhs.updatedAtMillis != rhs.updatedAtMillis {
                    return lhs.updatedAtMillis > rhs.updatedAtMillis
                }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    func notebooks(in parentID: UUID?) -> [NotebookRecord] {
        notebooks
            .filter { $0.folderID == parentID }
            .sorted { $0.lastEditedAtMillis > $1.lastEditedAtMillis }
    }

    private func folder(with id: UUID) -> NoteFolder? {
        folders.first(where: { $0.id == id })
    }

    private func load() throws {
        let url = try libraryFileURL()
        guard fileManager.fileExists(atPath: url.path) else {
            folders = []
            notebooks = []
            return
        }
        let data = try Data(contentsOf: url)
        let snapshot = try JSONDecoder().decode(HomeLibrarySnapshot.self, from: data)
        guard snapshot.schemaVersion <= HomeLibrarySnapshot.currentSchemaVersion else {
            folders = []
            notebooks = []
            return
        }
        folders = snapshot.folders
        notebooks = snapshot.notebooks
    }

    private func save() throws {
        let snapshot = HomeLibrarySnapshot(
            schemaVersion: HomeLibrarySnapshot.currentSchemaVersion,
            folders: folders,
            notebooks: notebooks
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        let url = try libraryFileURL()
        try data.write(to: url, options: .atomic)
    }

    private func libraryFileURL() throws -> URL {
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw HomeLibraryError.appSupportUnavailable
        }
        let directory = appSupport.appendingPathComponent("HomeLibrary", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory.appendingPathComponent("library.json")
    }

    private static func nowMillis() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }
}
