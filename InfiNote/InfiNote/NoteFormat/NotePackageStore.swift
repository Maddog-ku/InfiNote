//
//  NotePackageStore.swift
//  InfiNote
//

import Foundation
import CryptoKit

struct NotePackageStore {
    private let fileManager = FileManager.default

    func writePackage(to directoryURL: URL, payload: NotePackagePayload) throws -> NoteDocumentManifest {
        if fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.removeItem(at: directoryURL)
        }
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let dataDir = directoryURL.appendingPathComponent("data", isDirectory: true)
        let assetsDir = directoryURL.appendingPathComponent("assets", isDirectory: true)
        let notebookDir = directoryURL.appendingPathComponent("notebooks", isDirectory: true)
        try fileManager.createDirectory(at: dataDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: assetsDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: notebookDir, withIntermediateDirectories: true)

        let strokesPath = "data/strokes.bin"
        let textBoxesPath = "data/text_boxes.json"

        let strokesData = StrokeCodec.encodeBinary(payload.strokeDocument)
        let strokesURL = directoryURL.appendingPathComponent(strokesPath)
        try strokesData.write(to: strokesURL, options: .atomic)

        let textBoxesData = try JSONEncoder.noteEncoder.encode(payload.textBoxes)
        let textBoxesURL = directoryURL.appendingPathComponent(textBoxesPath)
        try textBoxesData.write(to: textBoxesURL, options: .atomic)

        let pdfAssets = try copyNotebookPDFAssets(payload.notebooks, to: assetsDir)
        let imageAssets = try copyFileAssets(files: payload.imageFiles, to: assetsDir.appendingPathComponent("images", isDirectory: true), mediaTypePrefix: "image/")
        let fontAssets = try copyFileAssets(files: payload.fontFiles, to: assetsDir.appendingPathComponent("fonts", isDirectory: true), mediaTypePrefix: "font/")

        let notebookManifests = try writeNotebookAnnotations(
            payload.notebooks,
            pdfAssets: pdfAssets,
            at: notebookDir
        )

        let annotationFiles = notebookManifests
            .flatMap(\.pages)
            .compactMap(\.annotationFile)

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let manifest = NoteDocumentManifest(
            schemaVersion: NoteDocumentManifest.currentSchemaVersion,
            minReaderSchemaVersion: 1,
            writer: NoteWriterInfo(
                appID: "note.InfiNote",
                appVersion: "1.0",
                platform: "apple"
            ),
            documentID: UUID(),
            createdAtMillis: now,
            updatedAtMillis: now,
            data: NoteDataSection(
                strokesFile: strokesPath,
                strokesCodec: "infs-bin-v1",
                textBoxesFile: textBoxesPath,
                textBoxesCodec: "json-v1"
            ),
            assets: NoteAssetSection(
                pdfs: Array(pdfAssets.values).sorted(by: { $0.file < $1.file }),
                images: imageAssets,
                fonts: fontAssets
            ),
            notebooks: notebookManifests,
            quickLoad: NoteQuickLoadIndex(
                pageCount: notebookManifests.reduce(0) { $0 + $1.pages.count },
                strokeCount: payload.strokeDocument.strokes.count,
                textBoxCount: payload.textBoxes.count,
                notebookCount: payload.notebooks.count,
                annotationFiles: annotationFiles.sorted()
            )
        )

        let manifestURL = directoryURL.appendingPathComponent("document.json")
        let manifestData = try JSONEncoder.noteEncoder.encode(manifest)
        try manifestData.write(to: manifestURL, options: .atomic)

        return manifest
    }

    func readPackage(from directoryURL: URL) throws -> NotePackage {
        let manifestURL = directoryURL.appendingPathComponent("document.json")
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw NotePackageError.missingFile("document.json")
        }
        let manifestData = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(NoteDocumentManifest.self, from: manifestData)

        guard manifest.schemaVersion >= 1,
              manifest.schemaVersion >= manifest.minReaderSchemaVersion else {
            throw NotePackageError.unsupportedSchema(manifest.schemaVersion)
        }

        let strokesURL = directoryURL.appendingPathComponent(manifest.data.strokesFile)
        let textBoxesURL = directoryURL.appendingPathComponent(manifest.data.textBoxesFile)
        guard fileManager.fileExists(atPath: strokesURL.path) else {
            throw NotePackageError.missingFile(manifest.data.strokesFile)
        }
        guard fileManager.fileExists(atPath: textBoxesURL.path) else {
            throw NotePackageError.missingFile(manifest.data.textBoxesFile)
        }

        let strokeDocument = try StrokeCodec.decodeBinary(Data(contentsOf: strokesURL))
        let textBoxes = try JSONDecoder().decode([CanvasTextBox].self, from: Data(contentsOf: textBoxesURL))

        let pdfLookup = Dictionary(uniqueKeysWithValues: manifest.assets.pdfs.map { ($0.id, $0) })
        let notebooks: [PDFNotebook] = try manifest.notebooks.map { notebookManifest in
            guard let pdfAsset = pdfLookup[notebookManifest.pdfAssetID] else {
                throw NotePackageError.invalidManifest
            }
            let pdfURL = directoryURL.appendingPathComponent(pdfAsset.file)
            var annotationMap: [Int: CanvasPageAnnotations] = [:]
            var pages: [CanvasPDFPageInfo] = []

            for page in notebookManifest.pages {
                pages.append(
                    CanvasPDFPageInfo(
                        pageIndex: page.pageIndex,
                        width: page.width,
                        height: page.height
                    )
                )
                if let annotationFile = page.annotationFile {
                    let annotationURL = directoryURL.appendingPathComponent(annotationFile)
                    guard fileManager.fileExists(atPath: annotationURL.path) else {
                        throw NotePackageError.missingFile(annotationFile)
                    }
                    let annotationData = try Data(contentsOf: annotationURL)
                    let decoded = try JSONDecoder().decode(NotePageAnnotationFile.self, from: annotationData)
                    annotationMap[page.pageIndex] = CanvasPageAnnotations(strokes: decoded.strokes, textBoxes: decoded.textBoxes)
                }
            }

            return PDFNotebook(
                id: notebookManifest.id,
                title: notebookManifest.title,
                sourceFileURL: pdfURL,
                pages: pages.sorted(by: { $0.pageIndex < $1.pageIndex }),
                annotationsByPageIndex: annotationMap
            )
        }

        let imageURLs = manifest.assets.images.map { directoryURL.appendingPathComponent($0.file) }
        let fontURLs = manifest.assets.fonts.map { directoryURL.appendingPathComponent($0.file) }

        return NotePackage(
            manifest: manifest,
            strokeDocument: strokeDocument,
            textBoxes: textBoxes,
            notebooks: notebooks,
            imageAssetURLs: imageURLs,
            fontAssetURLs: fontURLs
        )
    }

    private func copyNotebookPDFAssets(_ notebooks: [PDFNotebook], to assetsDir: URL) throws -> [URL: NoteAssetDescriptor] {
        let pdfDir = assetsDir.appendingPathComponent("pdfs", isDirectory: true)
        try fileManager.createDirectory(at: pdfDir, withIntermediateDirectories: true)

        var map: [URL: NoteAssetDescriptor] = [:]
        for notebook in notebooks {
            let source = notebook.sourceFileURL.standardizedFileURL
            if map[source] != nil { continue }

            let ext = source.pathExtension.isEmpty ? "pdf" : source.pathExtension
            let id = UUID()
            let fileName = "\(id.uuidString).\(ext)"
            let relativePath = "assets/pdfs/\(fileName)"
            let target = pdfDir.appendingPathComponent(fileName)
            if fileManager.fileExists(atPath: target.path) {
                try fileManager.removeItem(at: target)
            }
            try fileManager.copyItem(at: source, to: target)
            let data = try Data(contentsOf: target)
            map[source] = NoteAssetDescriptor(
                id: id,
                file: relativePath,
                mediaType: "application/pdf",
                bytes: Int64(data.count),
                sha256: sha256Hex(data)
            )
        }
        return map
    }

    private func copyFileAssets(files: [URL], to destinationDir: URL, mediaTypePrefix: String) throws -> [NoteAssetDescriptor] {
        try fileManager.createDirectory(at: destinationDir, withIntermediateDirectories: true)
        var descriptors: [NoteAssetDescriptor] = []

        for source in files {
            let scoped = source.startAccessingSecurityScopedResource()
            defer {
                if scoped {
                    source.stopAccessingSecurityScopedResource()
                }
            }
            let ext = source.pathExtension.lowercased()
            let id = UUID()
            let fileName = ext.isEmpty ? id.uuidString : "\(id.uuidString).\(ext)"
            let target = destinationDir.appendingPathComponent(fileName)
            if fileManager.fileExists(atPath: target.path) {
                try fileManager.removeItem(at: target)
            }
            try fileManager.copyItem(at: source, to: target)
            let data = try Data(contentsOf: target)
            let parent = destinationDir.lastPathComponent
            let relativePath = "assets/\(parent)/\(fileName)"
            descriptors.append(
                NoteAssetDescriptor(
                    id: id,
                    file: relativePath,
                    mediaType: "\(mediaTypePrefix)\(ext.isEmpty ? "octet-stream" : ext)",
                    bytes: Int64(data.count),
                    sha256: sha256Hex(data)
                )
            )
        }

        return descriptors.sorted(by: { $0.file < $1.file })
    }

    private func writeNotebookAnnotations(
        _ notebooks: [PDFNotebook],
        pdfAssets: [URL: NoteAssetDescriptor],
        at notebookDir: URL
    ) throws -> [NoteNotebookManifest] {
        var manifests: [NoteNotebookManifest] = []
        let encoder = JSONEncoder.noteEncoder

        for notebook in notebooks {
            let source = notebook.sourceFileURL.standardizedFileURL
            guard let pdfAsset = pdfAssets[source] else {
                throw NotePackageError.invalidManifest
            }

            let thisNotebookDir = notebookDir.appendingPathComponent(notebook.id.uuidString, isDirectory: true)
            try fileManager.createDirectory(at: thisNotebookDir, withIntermediateDirectories: true)

            var pageManifests: [NoteNotebookPageManifest] = []
            for page in notebook.pages.sorted(by: { $0.pageIndex < $1.pageIndex }) {
                let annotations = notebook.annotationsByPageIndex[page.pageIndex] ?? .empty
                let hasContent = !annotations.strokes.isEmpty || !annotations.textBoxes.isEmpty
                var annotationPath: String?
                if hasContent {
                    let fileName = "page_\(page.pageIndex).json"
                    let fileURL = thisNotebookDir.appendingPathComponent(fileName)
                    let data = try encoder.encode(
                        NotePageAnnotationFile(strokes: annotations.strokes, textBoxes: annotations.textBoxes)
                    )
                    try data.write(to: fileURL, options: .atomic)
                    annotationPath = "notebooks/\(notebook.id.uuidString)/\(fileName)"
                }
                pageManifests.append(
                    NoteNotebookPageManifest(
                        pageIndex: page.pageIndex,
                        width: page.width,
                        height: page.height,
                        annotationFile: annotationPath
                    )
                )
            }
            manifests.append(
                NoteNotebookManifest(
                    id: notebook.id,
                    title: notebook.title,
                    pdfAssetID: pdfAsset.id,
                    pages: pageManifests
                )
            )
        }
        return manifests.sorted(by: { $0.title < $1.title })
    }

    private func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private extension JSONEncoder {
    static var noteEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
