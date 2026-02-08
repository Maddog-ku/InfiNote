//
//  PDFImportService.swift
//  InfiNote
//

import Foundation
import CoreGraphics

enum PDFImportError: Error {
    case appSupportUnavailable
    case copyFailed(URL)
    case openFailed(URL)
}

struct PDFImportService {
    func importPDFs(urls: [URL]) throws -> [PDFNotebook] {
        let notebooksFolder = try notebooksDirectory()
        var imported: [PDFNotebook] = []

        for sourceURL in urls {
            let scoped = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if scoped {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            guard sourceURL.pathExtension.lowercased() == "pdf" else { continue }
            let targetURL = notebooksFolder.appendingPathComponent(sourceURL.lastPathComponent)
            if FileManager.default.fileExists(atPath: targetURL.path) {
                try? FileManager.default.removeItem(at: targetURL)
            }
            do {
                try FileManager.default.copyItem(at: sourceURL, to: targetURL)
            } catch {
                throw PDFImportError.copyFailed(sourceURL)
            }

            guard let document = CGPDFDocument(targetURL as CFURL) else {
                throw PDFImportError.openFailed(targetURL)
            }

            var pages: [CanvasPDFPageInfo] = []
            pages.reserveCapacity(document.numberOfPages)
            for pageNumber in 1...document.numberOfPages {
                guard let page = document.page(at: pageNumber) else { continue }
                let media = page.getBoxRect(.mediaBox)
                pages.append(
                    CanvasPDFPageInfo(
                        pageIndex: pageNumber - 1,
                        width: max(1, media.width),
                        height: max(1, media.height)
                    )
                )
            }
            let notebook = PDFNotebook(
                id: UUID(),
                title: targetURL.deletingPathExtension().lastPathComponent,
                sourceFileURL: targetURL,
                pages: pages,
                annotationsByPageIndex: [:]
            )
            imported.append(notebook)
        }
        return imported
    }

    private func notebooksDirectory() throws -> URL {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw PDFImportError.appSupportUnavailable
        }
        let folder = appSupport.appendingPathComponent("PDFNotebooks", isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder
    }
}
