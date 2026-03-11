import Foundation
import PDFKit
import UIKit

enum PDFIOError: Error {
    case openFailed
    case writeFailed
}

struct PDFIOService {
    func importDocument(url: URL) throws -> PDFDocument {
        guard let document = PDFDocument(url: url) else { throw PDFIOError.openFailed }
        return document
    }

    func exportSinglePage(to url: URL, pageRect: CGRect, draw: (CGContext) -> Void) throws {
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        do {
            try renderer.writePDF(to: url) { context in
                context.beginPage()
                draw(context.cgContext)
            }
        } catch {
            throw PDFIOError.writeFailed
        }
    }
}
