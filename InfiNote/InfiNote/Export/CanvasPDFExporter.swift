//
//  CanvasPDFExporter.swift
//  InfiNote
//

import Foundation
import UIKit
import CoreGraphics
import UniformTypeIdentifiers

enum ExportError: Error {
    case emptyContent
    case invalidCanvasSize
    case renderFailed
    case passwordRequired
    case encryptedPDFBuildFailed
    case unsupportedImageFormat
    case invalidRTF
}

enum PDFPaperSize: Hashable {
    case content
    case a4
    case letter
    case legal
    case custom(CGSize)

    func pageSize(for contentSize: CGSize) -> CGSize {
        switch self {
        case .content:
            return CGSize(width: max(1, contentSize.width), height: max(1, contentSize.height))
        case .a4:
            return CGSize(width: 595.276, height: 841.89)
        case .letter:
            return CGSize(width: 612, height: 792)
        case .legal:
            return CGSize(width: 612, height: 1008)
        case let .custom(size):
            return CGSize(width: max(1, size.width), height: max(1, size.height))
        }
    }
}

struct PDFSecurityOptions: Hashable {
    var userPassword: String
    var ownerPassword: String?
    var allowsPrinting: Bool
    var allowsCopying: Bool

    init(
        userPassword: String,
        ownerPassword: String? = nil,
        allowsPrinting: Bool = true,
        allowsCopying: Bool = true
    ) {
        self.userPassword = userPassword
        self.ownerPassword = ownerPassword
        self.allowsPrinting = allowsPrinting
        self.allowsCopying = allowsCopying
    }
}

struct PDFExportOptions {
    var paperSize: PDFPaperSize
    var margin: UIEdgeInsets
    var security: PDFSecurityOptions?
    var backgroundColor: UIColor

    static let `default` = PDFExportOptions(
        paperSize: .content,
        margin: .zero,
        security: nil,
        backgroundColor: .systemBackground
    )
}

enum ImageExportFormat: Hashable {
    case png
    case jpg(quality: CGFloat)

    var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpg: return "jpg"
        }
    }
}

struct ImageExportOptions: Hashable {
    var format: ImageExportFormat
    var scale: CGFloat
    var margin: CGFloat
    var backgroundColor: UIColor

    static let png = ImageExportOptions(
        format: .png,
        scale: 2,
        margin: 24,
        backgroundColor: .systemBackground
    )

    static let jpg = ImageExportOptions(
        format: .jpg(quality: 0.9),
        scale: 2,
        margin: 24,
        backgroundColor: .systemBackground
    )
}

struct RTFExportOptions: Hashable {
    var lineSeparator: String

    static let `default` = RTFExportOptions(lineSeparator: "\n\n")
}

struct ExportArtifact {
    var fileName: String
    var contentType: UTType
    var data: Data
}

struct CanvasPDFExportResult {
    var data: Data
    var missingFontPostScriptNames: [String]
}

struct CanvasPDFExporter {
    func export(
        strokes: [CanvasStroke],
        textBoxes: [CanvasTextBox],
        worldRect: CGRect,
        options: PDFExportOptions = .default
    ) throws -> CanvasPDFExportResult {
        guard !worldRect.isNull, worldRect.width.isFinite, worldRect.height.isFinite else {
            throw ExportError.invalidCanvasSize
        }
        let contentRect = CGRect(
            x: worldRect.minX,
            y: worldRect.minY,
            width: max(1, worldRect.width),
            height: max(1, worldRect.height)
        )
        let pageSize = options.paperSize.pageSize(for: contentRect.size)
        let pageBounds = CGRect(origin: .zero, size: pageSize)
        let safeMargin = options.margin.clampedNonNegative
        let drawable = pageBounds.inset(by: safeMargin)
        guard drawable.width > 1, drawable.height > 1 else {
            throw ExportError.invalidCanvasSize
        }
        let scale = min(drawable.width / contentRect.width, drawable.height / contentRect.height)
        let drawOrigin = CGPoint(
            x: drawable.midX - contentRect.width * scale * 0.5,
            y: drawable.midY - contentRect.height * scale * 0.5
        )

        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)

        var missingFonts = Set<String>()
        var data = renderer.pdfData { context in
            context.beginPage()
            guard let cg = UIGraphicsGetCurrentContext() else { return }

            cg.setFillColor(options.backgroundColor.cgColor)
            cg.fill(pageBounds)

            for stroke in strokes where !stroke.isDeleted {
                BrushRenderer.drawStroke(
                    stroke,
                    in: cg,
                    toView: { point in
                        CGPoint(
                            x: drawOrigin.x + (point.x - contentRect.minX) * scale,
                            y: drawOrigin.y + (point.y - contentRect.minY) * scale
                        )
                    },
                    predicted: false,
                    cameraScale: scale
                )
            }

            for box in textBoxes.sorted(by: { $0.zIndex < $1.zIndex }) {
                let frame = box.frame.cgRect
                let drawRect = CGRect(
                    x: drawOrigin.x + (frame.minX - contentRect.minX) * scale,
                    y: drawOrigin.y + (frame.minY - contentRect.minY) * scale,
                    width: frame.width * scale,
                    height: frame.height * scale
                )
                let targetFontSize = CGFloat(box.style.fontSize) * scale
                let font = FontRegistry.shared.uiFont(
                    postScriptName: box.style.fontPostScriptName,
                    size: targetFontSize
                ) ?? UIFont.systemFont(ofSize: targetFontSize)
                if font.fontName != box.style.fontPostScriptName {
                    missingFonts.insert(box.style.fontPostScriptName)
                }
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = NSTextAlignment(rawValue: box.style.alignmentRawValue) ?? .left
                paragraph.lineHeightMultiple = CGFloat(box.style.lineHeightMultiple)

                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: box.style.color.uiColor,
                    .paragraphStyle: paragraph
                ]
                (box.text as NSString).draw(in: drawRect.insetBy(dx: 6, dy: 4), withAttributes: attrs)
            }
        }
        data = try PDFSecurityProcessor.encrypt(data: data, options: options.security)
        return CanvasPDFExportResult(data: data, missingFontPostScriptNames: Array(missingFonts).sorted())
    }
}

struct CanvasImageExportResult {
    var data: Data
    var missingFontPostScriptNames: [String]
}

struct CanvasImageExporter {
    func export(
        strokes: [CanvasStroke],
        textBoxes: [CanvasTextBox],
        worldRect: CGRect,
        options: ImageExportOptions
    ) throws -> CanvasImageExportResult {
        guard !worldRect.isNull, worldRect.width.isFinite, worldRect.height.isFinite else {
            throw ExportError.invalidCanvasSize
        }
        let contentRect = CGRect(
            x: worldRect.minX,
            y: worldRect.minY,
            width: max(1, worldRect.width),
            height: max(1, worldRect.height)
        )
        let imageBounds = CGRect(
            x: 0,
            y: 0,
            width: contentRect.width + max(0, options.margin * 2),
            height: contentRect.height + max(0, options.margin * 2)
        )
        guard imageBounds.width > 1, imageBounds.height > 1 else {
            throw ExportError.invalidCanvasSize
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = max(1, options.scale)
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: imageBounds.size, format: format)

        var missingFonts = Set<String>()
        let image = renderer.image { _ in
            guard let cg = UIGraphicsGetCurrentContext() else { return }
            cg.setFillColor(options.backgroundColor.cgColor)
            cg.fill(imageBounds)

            for stroke in strokes where !stroke.isDeleted {
                BrushRenderer.drawStroke(
                    stroke,
                    in: cg,
                    toView: { point in
                        CGPoint(
                            x: options.margin + (point.x - contentRect.minX),
                            y: options.margin + (point.y - contentRect.minY)
                        )
                    },
                    predicted: false,
                    cameraScale: 1
                )
            }

            for box in textBoxes.sorted(by: { $0.zIndex < $1.zIndex }) {
                let frame = box.frame.cgRect
                let drawRect = CGRect(
                    x: options.margin + (frame.minX - contentRect.minX),
                    y: options.margin + (frame.minY - contentRect.minY),
                    width: frame.width,
                    height: frame.height
                )
                let targetFontSize = CGFloat(box.style.fontSize)
                let font = FontRegistry.shared.uiFont(
                    postScriptName: box.style.fontPostScriptName,
                    size: targetFontSize
                ) ?? UIFont.systemFont(ofSize: targetFontSize)
                if font.fontName != box.style.fontPostScriptName {
                    missingFonts.insert(box.style.fontPostScriptName)
                }
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = NSTextAlignment(rawValue: box.style.alignmentRawValue) ?? .left
                paragraph.lineHeightMultiple = CGFloat(box.style.lineHeightMultiple)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: box.style.color.uiColor,
                    .paragraphStyle: paragraph
                ]
                (box.text as NSString).draw(in: drawRect.insetBy(dx: 6, dy: 4), withAttributes: attrs)
            }
        }

        let data: Data?
        switch options.format {
        case .png:
            data = image.pngData()
        case let .jpg(quality):
            data = image.jpegData(compressionQuality: max(0, min(1, quality)))
        }
        guard let data else {
            throw ExportError.unsupportedImageFormat
        }
        return CanvasImageExportResult(data: data, missingFontPostScriptNames: Array(missingFonts).sorted())
    }
}

struct TextRTFExporter {
    func export(textBoxes: [CanvasTextBox], options: RTFExportOptions = .default) throws -> Data {
        let sorted = textBoxes.sorted { lhs, rhs in
            if lhs.zIndex != rhs.zIndex { return lhs.zIndex < rhs.zIndex }
            return lhs.createdAtMillis < rhs.createdAtMillis
        }
        let output = NSMutableAttributedString()

        for (index, box) in sorted.enumerated() where !box.text.isEmpty {
            let font = FontRegistry.shared.uiFont(
                postScriptName: box.style.fontPostScriptName,
                size: CGFloat(box.style.fontSize)
            ) ?? UIFont.systemFont(ofSize: CGFloat(box.style.fontSize))
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = NSTextAlignment(rawValue: box.style.alignmentRawValue) ?? .left
            paragraph.lineHeightMultiple = CGFloat(box.style.lineHeightMultiple)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: box.style.color.uiColor,
                .paragraphStyle: paragraph
            ]
            output.append(NSAttributedString(string: box.text, attributes: attrs))
            if index < sorted.count - 1 {
                output.append(NSAttributedString(string: options.lineSeparator))
            }
        }

        let fullRange = NSRange(location: 0, length: output.length)
        let data = try output.data(
            from: fullRange,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        guard !data.isEmpty else { throw ExportError.invalidRTF }
        return data
    }
}

struct NoteExportService {
    func exportCanvasPDF(
        strokes: [CanvasStroke],
        textBoxes: [CanvasTextBox],
        worldRect: CGRect,
        options: PDFExportOptions = .default,
        fileName: String = "InfiNote.pdf"
    ) throws -> ExportArtifact {
        let result = try CanvasPDFExporter().export(
            strokes: strokes,
            textBoxes: textBoxes,
            worldRect: worldRect,
            options: options
        )
        _ = result.missingFontPostScriptNames
        return ExportArtifact(fileName: sanitizeFileName(fileName, fallbackExt: "pdf"), contentType: .pdf, data: result.data)
    }

    func exportCanvasImage(
        strokes: [CanvasStroke],
        textBoxes: [CanvasTextBox],
        worldRect: CGRect,
        options: ImageExportOptions,
        baseFileName: String = "InfiNote"
    ) throws -> ExportArtifact {
        let result = try CanvasImageExporter().export(
            strokes: strokes,
            textBoxes: textBoxes,
            worldRect: worldRect,
            options: options
        )
        _ = result.missingFontPostScriptNames
        let ext = options.format.fileExtension
        let fileName = sanitizeFileName("\(baseFileName).\(ext)", fallbackExt: ext)
        let contentType: UTType = (ext == "png") ? .png : .jpeg
        return ExportArtifact(fileName: fileName, contentType: contentType, data: result.data)
    }

    func exportRTF(
        textBoxes: [CanvasTextBox],
        options: RTFExportOptions = .default,
        fileName: String = "InfiNote.rtf"
    ) throws -> ExportArtifact {
        let data = try TextRTFExporter().export(textBoxes: textBoxes, options: options)
        return ExportArtifact(fileName: sanitizeFileName(fileName, fallbackExt: "rtf"), contentType: .rtf, data: data)
    }

    func exportNotebookPDF(
        notebook: PDFNotebook,
        options: PDFExportOptions = .default,
        fileName: String? = nil
    ) throws -> ExportArtifact {
        let result = try PDFNotebookExporter().export(notebook: notebook, options: options)
        _ = result.missingFontPostScriptNames
        let exportName = fileName ?? "\(notebook.title).pdf"
        return ExportArtifact(fileName: sanitizeFileName(exportName, fallbackExt: "pdf"), contentType: .pdf, data: result.data)
    }

    func writeToTemporaryFile(_ artifact: ExportArtifact) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(artifact.fileName)
        try artifact.data.write(to: url, options: .atomic)
        return url
    }

    private func sanitizeFileName(_ name: String, fallbackExt: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "InfiNote.\(fallbackExt)" }
        return trimmed
    }
}

enum ExportInteractionController {
    static func presentShareSheet(
        items: [Any],
        from presenter: UIViewController,
        sourceView: UIView? = nil
    ) {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            popover.sourceView = sourceView ?? presenter.view
            popover.sourceRect = sourceView?.bounds ?? CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
        }
        presenter.present(controller, animated: true)
    }

    static func printPDF(_ data: Data, jobName: String = "InfiNote") {
        guard UIPrintInteractionController.isPrintingAvailable else { return }
        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.outputType = .general
        printInfo.jobName = jobName

        let controller = UIPrintInteractionController.shared
        controller.printInfo = printInfo
        controller.printingItem = data
        controller.present(animated: true, completionHandler: nil)
    }

    static func printImage(_ image: UIImage, jobName: String = "InfiNote") {
        guard UIPrintInteractionController.isPrintingAvailable else { return }
        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.outputType = .photo
        printInfo.jobName = jobName

        let controller = UIPrintInteractionController.shared
        controller.printInfo = printInfo
        controller.printingItem = image
        controller.present(animated: true, completionHandler: nil)
    }
}

enum PDFSecurityProcessor {
    static func encrypt(data: Data, options: PDFSecurityOptions?) throws -> Data {
        guard let options else { return data }
        guard !options.userPassword.isEmpty else { throw ExportError.passwordRequired }

        guard let provider = CGDataProvider(data: data as CFData),
              let source = CGPDFDocument(provider) else {
            throw ExportError.encryptedPDFBuildFailed
        }
        let pageCount = source.numberOfPages
        guard pageCount > 0 else { return data }
        guard let firstPage = source.page(at: 1) else {
            throw ExportError.encryptedPDFBuildFailed
        }

        let encryptedData = NSMutableData()
        guard let consumer = CGDataConsumer(data: encryptedData as CFMutableData) else {
            throw ExportError.encryptedPDFBuildFailed
        }
        var firstMediaBox = firstPage.getBoxRect(.mediaBox)
        let ownerPassword = options.ownerPassword ?? options.userPassword
        let aux: [CFString: Any] = [
            kCGPDFContextUserPassword: options.userPassword,
            kCGPDFContextOwnerPassword: ownerPassword,
            kCGPDFContextAllowsPrinting: options.allowsPrinting,
            kCGPDFContextAllowsCopying: options.allowsCopying
        ]
        guard let context = CGContext(
            consumer: consumer,
            mediaBox: &firstMediaBox,
            aux as CFDictionary
        ) else {
            throw ExportError.encryptedPDFBuildFailed
        }

        for pageNumber in 1...pageCount {
            guard let page = source.page(at: pageNumber) else { continue }
            var mediaBox = page.getBoxRect(.mediaBox)
            context.beginPDFPage([
                kCGPDFContextMediaBox: Data(bytes: &mediaBox, count: MemoryLayout<CGRect>.size)
            ] as CFDictionary)
            context.drawPDFPage(page)
            context.endPDFPage()
        }
        context.closePDF()
        return encryptedData as Data
    }
}

extension UIEdgeInsets {
    var clampedNonNegative: UIEdgeInsets {
        UIEdgeInsets(
            top: max(0, top),
            left: max(0, left),
            bottom: max(0, bottom),
            right: max(0, right)
        )
    }
}
