//
//  InfiNoteTests.swift
//  InfiNoteTests
//

import Foundation
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
}
