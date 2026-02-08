//
//  NotebookThumbnailService.swift
//  InfiNote
//

import Foundation
import UIKit
import CoreGraphics

@MainActor
final class NotebookThumbnailService {
    static let shared = NotebookThumbnailService()

    private let fileManager = FileManager.default
    private let memoryCache = NSCache<NSString, UIImage>()

    private init() {
        memoryCache.countLimit = 200
        memoryCache.totalCostLimit = 80 * 1024 * 1024
    }

    func thumbnail(for notebook: NotebookRecord, targetSize: CGSize, scale: CGFloat = 2) async -> UIImage {
        let normalizedSize = CGSize(width: max(80, targetSize.width), height: max(80, targetSize.height))
        let key = cacheKey(for: notebook, size: normalizedSize, scale: scale)

        if let cached = memoryCache.object(forKey: key as NSString) {
            return cached
        }
        if let disk = loadFromDisk(cacheKey: key) {
            memoryCache.setObject(disk, forKey: key as NSString, cost: estimatedCost(of: disk))
            return disk
        }

        let image = renderThumbnail(for: notebook, size: normalizedSize, scale: scale)
        memoryCache.setObject(image, forKey: key as NSString, cost: estimatedCost(of: image))
        saveToDisk(image: image, cacheKey: key)
        return image
    }

    private func renderThumbnail(for notebook: NotebookRecord, size: CGSize, scale: CGFloat) -> UIImage {
        if let pdfURL = localPDFURL(fileName: notebook.sourcePDFFileName),
           let image = renderPDFThumbnail(url: pdfURL, size: size, scale: scale) {
            return image
        }
        return renderTemplateThumbnail(for: notebook, size: size, scale: scale)
    }

    private func renderPDFThumbnail(url: URL, size: CGSize, scale: CGFloat) -> UIImage? {
        guard let document = CGPDFDocument(url as CFURL),
              let page = document.page(at: 1) else {
            return nil
        }
        let mediaBox = page.getBoxRect(.mediaBox)
        guard mediaBox.width > 0, mediaBox.height > 0 else { return nil }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        return renderer.image { _ in
            guard let cg = UIGraphicsGetCurrentContext() else { return }
            cg.setFillColor(UIColor.white.cgColor)
            cg.fill(CGRect(origin: .zero, size: size))

            let inset: CGFloat = 8
            let targetRect = CGRect(x: inset, y: inset, width: size.width - inset * 2, height: size.height - inset * 2)
            let factor = min(targetRect.width / mediaBox.width, targetRect.height / mediaBox.height)
            let drawSize = CGSize(width: mediaBox.width * factor, height: mediaBox.height * factor)
            let drawOrigin = CGPoint(
                x: targetRect.midX - drawSize.width * 0.5,
                y: targetRect.midY - drawSize.height * 0.5
            )
            let drawRect = CGRect(origin: drawOrigin, size: drawSize)

            cg.setFillColor(UIColor.white.cgColor)
            cg.fill(drawRect)
            cg.setStrokeColor(UIColor.systemGray5.cgColor)
            cg.stroke(drawRect)

            cg.saveGState()
            cg.translateBy(x: drawRect.minX, y: drawRect.minY + drawRect.height)
            cg.scaleBy(x: drawRect.width / mediaBox.width, y: -drawRect.height / mediaBox.height)
            cg.drawPDFPage(page)
            cg.restoreGState()
        }
    }

    private func renderTemplateThumbnail(for notebook: NotebookRecord, size: CGSize, scale: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        return renderer.image { _ in
            guard let cg = UIGraphicsGetCurrentContext() else { return }
            cg.setFillColor(UIColor.white.cgColor)
            cg.fill(CGRect(origin: .zero, size: size))

            drawTemplateBackground(template: notebook.template, in: cg, size: size)
            drawNotebookBadge(in: cg, size: size, title: notebook.title)
        }
    }

    private func drawTemplateBackground(template: NotebookTemplate, in context: CGContext, size: CGSize) {
        let insetRect = CGRect(x: 6, y: 6, width: size.width - 12, height: size.height - 12)
        context.setStrokeColor(UIColor.systemGray5.cgColor)
        context.stroke(insetRect)

        switch template {
        case .blank:
            return
        case .lined:
            context.setStrokeColor(UIColor.systemGray5.cgColor)
            context.setLineWidth(1)
            var y: CGFloat = 20
            while y < size.height - 12 {
                context.move(to: CGPoint(x: 10, y: y))
                context.addLine(to: CGPoint(x: size.width - 10, y: y))
                y += 14
            }
            context.strokePath()
        case .grid:
            context.setStrokeColor(UIColor.systemGray5.cgColor)
            context.setLineWidth(1)
            var x: CGFloat = 18
            while x < size.width - 12 {
                context.move(to: CGPoint(x: x, y: 10))
                context.addLine(to: CGPoint(x: x, y: size.height - 10))
                x += 14
            }
            var y: CGFloat = 18
            while y < size.height - 12 {
                context.move(to: CGPoint(x: 10, y: y))
                context.addLine(to: CGPoint(x: size.width - 10, y: y))
                y += 14
            }
            context.strokePath()
        case .dotted:
            context.setFillColor(UIColor.systemGray4.cgColor)
            var x: CGFloat = 16
            while x < size.width - 10 {
                var y: CGFloat = 16
                while y < size.height - 10 {
                    context.fillEllipse(in: CGRect(x: x - 1, y: y - 1, width: 2, height: 2))
                    y += 14
                }
                x += 14
            }
        }
    }

    private func drawNotebookBadge(in context: CGContext, size: CGSize, title: String) {
        let badgeRect = CGRect(x: 10, y: size.height - 38, width: size.width - 20, height: 26)
        context.setFillColor(UIColor.black.withAlphaComponent(0.55).cgColor)
        context.fill(badgeRect)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: UIColor.white
        ]
        let shortened = title.count > 22 ? String(title.prefix(22)) + "…" : title
        (shortened as NSString).draw(in: badgeRect.insetBy(dx: 6, dy: 5), withAttributes: attributes)
    }

    private func cacheKey(for notebook: NotebookRecord, size: CGSize, scale: CGFloat) -> String {
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        let scaled = Int((scale * 100).rounded())
        return "\(notebook.thumbnailKey)-\(width)x\(height)-s\(scaled)"
    }

    private func cacheDirectory() throws -> URL {
        guard let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            throw HomeLibraryError.appSupportUnavailable
        }
        let folder = caches.appendingPathComponent("NotebookThumbs", isDirectory: true)
        if !fileManager.fileExists(atPath: folder.path) {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder
    }

    private func diskPath(for cacheKey: String) -> URL? {
        guard let folder = try? cacheDirectory() else { return nil }
        return folder.appendingPathComponent("\(cacheKey).png")
    }

    private func loadFromDisk(cacheKey: String) -> UIImage? {
        guard let path = diskPath(for: cacheKey),
              fileManager.fileExists(atPath: path.path),
              let data = try? Data(contentsOf: path) else {
            return nil
        }
        return UIImage(data: data)
    }

    private func saveToDisk(image: UIImage, cacheKey: String) {
        guard let path = diskPath(for: cacheKey),
              let data = image.pngData() else {
            return
        }
        try? data.write(to: path, options: .atomic)
    }

    private func localPDFURL(fileName: String?) -> URL? {
        guard let fileName, !fileName.isEmpty else { return nil }
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let url = appSupport
            .appendingPathComponent("PDFNotebooks", isDirectory: true)
            .appendingPathComponent(fileName)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    private func estimatedCost(of image: UIImage) -> Int {
        guard let cg = image.cgImage else { return 1 }
        return cg.bytesPerRow * cg.height
    }
}
