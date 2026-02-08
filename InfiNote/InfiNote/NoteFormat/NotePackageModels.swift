//
//  NotePackageModels.swift
//  InfiNote
//

import Foundation

enum NotePackageError: Error {
    case unsupportedSchema(UInt16)
    case missingFile(String)
    case invalidManifest
}

struct NotePackagePayload {
    var strokeDocument: StrokeDocument
    var textBoxes: [CanvasTextBox]
    var notebooks: [PDFNotebook]
    var imageFiles: [URL]
    var fontFiles: [URL]
}

struct NotePackage {
    var manifest: NoteDocumentManifest
    var strokeDocument: StrokeDocument
    var textBoxes: [CanvasTextBox]
    var notebooks: [PDFNotebook]
    var imageAssetURLs: [URL]
    var fontAssetURLs: [URL]
}

struct NoteDocumentManifest: Codable, Hashable {
    static let currentSchemaVersion: UInt16 = 1

    var schemaVersion: UInt16
    var minReaderSchemaVersion: UInt16
    var writer: NoteWriterInfo

    var documentID: UUID
    var createdAtMillis: Int64
    var updatedAtMillis: Int64

    var data: NoteDataSection
    var assets: NoteAssetSection
    var notebooks: [NoteNotebookManifest]
    var quickLoad: NoteQuickLoadIndex
}

struct NoteWriterInfo: Codable, Hashable {
    var appID: String
    var appVersion: String
    var platform: String
}

struct NoteDataSection: Codable, Hashable {
    var strokesFile: String
    var strokesCodec: String
    var textBoxesFile: String
    var textBoxesCodec: String
}

struct NoteAssetSection: Codable, Hashable {
    var pdfs: [NoteAssetDescriptor]
    var images: [NoteAssetDescriptor]
    var fonts: [NoteAssetDescriptor]
}

struct NoteAssetDescriptor: Codable, Hashable, Identifiable {
    var id: UUID
    var file: String
    var mediaType: String
    var bytes: Int64
    var sha256: String
}

struct NoteNotebookManifest: Codable, Hashable, Identifiable {
    var id: UUID
    var title: String
    var pdfAssetID: UUID
    var pages: [NoteNotebookPageManifest]
}

struct NoteNotebookPageManifest: Codable, Hashable {
    var pageIndex: Int
    var width: CGFloat
    var height: CGFloat
    var annotationFile: String?
}

struct NoteQuickLoadIndex: Codable, Hashable {
    var pageCount: Int
    var strokeCount: Int
    var textBoxCount: Int
    var notebookCount: Int
    var annotationFiles: [String]
}

struct NotePageAnnotationFile: Codable, Hashable {
    var strokes: [CanvasStroke]
    var textBoxes: [CanvasTextBox]
}
