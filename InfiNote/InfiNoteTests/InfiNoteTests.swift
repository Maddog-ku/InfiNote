//
//  InfiNoteTests.swift
//  InfiNoteTests
//

import Foundation
import CoreGraphics
import UIKit
import Testing
@testable import InfiNote

@MainActor
struct InfiNoteTests {
    @Test
    func strokeJSONRoundTrip() throws {
        let source = sampleDocument()
        let data = try StrokeCodec.encodeJSON(source)
        let decoded = try StrokeCodec.decodeJSON(data)
        #expect(decoded == source)
    }

    @Test
    func strokeBinaryRoundTrip() throws {
        let source = sampleDocument()
        let data = StrokeCodec.encodeBinary(source)
        let decoded = try StrokeCodec.decodeBinary(data)
        #expect(decoded == source)
    }

    @Test
    func notePackageRoundTrip() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("note-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let pdfURL = tempRoot.appendingPathComponent("sample.pdf")
        let imageURL = tempRoot.appendingPathComponent("sample.png")
        let fontURL = tempRoot.appendingPathComponent("sample.ttf")
        try Data("%PDF-1.4\n%EOF\n".utf8).write(to: pdfURL)
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: imageURL)
        try Data("fake-font".utf8).write(to: fontURL)

        let notebook = PDFNotebook(
            id: UUID(),
            title: "Sample",
            sourceFileURL: pdfURL,
            pages: [CanvasPDFPageInfo(pageIndex: 0, width: 595, height: 842)],
            annotationsByPageIndex: [
                0: CanvasPageAnnotations(
                    strokes: sampleDocument().strokes,
                    textBoxes: [sampleTextBox()]
                )
            ]
        )

        let payload = NotePackagePayload(
            strokeDocument: sampleDocument(),
            textBoxes: [sampleTextBox()],
            notebooks: [notebook],
            imageFiles: [imageURL],
            fontFiles: [fontURL]
        )

        let packageURL = tempRoot.appendingPathComponent("Sample.note", isDirectory: true)
        let store = NotePackageStore()
        let manifest = try store.writePackage(to: packageURL, payload: payload)
        #expect(manifest.schemaVersion == NoteDocumentManifest.currentSchemaVersion)

        let decoded = try store.readPackage(from: packageURL)
        #expect(decoded.strokeDocument == payload.strokeDocument)
        #expect(decoded.textBoxes == payload.textBoxes)
        #expect(decoded.notebooks.count == 1)
        #expect(decoded.imageAssetURLs.count == 1)
        #expect(decoded.fontAssetURLs.count == 1)
        #expect(decoded.manifest.quickLoad.pageCount == 1)
    }

    @Test
    func exportArtifactsRoundTrip() throws {
        let document = sampleDocument()
        let textBox = sampleTextBox()
        let worldRect = CGRect(x: -24, y: 8, width: 240, height: 120)
        let service = NoteExportService()

        let pdf = try service.exportCanvasPDF(
            strokes: document.strokes,
            textBoxes: [textBox],
            worldRect: worldRect,
            options: PDFExportOptions(
                paperSize: .letter,
                margin: UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24),
                security: nil,
                backgroundColor: .white
            ),
            fileName: "sample.pdf"
        )
        #expect(!pdf.data.isEmpty)
        #expect(pdf.fileName.hasSuffix(".pdf"))

        let png = try service.exportCanvasImage(
            strokes: document.strokes,
            textBoxes: [textBox],
            worldRect: worldRect,
            options: .png,
            baseFileName: "sample"
        )
        #expect(!png.data.isEmpty)
        #expect(png.fileName.hasSuffix(".png"))

        let jpg = try service.exportCanvasImage(
            strokes: document.strokes,
            textBoxes: [textBox],
            worldRect: worldRect,
            options: .jpg,
            baseFileName: "sample"
        )
        #expect(!jpg.data.isEmpty)
        #expect(jpg.fileName.hasSuffix(".jpg"))

        let rtf = try service.exportRTF(textBoxes: [textBox], fileName: "sample.rtf")
        #expect(!rtf.data.isEmpty)
        #expect(rtf.fileName.hasSuffix(".rtf"))
    }

    @Test
    func pdfPasswordSecurityApplied() throws {
        let result = try CanvasPDFExporter().export(
            strokes: sampleDocument().strokes,
            textBoxes: [sampleTextBox()],
            worldRect: CGRect(x: 0, y: 0, width: 300, height: 200),
            options: PDFExportOptions(
                paperSize: .content,
                margin: .zero,
                security: PDFSecurityOptions(
                    userPassword: "1234",
                    ownerPassword: "owner",
                    allowsPrinting: false,
                    allowsCopying: false
                ),
                backgroundColor: .white
            )
        )

        guard let provider = CGDataProvider(data: result.data as CFData),
              let document = CGPDFDocument(provider) else {
            Issue.record("Unable to open exported PDF")
            return
        }
        #expect(document.isEncrypted)
        #expect(!document.unlockWithPassword("wrong"))
        #expect(document.unlockWithPassword("1234"))
    }

    private func sampleDocument() -> StrokeDocument {
        let points: [StrokePoint] = [
            StrokePoint(x: -12.5, y: 40.25, time: 0.0, pressure: 0.2, azimuth: 0.4, altitude: 1.2),
            StrokePoint(x: 8.0, y: 44.0, time: 0.012, pressure: 0.5, azimuth: 0.45, altitude: 1.16),
            StrokePoint(x: 21.75, y: 49.4, time: 0.023, pressure: 0.74, azimuth: 0.5, altitude: 1.1),
        ]

        let stroke = Stroke(
            id: UUID(uuidString: "A43D6E2D-91E6-4CC3-BBF1-8EC9096A53FC") ?? UUID(),
            style: StrokeStyle(
                tool: .pen,
                color: StrokeColor(r: 30, g: 40, b: 50, a: 255),
                width: 2.4,
                opacity: 0.92
            ),
            points: points,
            bounds: StrokeBounds(points: points),
            isDeleted: false,
            erasedSpans: [StrokePointSpan(startIndex: 1, endIndex: 1)],
            createdAtMillis: 1_706_700_000_000,
            updatedAtMillis: 1_706_700_010_000,
            revision: 3
        )

        return StrokeDocument(formatVersion: StrokeDocument.currentVersion, strokes: [stroke])
    }

    private func sampleTextBox() -> CanvasTextBox {
        CanvasTextBox(
            id: UUID(uuidString: "B7437B09-7E1A-44B6-9AD4-BE398DABCEEF") ?? UUID(),
            text: "Hello",
            frame: StrokeBounds(minX: 10, minY: 12, maxX: 180, maxY: 72),
            rotation: 0,
            style: CanvasTextStyle(
                fontPostScriptName: "Helvetica",
                fontSize: 18,
                color: StrokeColor(r: 10, g: 20, b: 30, a: 255),
                lineHeightMultiple: 1.2,
                alignmentRawValue: 0
            ),
            zIndex: 1,
            isLocked: false,
            createdAtMillis: 1_706_700_000_100,
            updatedAtMillis: 1_706_700_000_100
        )
    }
}
