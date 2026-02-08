//
//  StrokeModels.swift
//  InfiNote
//

import Foundation

#if canImport(CoreGraphics)
import CoreGraphics
#endif

enum InkTool: UInt8, Codable, CaseIterable {
    case pen = 0
    case pencil = 1
    case highlighter = 2
}

struct StrokeColor: Codable, Hashable {
    var r: UInt8
    var g: UInt8
    var b: UInt8
    var a: UInt8

    static let black = StrokeColor(r: 0, g: 0, b: 0, a: 255)
}

struct StrokeStyle: Codable, Hashable {
    var tool: InkTool
    var color: StrokeColor
    var width: Float
    var opacity: Float
}

struct StrokePoint: Codable, Hashable {
    var x: Float
    var y: Float
    var time: Float
    var pressure: Float
    var azimuth: Float
    var altitude: Float
}

struct StrokeBounds: Codable, Hashable {
    var minX: Float
    var minY: Float
    var maxX: Float
    var maxY: Float

    static let zero = StrokeBounds(minX: 0, minY: 0, maxX: 0, maxY: 0)

    init(minX: Float, minY: Float, maxX: Float, maxY: Float) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }

    init(points: [StrokePoint]) {
        guard let first = points.first else {
            self = .zero
            return
        }

        var minX = first.x
        var minY = first.y
        var maxX = first.x
        var maxY = first.y

        for point in points.dropFirst() {
            minX = Swift.min(minX, point.x)
            minY = Swift.min(minY, point.y)
            maxX = Swift.max(maxX, point.x)
            maxY = Swift.max(maxY, point.y)
        }

        self.init(minX: minX, minY: minY, maxX: maxX, maxY: maxY)
    }
}

struct StrokePointSpan: Codable, Hashable {
    var startIndex: UInt32
    var endIndex: UInt32
}

struct Stroke: Codable, Hashable, Identifiable {
    var id: UUID
    var style: StrokeStyle
    var points: [StrokePoint]
    var bounds: StrokeBounds

    // Soft-delete + segment erase allow eraser/undo without rewriting raw points immediately.
    var isDeleted: Bool
    var erasedSpans: [StrokePointSpan]

    var createdAtMillis: Int64
    var updatedAtMillis: Int64
    var revision: Int32
}

struct StrokeDocument: Codable, Hashable {
    var formatVersion: UInt16
    var strokes: [Stroke]

    static let currentVersion: UInt16 = 1
}

#if canImport(CoreGraphics)
extension StrokePoint {
    var cgPoint: CGPoint {
        CGPoint(x: CGFloat(x), y: CGFloat(y))
    }
}

extension StrokeBounds {
    var cgRect: CGRect {
        CGRect(
            x: CGFloat(minX),
            y: CGFloat(minY),
            width: CGFloat(maxX - minX),
            height: CGFloat(maxY - minY)
        )
    }
}
#endif

#if canImport(UIKit)
import UIKit

extension StrokeColor {
    init(_ color: UIColor) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        self.init(
            r: UInt8((max(0, min(1, red)) * 255.0).rounded()),
            g: UInt8((max(0, min(1, green)) * 255.0).rounded()),
            b: UInt8((max(0, min(1, blue)) * 255.0).rounded()),
            a: UInt8((max(0, min(1, alpha)) * 255.0).rounded())
        )
    }

    var uiColor: UIColor {
        UIColor(
            red: CGFloat(r) / 255.0,
            green: CGFloat(g) / 255.0,
            blue: CGFloat(b) / 255.0,
            alpha: CGFloat(a) / 255.0
        )
    }
}
#endif
