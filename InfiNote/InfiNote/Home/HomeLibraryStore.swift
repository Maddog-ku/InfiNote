import Foundation
import Combine
import CryptoKit
import CoreGraphics

private enum HomeResourceFileStoreError: Error {
    case appSupportUnavailable
    case missingFile(URL)
}

private struct HomeResourceFileStore {
    private let fileManager = FileManager.default

    func absoluteURL(for relativePath: String) throws -> URL {
        try baseDirectory().appendingPathComponent(relativePath)
    }

    func importExternalFile(
        from sourceURL: URL,
        kind: ImportedResourceKind
    ) throws -> (relativePath: String, bytes: Int64, fileName: String) {
        let scoped = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw HomeResourceFileStoreError.missingFile(sourceURL)
        }

        let ext = sourceURL.pathExtension
        let fileName = ext.isEmpty ? UUID().uuidString : "\(UUID().uuidString).\(ext)"
        let kindDir = try directory(for: kind)
        let targetURL = kindDir.appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: targetURL.path) {
            try fileManager.removeItem(at: targetURL)
        }
        try fileManager.copyItem(at: sourceURL, to: targetURL)

        let attr = try fileManager.attributesOfItem(atPath: targetURL.path)
        let bytes = (attr[.size] as? NSNumber)?.int64Value ?? 0
        let relative = try makeRelativePath(forAbsolute: targetURL)
        return (relativePath: relative, bytes: bytes, fileName: sourceURL.lastPathComponent)
    }

    func deleteFile(relativePath: String) throws {
        let url = try absoluteURL(for: relativePath)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    func renameFile(relativePath: String, newName: String) throws -> String {
        let source = try absoluteURL(for: relativePath)
        let destination = source.deletingLastPathComponent().appendingPathComponent(newName)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: source, to: destination)
        return try makeRelativePath(forAbsolute: destination)
    }

    private func makeRelativePath(forAbsolute url: URL) throws -> String {
        let base = try baseDirectory().standardizedFileURL.path
        let absolute = url.standardizedFileURL.path
        if absolute.hasPrefix(base + "/") {
            return String(absolute.dropFirst(base.count + 1))
        }
        return url.lastPathComponent
    }

    private func directory(for kind: ImportedResourceKind) throws -> URL {
        let dir = try baseDirectory().appendingPathComponent(kind.rawValue, isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func baseDirectory() throws -> URL {
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw HomeResourceFileStoreError.appSupportUnavailable
        }
        let dir = appSupport.appendingPathComponent("HomeResources", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
}

@MainActor
final class HomeLibraryStore: ObservableObject {
    @Published private(set) var folders: [NoteFolder] = []
    @Published private(set) var notebooks: [NotebookRecord] = []
    @Published private(set) var resources: [ImportedResource] = []
    @Published private(set) var references: [ResourceReference] = []
    @Published private(set) var tombstones: [DeletionTombstone] = []
    @Published var currentFolderID: UUID?

    private let fileManager = FileManager.default
    private let pdfImportService = PDFImportService()
    private let resourceStore = HomeResourceFileStore()
    private let thumbnailService = NotebookThumbnailService.shared

    init() {
        do {
            try load()
            try migrateLegacyPDFReferencesIfNeeded()
        } catch {
            folders = []
            notebooks = []
            resources = []
            references = []
            tombstones = []
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
                sourcePDFResourceID: nil,
                sourcePDFRelativePath: nil,
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
            let copiedPDF = pdfNotebook.sourceFileURL
            let importedFile = try resourceStore.importExternalFile(from: copiedPDF, kind: .pdf)
            try? fileManager.removeItem(at: copiedPDF)

            let resourceID = UUID()
            resources.append(
                ImportedResource(
                    id: resourceID,
                    kind: .pdf,
                    relativePath: importedFile.relativePath,
                    originalFileName: importedFile.fileName,
                    mediaType: "application/pdf",
                    bytes: importedFile.bytes,
                    createdAtMillis: now,
                    updatedAtMillis: now,
                    isDeleted: false
                )
            )

            let notebookID = pdfNotebook.id
            addReference(resourceID: resourceID, ownerType: .notebook, ownerID: notebookID, purpose: "source_pdf")

            notebooks.append(
                NotebookRecord(
                    id: notebookID,
                    title: pdfNotebook.title,
                    folderID: parentFolderID,
                    template: .blank,
                    orientation: .portrait,
                    pageCount: max(1, pdfNotebook.pages.count),
                    sourcePDFFileName: importedFile.fileName,
                    sourcePDFResourceID: resourceID,
                    sourcePDFRelativePath: importedFile.relativePath,
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

    func importAssets(
        urls: [URL],
        kind: ImportedResourceKind,
        ownerType: ResourceOwnerType,
        ownerID: UUID,
        purpose: String
    ) throws -> [ImportedResource] {
        let now = Self.nowMillis()
        var created: [ImportedResource] = []

        for url in urls {
            let imported = try resourceStore.importExternalFile(from: url, kind: kind)
            let mediaType = Self.mediaType(for: kind, pathExtension: url.pathExtension)
            let resource = ImportedResource(
                id: UUID(),
                kind: kind,
                relativePath: imported.relativePath,
                originalFileName: imported.fileName,
                mediaType: mediaType,
                bytes: imported.bytes,
                createdAtMillis: now,
                updatedAtMillis: now,
                isDeleted: false
            )
            resources.append(resource)
            addReference(resourceID: resource.id, ownerType: ownerType, ownerID: ownerID, purpose: purpose)
            created.append(resource)
        }

        try save()
        return created
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

    func renameFolder(_ id: UUID, to newName: String) throws {
        guard let index = folders.firstIndex(where: { $0.id == id }) else {
            throw HomeLibraryError.folderNotFound(id)
        }
        let validated = try Self.validateDisplayName(newName)
        folders[index].name = validated
        folders[index].updatedAtMillis = Self.nowMillis()
        try save()
    }

    func renameNotebook(_ id: UUID, to newName: String) throws {
        guard let index = notebooks.firstIndex(where: { $0.id == id }) else {
            throw HomeLibraryError.notebookNotFound(id)
        }
        let validated = try Self.validateDisplayName(newName)
        notebooks[index].title = validated
        notebooks[index].updatedAtMillis = Self.nowMillis()
        notebooks[index].lastEditedAtMillis = notebooks[index].updatedAtMillis
        notebooks[index].thumbnailRevision &+= 1
        try save()
    }

    func renamePDF(_ resourceID: UUID, to newName: String) throws {
        try renameResource(resourceID, to: newName, expectedKind: .pdf)
    }

    func renameFile(_ resourceID: UUID, to newName: String) throws {
        try renameResource(resourceID, to: newName, expectedKind: nil)
    }

    func deletePDF(
        _ resourceID: UUID,
        policy: ResourceFileDeletionPolicy = .deleteIfNoReferences
    ) throws -> DeletionSummary {
        guard let resource = resources.first(where: { $0.id == resourceID }) else {
            throw HomeLibraryError.resourceNotFound(resourceID)
        }
        guard resource.kind == .pdf else {
            throw HomeLibraryError.illegalDelete("Resource is not a PDF.")
        }
        return try deleteImportedResources(ids: [resourceID], policy: policy)
    }

    func deleteFile(
        _ resourceID: UUID,
        policy: ResourceFileDeletionPolicy = .deleteIfNoReferences
    ) throws -> DeletionSummary {
        try deleteImportedResources(ids: [resourceID], policy: policy)
    }

    func deleteFolder(
        _ id: UUID,
        policy: ResourceFileDeletionPolicy = .deleteIfNoReferences
    ) throws -> DeletionSummary {
        try deleteFolders(ids: [id], policy: policy)
    }

    func deleteFolders(
        ids: [UUID],
        policy: ResourceFileDeletionPolicy = .deleteIfNoReferences
    ) throws -> DeletionSummary {
        let targetSet = Set(ids)
        guard !targetSet.isEmpty else { return DeletionSummary() }

        let folderIDs = allDescendantFolderIDs(for: targetSet)
        let notebookIDs = Set(
            notebooks
                .filter { notebook in
                    guard let folderID = notebook.folderID else { return false }
                    return folderIDs.contains(folderID)
                }
                .map(\.id)
        )

        var summary = try deleteNotebooksInternal(ids: notebookIDs, policy: policy, persist: false)

        let now = Self.nowMillis()
        for folderID in folderIDs {
            if let folder = folders.first(where: { $0.id == folderID }) {
                tombstones.append(
                    DeletionTombstone(
                        id: UUID(),
                        ownerType: .folder,
                        ownerID: folder.id,
                        displayName: folder.name,
                        deletedAtMillis: now
                    )
                )
            }
        }

        folders.removeAll { folderIDs.contains($0.id) }
        summary.deletedFolderIDs = folderIDs

        if let currentFolderID, folderIDs.contains(currentFolderID) {
            self.currentFolderID = nil
        }

        try save()
        return summary
    }

    func deleteNotebook(
        _ id: UUID,
        policy: ResourceFileDeletionPolicy = .deleteIfNoReferences
    ) throws -> DeletionSummary {
        try deleteNotebooks(ids: [id], policy: policy)
    }

    func deleteNotebooks(
        ids: [UUID],
        policy: ResourceFileDeletionPolicy = .deleteIfNoReferences
    ) throws -> DeletionSummary {
        try deleteNotebooksInternal(ids: Set(ids), policy: policy, persist: true)
    }

    func deletePages(
        notebookID: UUID,
        pageIndexes: IndexSet,
        policy: ResourceFileDeletionPolicy = .deleteIfNoReferences
    ) throws -> DeletionSummary {
        guard let notebookIndex = notebooks.firstIndex(where: { $0.id == notebookID }) else {
            throw HomeLibraryError.notebookNotFound(notebookID)
        }
        guard !pageIndexes.isEmpty else {
            throw HomeLibraryError.invalidPageSelection
        }

        var summary = DeletionSummary()
        var deletedOwnerIDs: Set<UUID> = []
        for pageIndex in pageIndexes {
            deletedOwnerIDs.insert(pageOwnerID(notebookID: notebookID, pageIndex: pageIndex))
        }

        let detached = removeReferences(ownerType: .page, ownerIDs: deletedOwnerIDs)
        summary.detachedReferenceIDs.formUnion(detached.map(\.id))

        let affectedResourceIDs = Set(detached.map(\.resourceID))
        let cleaned = try cleanupResources(resourceIDs: affectedResourceIDs, policy: policy)
        summary.deletedResourceIDs.formUnion(cleaned.deletedResourceIDs)
        summary.deletedFileRelativePaths.append(contentsOf: cleaned.deletedFileRelativePaths)

        let deletedCount = min(pageIndexes.count, notebooks[notebookIndex].pageCount)
        notebooks[notebookIndex].pageCount = max(1, notebooks[notebookIndex].pageCount - deletedCount)
        notebooks[notebookIndex].updatedAtMillis = Self.nowMillis()
        notebooks[notebookIndex].thumbnailRevision &+= 1

        try save()
        return summary
    }

    func deleteImportedResources(
        ids: [UUID],
        policy: ResourceFileDeletionPolicy = .deleteIfNoReferences
    ) throws -> DeletionSummary {
        var summary = DeletionSummary()
        for resourceID in ids {
            guard let resource = resources.first(where: { $0.id == resourceID }) else {
                throw HomeLibraryError.resourceNotFound(resourceID)
            }
            let refIDs = references.filter { $0.resourceID == resourceID }.map(\.id)

            switch policy {
            case .detachReferenceOnly:
                references.removeAll { $0.resourceID == resourceID }
                summary.detachedReferenceIDs.formUnion(refIDs)
            case .deleteIfNoReferences:
                if !refIDs.isEmpty {
                    throw HomeLibraryError.resourceInUse(resourceID)
                }
                try deleteResourceRecord(resource)
                summary.deletedResourceIDs.insert(resourceID)
                summary.deletedFileRelativePaths.append(resource.relativePath)
            case .forceDeleteUnderlyingFile:
                references.removeAll { $0.resourceID == resourceID }
                summary.detachedReferenceIDs.formUnion(refIDs)
                try deleteResourceRecord(resource)
                summary.deletedResourceIDs.insert(resourceID)
                summary.deletedFileRelativePaths.append(resource.relativePath)
            }
        }
        try save()
        return summary
    }

    func cleanupOrphanedResources() throws -> [UUID] {
        let orphanIDs = resources
            .filter { referenceCount(for: $0.id) == 0 }
            .map(\.id)
        let result = try cleanupResources(resourceIDs: Set(orphanIDs), policy: .deleteIfNoReferences)
        try save()
        return Array(result.deletedResourceIDs)
    }

    func resourceCount(for kind: ImportedResourceKind) -> Int {
        resources.filter { !$0.isDeleted && $0.kind == kind }.count
    }

    func referenceCount(for resourceID: UUID) -> Int {
        references.filter { $0.resourceID == resourceID }.count
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

    func notebookRecord(with id: UUID) -> NotebookRecord? {
        notebooks.first(where: { $0.id == id })
    }

    func loadNotebookDocument(for notebookID: UUID) throws -> NotebookDocumentRecord {
        guard let notebook = notebookRecord(with: notebookID) else {
            throw HomeLibraryError.notebookNotFound(notebookID)
        }

        let url = try notebookDocumentURL(for: notebookID)
        let loaded: NotebookDocumentRecord
        if fileManager.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            loaded = try JSONDecoder().decode(NotebookDocumentRecord.self, from: data)
        } else {
            loaded = buildNotebookDocument(for: notebook)
        }

        let normalized = normalizedDocument(loaded, for: notebook)
        try persistNotebookDocument(normalized)
        return normalized
    }

    func saveNotebookDocument(_ document: NotebookDocumentRecord) throws {
        guard let notebook = notebookRecord(with: document.notebookID) else {
            throw HomeLibraryError.notebookNotFound(document.notebookID)
        }

        let normalized = normalizedDocument(document, for: notebook)
        try persistNotebookDocument(normalized)
        try updateNotebookMetadata(for: normalized.notebookID, pageCount: normalized.pages.count, bumpThumbnail: false)
    }

    func urlForNotebookPDF(_ notebook: NotebookRecord) -> URL? {
        if let relative = notebook.sourcePDFRelativePath,
           let url = try? resourceStore.absoluteURL(for: relative),
           fileManager.fileExists(atPath: url.path) {
            return url
        }
        guard let fileName = notebook.sourcePDFFileName else { return nil }
        return legacyPDFURL(fileName: fileName)
    }

    func removeFontFiles(urls: [URL]) throws -> [URL] {
        let deleted = try FontRegistry.shared.deletePersistedFontFiles(urls: urls)

        let normalized = Set(deleted.map { $0.standardizedFileURL.path })
        let matchingResourceIDs = resources
            .filter { resource in
                guard resource.kind == .font,
                      let absURL = try? resourceStore.absoluteURL(for: resource.relativePath) else {
                    return false
                }
                return normalized.contains(absURL.standardizedFileURL.path)
            }
            .map(\.id)

        if !matchingResourceIDs.isEmpty {
            _ = try deleteImportedResources(ids: matchingResourceIDs, policy: .forceDeleteUnderlyingFile)
        }
        return deleted
    }

    private func renameResource(
        _ resourceID: UUID,
        to requestedName: String,
        expectedKind: ImportedResourceKind?
    ) throws {
        guard let index = resources.firstIndex(where: { $0.id == resourceID }) else {
            throw HomeLibraryError.resourceNotFound(resourceID)
        }
        let resource = resources[index]
        if let expectedKind, resource.kind != expectedKind {
            throw HomeLibraryError.illegalDelete("Resource kind mismatch.")
        }

        let sourceURL = try resourceStore.absoluteURL(for: resource.relativePath)
        let ext = sourceURL.pathExtension
        let validated = try Self.validateFileName(requestedName, keepExtension: ext)
        let newRelativePath = try resourceStore.renameFile(relativePath: resource.relativePath, newName: validated)

        resources[index].relativePath = newRelativePath
        resources[index].originalFileName = validated
        resources[index].updatedAtMillis = Self.nowMillis()

        for notebookIndex in notebooks.indices where notebooks[notebookIndex].sourcePDFResourceID == resourceID {
            notebooks[notebookIndex].sourcePDFRelativePath = newRelativePath
            notebooks[notebookIndex].sourcePDFFileName = validated
            notebooks[notebookIndex].updatedAtMillis = Self.nowMillis()
            notebooks[notebookIndex].thumbnailRevision &+= 1
            thumbnailService.removeThumbnails(for: notebooks[notebookIndex].id)
        }
        try save()
    }

    private func deleteNotebooksInternal(
        ids: Set<UUID>,
        policy: ResourceFileDeletionPolicy,
        persist: Bool
    ) throws -> DeletionSummary {
        guard !ids.isEmpty else { return DeletionSummary() }

        var summary = DeletionSummary()
        let now = Self.nowMillis()
        let notebookToDelete = notebooks.filter { ids.contains($0.id) }

        for notebook in notebookToDelete {
            tombstones.append(
                DeletionTombstone(
                    id: UUID(),
                    ownerType: .notebook,
                    ownerID: notebook.id,
                    displayName: notebook.title,
                    deletedAtMillis: now
                )
            )
            summary.deletedNotebookIDs.insert(notebook.id)
        }

        let deletedNotebookIDs = Set(notebookToDelete.map(\.id))
        let detachedNotebookRefs = removeReferences(ownerType: .notebook, ownerIDs: deletedNotebookIDs)
        summary.detachedReferenceIDs.formUnion(detachedNotebookRefs.map(\.id))

        var pageOwnerIDs: Set<UUID> = []
        for notebook in notebookToDelete {
            for pageIndex in 0..<max(1, notebook.pageCount) {
                pageOwnerIDs.insert(pageOwnerID(notebookID: notebook.id, pageIndex: pageIndex))
            }
            thumbnailService.removeThumbnails(for: notebook.id)
        }

        let detachedPageRefs = removeReferences(ownerType: .page, ownerIDs: pageOwnerIDs)
        summary.detachedReferenceIDs.formUnion(detachedPageRefs.map(\.id))

        var affectedResourceIDs = Set(detachedNotebookRefs.map(\.resourceID))
        affectedResourceIDs.formUnion(detachedPageRefs.map(\.resourceID))

        let cleanup = try cleanupResources(resourceIDs: affectedResourceIDs, policy: policy)
        summary.deletedResourceIDs.formUnion(cleanup.deletedResourceIDs)
        summary.deletedFileRelativePaths.append(contentsOf: cleanup.deletedFileRelativePaths)

        for notebook in notebookToDelete {
            try cleanupLegacyPDFIfNeeded(notebook: notebook)
        }

        notebooks.removeAll { ids.contains($0.id) }

        if persist {
            try save()
        }

        return summary
    }

    private func cleanupLegacyPDFIfNeeded(notebook: NotebookRecord) throws {
        guard notebook.sourcePDFResourceID == nil,
              let fileName = notebook.sourcePDFFileName,
              let url = legacyPDFURL(fileName: fileName) else {
            return
        }

        let stillReferenced = notebooks.contains { candidate in
            candidate.id != notebook.id &&
            candidate.sourcePDFResourceID == nil &&
            candidate.sourcePDFFileName == fileName
        }
        if !stillReferenced {
            try? fileManager.removeItem(at: url)
        }
    }

    private func cleanupResources(
        resourceIDs: Set<UUID>,
        policy: ResourceFileDeletionPolicy
    ) throws -> DeletionSummary {
        var summary = DeletionSummary()
        guard !resourceIDs.isEmpty else { return summary }

        for id in resourceIDs {
            guard let resource = resources.first(where: { $0.id == id }) else { continue }
            let refCount = referenceCount(for: id)

            switch policy {
            case .detachReferenceOnly:
                continue
            case .deleteIfNoReferences:
                guard refCount == 0 else { continue }
                try deleteResourceRecord(resource)
                summary.deletedResourceIDs.insert(id)
                summary.deletedFileRelativePaths.append(resource.relativePath)
            case .forceDeleteUnderlyingFile:
                references.removeAll { $0.resourceID == id }
                try deleteResourceRecord(resource)
                summary.deletedResourceIDs.insert(id)
                summary.deletedFileRelativePaths.append(resource.relativePath)
            }
        }

        return summary
    }

    private func deleteResourceRecord(_ resource: ImportedResource) throws {
        try resourceStore.deleteFile(relativePath: resource.relativePath)
        resources.removeAll { $0.id == resource.id }
    }

    private func removeReferences(ownerType: ResourceOwnerType, ownerIDs: Set<UUID>) -> [ResourceReference] {
        guard !ownerIDs.isEmpty else { return [] }
        let detached = references.filter { $0.ownerType == ownerType && ownerIDs.contains($0.ownerID) }
        references.removeAll { $0.ownerType == ownerType && ownerIDs.contains($0.ownerID) }
        return detached
    }

    private func addReference(resourceID: UUID, ownerType: ResourceOwnerType, ownerID: UUID, purpose: String) {
        references.append(
            ResourceReference(
                id: UUID(),
                resourceID: resourceID,
                ownerType: ownerType,
                ownerID: ownerID,
                purpose: purpose,
                createdAtMillis: Self.nowMillis()
            )
        )
    }

    private func allDescendantFolderIDs(for rootIDs: Set<UUID>) -> Set<UUID> {
        var visited = rootIDs
        var queue = Array(rootIDs)
        while let current = queue.popLast() {
            let children = folders.filter { $0.parentFolderID == current }.map(\.id)
            for child in children where !visited.contains(child) {
                visited.insert(child)
                queue.append(child)
            }
        }
        return visited
    }

    private func pageOwnerID(notebookID: UUID, pageIndex: Int) -> UUID {
        let raw = "\(notebookID.uuidString)-page-\(pageIndex)"
        let digest = SHA256.hash(data: Data(raw.utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        let tuple: uuid_t = (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        )
        return UUID(uuid: tuple)
    }

    private func folder(with id: UUID) -> NoteFolder? {
        folders.first(where: { $0.id == id })
    }

    private func buildNotebookDocument(for notebook: NotebookRecord) -> NotebookDocumentRecord {
        let pages: [NotebookPageRecord]
        if let pdfURL = urlForNotebookPDF(notebook),
           let document = CGPDFDocument(pdfURL as CFURL),
           document.numberOfPages > 0 {
            pages = (1...document.numberOfPages).compactMap { pageNumber in
                guard let page = document.page(at: pageNumber) else { return nil }
                let media = page.getBoxRect(.mediaBox)
                return NotebookPageRecord(
                    id: UUID(),
                    pageIndex: pageNumber - 1,
                    width: max(1, media.width),
                    height: max(1, media.height),
                    annotations: .empty
                )
            }
        } else {
            pages = makeBlankPages(
                count: max(1, notebook.pageCount),
                orientation: notebook.orientation
            )
        }

        return NotebookDocumentRecord(
            notebookID: notebook.id,
            pages: pages.isEmpty ? makeBlankPages(count: 1, orientation: notebook.orientation) : pages
        )
    }

    private func normalizedDocument(
        _ document: NotebookDocumentRecord,
        for notebook: NotebookRecord
    ) -> NotebookDocumentRecord {
        let defaultPageSize = Self.defaultPageSize(for: notebook.orientation)
        let sortedPages = document.pages
            .sorted { lhs, rhs in
                if lhs.pageIndex != rhs.pageIndex {
                    return lhs.pageIndex < rhs.pageIndex
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }

        let normalizedPages = sortedPages.enumerated().map { offset, page -> NotebookPageRecord in
            NotebookPageRecord(
                id: page.id,
                pageIndex: offset,
                width: page.width > 0 ? page.width : defaultPageSize.width,
                height: page.height > 0 ? page.height : defaultPageSize.height,
                annotations: page.annotations
            )
        }

        let usablePages = normalizedPages.isEmpty
            ? makeBlankPages(count: 1, orientation: notebook.orientation)
            : normalizedPages

        return NotebookDocumentRecord(
            notebookID: notebook.id,
            pages: usablePages
        )
    }

    private func persistNotebookDocument(_ document: NotebookDocumentRecord) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        try data.write(to: notebookDocumentURL(for: document.notebookID), options: .atomic)
    }

    private func notebookDocumentURL(for notebookID: UUID) throws -> URL {
        let base = try libraryFileURL().deletingLastPathComponent()
        let directory = base.appendingPathComponent("NotebookDocuments", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory.appendingPathComponent("\(notebookID.uuidString).json")
    }

    private func makeBlankPages(count: Int, orientation: NotebookOrientation) -> [NotebookPageRecord] {
        let size = Self.defaultPageSize(for: orientation)
        return (0..<max(1, count)).map { index in
            NotebookPageRecord(
                id: UUID(),
                pageIndex: index,
                width: size.width,
                height: size.height,
                annotations: .empty
            )
        }
    }

    private func updateNotebookMetadata(
        for notebookID: UUID,
        pageCount: Int,
        bumpThumbnail: Bool
    ) throws {
        guard let index = notebooks.firstIndex(where: { $0.id == notebookID }) else {
            throw HomeLibraryError.notebookNotFound(notebookID)
        }

        let normalizedCount = max(1, pageCount)
        let now = Self.nowMillis()
        notebooks[index].pageCount = normalizedCount
        notebooks[index].updatedAtMillis = now
        notebooks[index].lastEditedAtMillis = now
        if bumpThumbnail {
            notebooks[index].thumbnailRevision &+= 1
        }
        notebooks.sort { $0.lastEditedAtMillis > $1.lastEditedAtMillis }
        try save()
    }

    private func load() throws {
        let url = try libraryFileURL()
        guard fileManager.fileExists(atPath: url.path) else {
            folders = []
            notebooks = []
            resources = []
            references = []
            tombstones = []
            return
        }
        let data = try Data(contentsOf: url)
        let snapshot = try JSONDecoder().decode(HomeLibrarySnapshot.self, from: data)
        guard snapshot.schemaVersion <= HomeLibrarySnapshot.currentSchemaVersion else {
            folders = []
            notebooks = []
            resources = []
            references = []
            tombstones = []
            return
        }
        folders = snapshot.folders
        notebooks = snapshot.notebooks
        resources = snapshot.resources
        references = snapshot.references
        tombstones = snapshot.tombstones
    }

    private func save() throws {
        let snapshot = HomeLibrarySnapshot(
            schemaVersion: HomeLibrarySnapshot.currentSchemaVersion,
            folders: folders,
            notebooks: notebooks,
            resources: resources,
            references: references,
            tombstones: tombstones
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

    private func migrateLegacyPDFReferencesIfNeeded() throws {
        var migrated = false
        let now = Self.nowMillis()

        for index in notebooks.indices {
            guard notebooks[index].sourcePDFResourceID == nil,
                  notebooks[index].sourcePDFRelativePath == nil,
                  let fileName = notebooks[index].sourcePDFFileName,
                  let legacyURL = legacyPDFURL(fileName: fileName) else {
                continue
            }

            let imported = try resourceStore.importExternalFile(from: legacyURL, kind: .pdf)
            let resourceID = UUID()
            resources.append(
                ImportedResource(
                    id: resourceID,
                    kind: .pdf,
                    relativePath: imported.relativePath,
                    originalFileName: fileName,
                    mediaType: "application/pdf",
                    bytes: imported.bytes,
                    createdAtMillis: now,
                    updatedAtMillis: now,
                    isDeleted: false
                )
            )
            addReference(resourceID: resourceID, ownerType: .notebook, ownerID: notebooks[index].id, purpose: "source_pdf")

            notebooks[index].sourcePDFResourceID = resourceID
            notebooks[index].sourcePDFRelativePath = imported.relativePath
            try? fileManager.removeItem(at: legacyURL)
            migrated = true
        }

        if migrated {
            try save()
        }
    }

    private func legacyPDFURL(fileName: String) -> URL? {
        guard !fileName.isEmpty,
              let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let url = appSupport
            .appendingPathComponent("PDFNotebooks", isDirectory: true)
            .appendingPathComponent(fileName)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    private static func mediaType(for kind: ImportedResourceKind, pathExtension ext: String) -> String {
        let lower = ext.lowercased()
        switch kind {
        case .pdf:
            return "application/pdf"
        case .image:
            return "image/\(lower.isEmpty ? "png" : lower)"
        case .font:
            return "font/\(lower.isEmpty ? "ttf" : lower)"
        case .file, .page, .canvas:
            return "application/octet-stream"
        }
    }

    private static func validateDisplayName(_ raw: String) throws -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            throw HomeLibraryError.invalidName
        }
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|")
        guard value.rangeOfCharacter(from: invalid) == nil else {
            throw HomeLibraryError.invalidName
        }
        return value
    }

    private static func validateFileName(_ raw: String, keepExtension ext: String) throws -> String {
        let base = try validateDisplayName(raw)
        let baseWithoutExtension = URL(fileURLWithPath: base).deletingPathExtension().lastPathComponent
        let cleanBase = baseWithoutExtension.isEmpty ? "Untitled" : baseWithoutExtension
        if ext.isEmpty {
            return cleanBase
        }
        return "\(cleanBase).\(ext)"
    }

    private static func defaultPageSize(for orientation: NotebookOrientation) -> CGSize {
        switch orientation {
        case .portrait:
            return CGSize(width: 768, height: 1024)
        case .landscape:
            return CGSize(width: 1024, height: 768)
        }
    }

    private static func nowMillis() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }
}
