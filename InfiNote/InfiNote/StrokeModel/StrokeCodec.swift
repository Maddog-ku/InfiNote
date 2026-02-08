//
//  StrokeCodec.swift
//  InfiNote
//

import Foundation

enum StrokeCodecError: Error {
    case invalidHeader
    case unsupportedVersion(UInt16)
    case truncatedData
}

enum StrokeCodec {
    private static let magic: [UInt8] = [0x49, 0x4E, 0x46, 0x53] // "INFS"
    private static let binaryVersion: UInt16 = 1

    static func encodeJSON(_ document: StrokeDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return try encoder.encode(document)
    }

    static func decodeJSON(_ data: Data) throws -> StrokeDocument {
        try JSONDecoder().decode(StrokeDocument.self, from: data)
    }

    static func encodeBinary(_ document: StrokeDocument) -> Data {
        var writer = BinaryWriter()
        writer.append(bytes: magic)
        writer.append(binaryVersion)
        writer.append(document.formatVersion)
        writer.append(UInt32(document.strokes.count))

        for stroke in document.strokes {
            writer.append(stroke.id)
            writer.append(stroke.style.tool.rawValue)
            writer.append(stroke.style.color.r)
            writer.append(stroke.style.color.g)
            writer.append(stroke.style.color.b)
            writer.append(stroke.style.color.a)
            writer.append(stroke.style.width)
            writer.append(stroke.style.opacity)
            writer.append(stroke.bounds.minX)
            writer.append(stroke.bounds.minY)
            writer.append(stroke.bounds.maxX)
            writer.append(stroke.bounds.maxY)
            writer.append(stroke.createdAtMillis)
            writer.append(stroke.updatedAtMillis)
            writer.append(stroke.revision)
            writer.append(stroke.isDeleted ? UInt8(1) : UInt8(0))

            writer.append(UInt32(stroke.erasedSpans.count))
            for span in stroke.erasedSpans {
                writer.append(span.startIndex)
                writer.append(span.endIndex)
            }

            writer.append(UInt32(stroke.points.count))
            for point in stroke.points {
                writer.append(point.x)
                writer.append(point.y)
                writer.append(point.time)
                writer.append(point.pressure)
                writer.append(point.azimuth)
                writer.append(point.altitude)
            }
        }

        return writer.data
    }

    static func decodeBinary(_ data: Data) throws -> StrokeDocument {
        var reader = BinaryReader(data: data)
        guard reader.readBytes(count: 4) == magic else {
            throw StrokeCodecError.invalidHeader
        }

        let storageVersion: UInt16 = try reader.read()
        guard storageVersion == binaryVersion else {
            throw StrokeCodecError.unsupportedVersion(storageVersion)
        }

        let formatVersion: UInt16 = try reader.read()
        let strokeCount: UInt32 = try reader.read()

        var strokes: [Stroke] = []
        strokes.reserveCapacity(Int(strokeCount))

        for _ in 0..<strokeCount {
            let id = try reader.readUUID()
            let toolRaw: UInt8 = try reader.read()
            let tool = InkTool(rawValue: toolRaw) ?? .pen

            let style = StrokeStyle(
                tool: tool,
                color: StrokeColor(
                    r: try reader.read(),
                    g: try reader.read(),
                    b: try reader.read(),
                    a: try reader.read()
                ),
                width: try reader.read(),
                opacity: try reader.read()
            )

            let bounds = StrokeBounds(
                minX: try reader.read(),
                minY: try reader.read(),
                maxX: try reader.read(),
                maxY: try reader.read()
            )

            let createdAtMillis: Int64 = try reader.read()
            let updatedAtMillis: Int64 = try reader.read()
            let revision: Int32 = try reader.read()
            let isDeleted: UInt8 = try reader.read()

            let erasedCount: UInt32 = try reader.read()
            var erasedSpans: [StrokePointSpan] = []
            erasedSpans.reserveCapacity(Int(erasedCount))
            for _ in 0..<erasedCount {
                erasedSpans.append(
                    StrokePointSpan(
                        startIndex: try reader.read(),
                        endIndex: try reader.read()
                    )
                )
            }

            let pointCount: UInt32 = try reader.read()
            var points: [StrokePoint] = []
            points.reserveCapacity(Int(pointCount))

            for _ in 0..<pointCount {
                points.append(
                    StrokePoint(
                        x: try reader.read(),
                        y: try reader.read(),
                        time: try reader.read(),
                        pressure: try reader.read(),
                        azimuth: try reader.read(),
                        altitude: try reader.read()
                    )
                )
            }

            strokes.append(
                Stroke(
                    id: id,
                    style: style,
                    points: points,
                    bounds: bounds,
                    isDeleted: isDeleted == 1,
                    erasedSpans: erasedSpans,
                    createdAtMillis: createdAtMillis,
                    updatedAtMillis: updatedAtMillis,
                    revision: revision
                )
            )
        }

        return StrokeDocument(formatVersion: formatVersion, strokes: strokes)
    }
}

private struct BinaryWriter {
    var data = Data()

    mutating func append(bytes: [UInt8]) {
        data.append(contentsOf: bytes)
    }

    mutating func append<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { rawBuffer in
            data.append(contentsOf: rawBuffer)
        }
    }

    mutating func append(_ value: Float) {
        append(value.bitPattern)
    }

    mutating func append(_ value: UUID) {
        var uuid = value.uuid
        withUnsafeBytes(of: &uuid) { rawBuffer in
            data.append(contentsOf: rawBuffer)
        }
    }
}

private struct BinaryReader {
    let data: Data
    var offset: Int = 0

    mutating func readBytes(count: Int) -> [UInt8] {
        guard offset + count <= data.count else { return [] }
        defer { offset += count }
        return Array(data[offset..<(offset + count)])
    }

    mutating func read<T: FixedWidthInteger>() throws -> T {
        let size = MemoryLayout<T>.size
        guard offset + size <= data.count else { throw StrokeCodecError.truncatedData }
        let value: T = data.withUnsafeBytes { rawBuffer in
            rawBuffer.loadUnaligned(fromByteOffset: offset, as: T.self)
        }
        offset += size
        return T(littleEndian: value)
    }

    mutating func read() throws -> Float {
        let bits: UInt32 = try read()
        return Float(bitPattern: bits)
    }

    mutating func readUUID() throws -> UUID {
        let bytes = readBytes(count: 16)
        guard bytes.count == 16 else { throw StrokeCodecError.truncatedData }

        var tuple: uuid_t = (
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0
        )
        withUnsafeMutableBytes(of: &tuple) { rawBuffer in
            rawBuffer.copyBytes(from: bytes)
        }
        return UUID(uuid: tuple)
    }
}
