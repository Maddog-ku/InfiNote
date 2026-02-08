//
//  CanvasModels.swift
//  InfiNote
//

import Foundation
import CoreGraphics

typealias CanvasInkTool = InkTool
typealias CanvasColor = StrokeColor
typealias CanvasStrokeStyle = StrokeStyle
typealias CanvasStrokePoint = StrokePoint
typealias CanvasStroke = Stroke

enum EraserMode: String, CaseIterable, Identifiable {
    case stroke
    case segment

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stroke:
            return "Stroke"
        case .segment:
            return "Segment"
        }
    }
}

enum EditorTool: String, CaseIterable, Identifiable {
    case pen
    case pencil
    case highlighter
    case eraser
    case lasso

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pen:
            return "Pen"
        case .pencil:
            return "Pencil"
        case .highlighter:
            return "Marker"
        case .eraser:
            return "Eraser"
        case .lasso:
            return "Lasso"
        }
    }

    var inkTool: InkTool? {
        switch self {
        case .pen:
            return .pen
        case .pencil:
            return .pencil
        case .highlighter:
            return .highlighter
        case .eraser:
            return nil
        case .lasso:
            return nil
        }
    }
}

struct CanvasTextBox: Identifiable, Hashable {
    var id: UUID
    var text: String
    var frame: StrokeBounds
    var rotation: Float
    var createdAtMillis: Int64
    var updatedAtMillis: Int64
}

struct LassoPolygon: Hashable {
    var points: [CanvasStrokePoint]

    var isClosed: Bool {
        points.count >= 3
    }

    var bounds: StrokeBounds {
        StrokeBounds(points: points)
    }
}

struct SelectionGroup: Hashable {
    var id: UUID
    var strokeIDs: Set<UUID>
    var textBoxIDs: Set<UUID>
    var lasso: LassoPolygon
    var bounds: StrokeBounds

    var isEmpty: Bool {
        strokeIDs.isEmpty && textBoxIDs.isEmpty
    }
}

enum CanvasBackgroundTemplate: String, CaseIterable, Identifiable {
    case lines
    case grid
    case dots

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lines:
            return "Lines"
        case .grid:
            return "Grid"
        case .dots:
            return "Dots"
        }
    }
}

struct CanvasCamera {
    var scale: CGFloat = 1
    var translation: CGPoint = .zero

    let minScale: CGFloat = 0.2
    let maxScale: CGFloat = 6

    mutating func updateScale(multiplier: CGFloat) {
        scale = max(minScale, min(maxScale, scale * multiplier))
    }

    func worldToView(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: point.x * scale + translation.x,
            y: point.y * scale + translation.y
        )
    }

    func viewToWorld(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: (point.x - translation.x) / scale,
            y: (point.y - translation.y) / scale
        )
    }
}
