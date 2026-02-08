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
    var thumbnailRevision: Int32
    var createdAtMillis: Int64
    var updatedAtMillis: Int64
    var lastEditedAtMillis: Int64

    var thumbnailKey: String {
        "\(id.uuidString)-\(thumbnailRevision)"
    }
}

struct HomeLibrarySnapshot: Codable, Hashable {
    var schemaVersion: UInt16
    var folders: [NoteFolder]
    var notebooks: [NotebookRecord]

    static let currentSchemaVersion: UInt16 = 1
}

enum HomeLibraryError: Error {
    case appSupportUnavailable
    case folderNotFound(UUID)
}
