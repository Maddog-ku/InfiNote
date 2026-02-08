//
//  PDFNotebookExporter.swift
//  InfiNote
//

import Foundation
import UIKit
import CoreGraphics

struct PDFNotebookExportResult {
    var data: Data
    var missingFontPostScriptNames: [String]
}

enum PDFNotebookExportError: Error {
    case openSourceFailed(URL)
}

struct PDFNotebookExporter {
    func export(notebook: PDFNotebook, options: PDFExportOptions = .default) throws -> PDFNotebookExportResult {
        guard let sourceDoc = CGPDFDocument(notebook.sourceFileURL as CFURL) else {
            throw PDFNotebookExportError.openSourceFailed(notebook.sourceFileURL)
        }

        // Start with first page size if exists.
        let firstPage = notebook.pages.first
        let defaultBounds = CGRect(
            x: 0,
            y: 0,
            width: firstPage?.width ?? 1024,
            height: firstPage?.height ?? 768
        )
        let renderer = UIGraphicsPDFRenderer(bounds: defaultBounds)
        var missingFonts = Set<String>()

        var data = renderer.pdfData { context in
            for pageInfo in notebook.pages {
                let sourcePageBounds = CGRect(x: 0, y: 0, width: pageInfo.width, height: pageInfo.height)
                let pageSize = options.paperSize.pageSize(for: sourcePageBounds.size)
                let pageBounds = CGRect(origin: .zero, size: pageSize)
                let safeMargin = options.margin.clampedNonNegative
                let drawable = pageBounds.inset(by: safeMargin)
                let renderScale = min(
                    max(0.0001, drawable.width) / max(1, sourcePageBounds.width),
                    max(0.0001, drawable.height) / max(1, sourcePageBounds.height)
                )
                let drawOrigin = CGPoint(
                    x: drawable.midX - sourcePageBounds.width * renderScale * 0.5,
                    y: drawable.midY - sourcePageBounds.height * renderScale * 0.5
                )

                context.beginPage(withBounds: pageBounds, pageInfo: [:])
                guard let cg = UIGraphicsGetCurrentContext() else { continue }
                cg.setFillColor(options.backgroundColor.cgColor)
                cg.fill(pageBounds)

                if let sourcePage = sourceDoc.page(at: pageInfo.pageIndex + 1) {
                    // CGPDF uses bottom-left coordinates.
                    cg.saveGState()
                    cg.translateBy(x: drawOrigin.x, y: drawOrigin.y)
                    cg.scaleBy(x: renderScale, y: renderScale)
                    cg.translateBy(x: 0, y: sourcePageBounds.height)
                    cg.scaleBy(x: 1, y: -1)
                    cg.drawPDFPage(sourcePage)
                    cg.restoreGState()
                }

                let annotations = notebook.annotationsByPageIndex[pageInfo.pageIndex] ?? .empty
                for stroke in annotations.strokes where !stroke.isDeleted {
                    BrushRenderer.drawStroke(
                        stroke,
                        in: cg,
                        toView: { point in
                            CGPoint(
                                x: drawOrigin.x + point.x * renderScale,
                                y: drawOrigin.y + point.y * renderScale
                            )
                        },
                        predicted: false,
                        cameraScale: renderScale
                    )
                }
                for box in annotations.textBoxes.sorted(by: { $0.zIndex < $1.zIndex }) {
                    let font = FontRegistry.shared.uiFont(
                        postScriptName: box.style.fontPostScriptName,
                        size: CGFloat(box.style.fontSize) * renderScale
                    ) ?? UIFont.systemFont(ofSize: CGFloat(box.style.fontSize) * renderScale)
                    if font.fontName != box.style.fontPostScriptName {
                        missingFonts.insert(box.style.fontPostScriptName)
                    }
                    let paragraph = NSMutableParagraphStyle()
                    paragraph.alignment = NSTextAlignment(rawValue: box.style.alignmentRawValue) ?? .left
                    paragraph.lineHeightMultiple = CGFloat(box.style.lineHeightMultiple)
                    let sourceFrame = box.frame.cgRect
                    let drawFrame = CGRect(
                        x: drawOrigin.x + sourceFrame.minX * renderScale,
                        y: drawOrigin.y + sourceFrame.minY * renderScale,
                        width: sourceFrame.width * renderScale,
                        height: sourceFrame.height * renderScale
                    )
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: font,
                        .foregroundColor: box.style.color.uiColor,
                        .paragraphStyle: paragraph
                    ]
                    (box.text as NSString).draw(
                        in: drawFrame.insetBy(dx: 6 * renderScale, dy: 4 * renderScale),
                        withAttributes: attrs
                    )
                }
            }
        }
        data = try PDFSecurityProcessor.encrypt(data: data, options: options.security)

        return PDFNotebookExportResult(
            data: data,
            missingFontPostScriptNames: Array(missingFonts).sorted()
        )
    }
}
