//
//  HomeModels.swift
//  InfiNote
//

import Foundation
import SwiftUI

enum NotebookTemplate: String, Codable, CaseIterable, Identifiable {
    case blank
    case lined
    case grid
    case dotted

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .blank: return "template.blank"
        case .lined: return "template.lined"
        case .grid: return "template.grid"
        case .dotted: return "template.dotted"
        }
    }
}

extension NotebookTemplate {
    var canvasBackgroundTemplate: CanvasBackgroundTemplate {
        switch self {
        case .blank:
            return .blank
        case .lined:
            return .lines
        case .grid:
            return .grid
        case .dotted:
            return .dots
        }
    }
}

enum NotebookOrientation: String, Codable, CaseIterable, Identifiable {
    case portrait
    case landscape

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .portrait: return "orientation.portrait"
        case .landscape: return "orientation.landscape"
        }
    }
}

struct NoteFolder: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var parentFolderID: UUID?
    var createdAtMillis: Int64
    var updatedAtMillis: Int64
}

struct NotebookRecord: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var folderID: UUID?
    var template: NotebookTemplate
    var orientation: NotebookOrientation
    var pageCount: Int
    var sourcePDFFileName: String?
    var sourcePDFResourceID: UUID?
    var sourcePDFRelativePath: String?
    var thumbnailRevision: Int32
    var createdAtMillis: Int64
    var updatedAtMillis: Int64
    var lastEditedAtMillis: Int64

    var thumbnailKey: String {
        "\(id.uuidString)-\(thumbnailRevision)"
    }
}

struct NotebookPageRecord: Identifiable, Codable, Hashable {
    var id: UUID
    var pageIndex: Int
    var width: CGFloat
    var height: CGFloat
    var annotations: CanvasPageAnnotations
}

struct NotebookDocumentRecord: Codable, Hashable {
    var notebookID: UUID
    var pages: [NotebookPageRecord]
}

enum ImportedResourceKind: String, Codable, CaseIterable, Identifiable {
    case pdf
    case image
    case font
    case file
    case page
    case canvas

    var id: String { rawValue }
}

struct ImportedResource: Identifiable, Codable, Hashable {
    var id: UUID
    var kind: ImportedResourceKind
    var relativePath: String
    var originalFileName: String
    var mediaType: String
    var bytes: Int64
    var createdAtMillis: Int64
    var updatedAtMillis: Int64
    var isDeleted: Bool
}

enum ResourceOwnerType: String, Codable, CaseIterable, Identifiable {
    case folder
    case notebook
    case page
    case canvas
    case app

    var id: String { rawValue }
}

struct ResourceReference: Identifiable, Codable, Hashable {
    var id: UUID
    var resourceID: UUID
    var ownerType: ResourceOwnerType
    var ownerID: UUID
    var purpose: String
    var createdAtMillis: Int64
}

struct DeletionTombstone: Identifiable, Codable, Hashable {
    var id: UUID
    var ownerType: ResourceOwnerType
    var ownerID: UUID
    var displayName: String
    var deletedAtMillis: Int64
}

enum ResourceFileDeletionPolicy: String, Codable {
    case detachReferenceOnly
    case deleteIfNoReferences
    case forceDeleteUnderlyingFile
}

struct DeletionSummary: Hashable {
    var deletedFolderIDs: Set<UUID> = []
    var deletedNotebookIDs: Set<UUID> = []
    var deletedResourceIDs: Set<UUID> = []
    var detachedReferenceIDs: Set<UUID> = []
    var deletedFileRelativePaths: [String] = []
}

struct HomeLibrarySnapshot: Codable, Hashable {
    var schemaVersion: UInt16
    var folders: [NoteFolder]
    var notebooks: [NotebookRecord]
    var resources: [ImportedResource]
    var references: [ResourceReference]
    var tombstones: [DeletionTombstone]

    static let currentSchemaVersion: UInt16 = 2

    init(
        schemaVersion: UInt16,
        folders: [NoteFolder],
        notebooks: [NotebookRecord],
        resources: [ImportedResource],
        references: [ResourceReference],
        tombstones: [DeletionTombstone]
    ) {
        self.schemaVersion = schemaVersion
        self.folders = folders
        self.notebooks = notebooks
        self.resources = resources
        self.references = references
        self.tombstones = tombstones
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(UInt16.self, forKey: .schemaVersion) ?? 1
        folders = try container.decodeIfPresent([NoteFolder].self, forKey: .folders) ?? []
        notebooks = try container.decodeIfPresent([NotebookRecord].self, forKey: .notebooks) ?? []
        resources = try container.decodeIfPresent([ImportedResource].self, forKey: .resources) ?? []
        references = try container.decodeIfPresent([ResourceReference].self, forKey: .references) ?? []
        tombstones = try container.decodeIfPresent([DeletionTombstone].self, forKey: .tombstones) ?? []
    }
}

enum HomeLibraryError: Error {
    case appSupportUnavailable
    case folderNotFound(UUID)
    case notebookNotFound(UUID)
    case invalidName
    case invalidPageSelection
    case resourceNotFound(UUID)
    case resourceInUse(UUID)
    case illegalDelete(String)
}
