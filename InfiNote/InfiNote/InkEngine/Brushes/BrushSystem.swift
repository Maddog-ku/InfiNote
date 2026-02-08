//
//  BrushSystem.swift
//  InfiNote
//

import UIKit

private protocol Brush {
    var blendMode: CGBlendMode { get }
    func width(for sample: StrokePoint, baseWidth: CGFloat, cameraScale: CGFloat) -> CGFloat
    func alpha(for sample: StrokePoint, baseOpacity: CGFloat, predicted: Bool) -> CGFloat
}

private struct PencilBrush: Brush {
    let blendMode: CGBlendMode = .normal

    func width(for sample: StrokePoint, baseWidth: CGFloat, cameraScale: CGFloat) -> CGFloat {
        let pressure = CGFloat(sample.pressure)
        let altitude = CGFloat(sample.altitude)
        let altitudeBoost = 1 + (1 - max(0, min(1, altitude / (.pi / 2)))) * 0.45
        return max(0.4, baseWidth * cameraScale * (0.45 + pressure * 1.3) * altitudeBoost)
    }

    func alpha(for sample: StrokePoint, baseOpacity: CGFloat, predicted: Bool) -> CGFloat {
        let pressure = CGFloat(sample.pressure)
        let grain = 0.8 + noise(sample: sample) * 0.25
        var alpha = baseOpacity * (0.35 + pressure * 0.75) * grain
        if predicted { alpha *= 0.4 }
        return max(0.01, min(1, alpha))
    }

    private func noise(sample: StrokePoint) -> CGFloat {
        let seed = sin(Double(sample.x) * 12.9898 + Double(sample.y) * 78.233 + Double(sample.time) * 0.15) * 43758.5453
        return CGFloat(seed - floor(seed))
    }
}

private struct PenBrush: Brush {
    let blendMode: CGBlendMode = .normal

    func width(for sample: StrokePoint, baseWidth: CGFloat, cameraScale: CGFloat) -> CGFloat {
        let pressure = CGFloat(sample.pressure)
        return max(0.6, baseWidth * cameraScale * (0.9 + pressure * 0.18))
    }

    func alpha(for sample: StrokePoint, baseOpacity: CGFloat, predicted: Bool) -> CGFloat {
        let pressure = CGFloat(sample.pressure)
        var alpha = baseOpacity * (0.92 + pressure * 0.08)
        if predicted { alpha *= 0.35 }
        return max(0.01, min(1, alpha))
    }
}

private struct HighlighterBrush: Brush {
    let blendMode: CGBlendMode = .multiply

    func width(for sample: StrokePoint, baseWidth: CGFloat, cameraScale: CGFloat) -> CGFloat {
        let pressure = CGFloat(sample.pressure)
        return max(1.2, baseWidth * cameraScale * (0.85 + pressure * 0.2))
    }

    func alpha(for sample: StrokePoint, baseOpacity: CGFloat, predicted: Bool) -> CGFloat {
        let pressure = CGFloat(sample.pressure)
        var alpha = baseOpacity * (0.14 + pressure * 0.12)
        if predicted { alpha *= 0.45 }
        return max(0.01, min(0.4, alpha))
    }
}

private enum BrushFactory {
    static func make(tool: InkTool) -> any Brush {
        switch tool {
        case .pen:
            PenBrush()
        case .pencil:
            PencilBrush()
        case .highlighter:
            HighlighterBrush()
        }
    }
}

enum BrushRenderer {
    static func drawStroke(
        _ stroke: Stroke,
        in context: CGContext,
        toView transform: (CGPoint) -> CGPoint,
        predicted: Bool,
        cameraScale: CGFloat
    ) {
        guard !stroke.points.isEmpty else { return }

        let brush = BrushFactory.make(tool: stroke.style.tool)
        let color = stroke.style.color.uiColor
        let baseWidth = CGFloat(stroke.style.width)
        let baseOpacity = CGFloat(stroke.style.opacity)
        let lodStride = pointStride(cameraScale: cameraScale, predicted: predicted)
        let sampledIndices = sampledPointIndices(pointCount: stroke.points.count, stride: lodStride)
        let sampledPoints = sampledIndices.map { stroke.points[$0] }
        let viewPoints = sampledPoints.map { transform($0.cgPoint) }

        context.saveGState()
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setBlendMode(brush.blendMode)

        if sampledPoints.count == 1, let only = sampledPoints.first {
            let point = viewPoints[0]
            let width = brush.width(for: only, baseWidth: baseWidth, cameraScale: cameraScale)
            let alpha = brush.alpha(for: only, baseOpacity: baseOpacity, predicted: predicted)
            context.setFillColor(color.withAlphaComponent(alpha).cgColor)
            context.fillEllipse(in: CGRect(x: point.x - width * 0.5, y: point.y - width * 0.5, width: width, height: width))
            context.restoreGState()
            return
        }

        let minDistance = minimumSegmentDistance(cameraScale: cameraScale, predicted: predicted)
        let minDistanceSquared = minDistance * minDistance
        for index in 1..<sampledPoints.count {
            let prevSample = sampledPoints[index - 1]
            let currentSample = sampledPoints[index]
            let start = viewPoints[index - 1]
            let end = viewPoints[index]
            let dx = end.x - start.x
            let dy = end.y - start.y
            if dx * dx + dy * dy < minDistanceSquared, index < sampledPoints.count - 1 {
                continue
            }
            let sample = blendedSample(lhs: prevSample, rhs: currentSample)

            let width = brush.width(for: sample, baseWidth: baseWidth, cameraScale: cameraScale)
            let alpha = brush.alpha(for: sample, baseOpacity: baseOpacity, predicted: predicted)

            context.setStrokeColor(color.withAlphaComponent(alpha).cgColor)
            context.setLineWidth(width)
            context.move(to: start)
            context.addLine(to: end)
            context.strokePath()
        }

        context.restoreGState()
    }

    private static func pointStride(cameraScale: CGFloat, predicted: Bool) -> Int {
        guard !predicted else { return 1 }
        if cameraScale >= 1 { return 1 }
        if cameraScale >= 0.65 { return 2 }
        if cameraScale >= 0.4 { return 3 }
        return 4
    }

    private static func sampledPointIndices(pointCount: Int, stride: Int) -> [Int] {
        guard pointCount > 0 else { return [] }
        guard stride > 1 else { return Array(0..<pointCount) }
        var indices: [Int] = []
        indices.reserveCapacity((pointCount / stride) + 2)
        var index = 0
        while index < pointCount {
            indices.append(index)
            index += stride
        }
        if indices.last != pointCount - 1 {
            indices.append(pointCount - 1)
        }
        return indices
    }

    private static func minimumSegmentDistance(cameraScale: CGFloat, predicted: Bool) -> CGFloat {
        if predicted {
            return 1.2
        }
        if cameraScale < 0.5 {
            return 1.5
        }
        if cameraScale < 0.8 {
            return 1.0
        }
        return 0.35
    }

    private static func blendedSample(lhs: StrokePoint, rhs: StrokePoint) -> StrokePoint {
        StrokePoint(
            x: (lhs.x + rhs.x) * 0.5,
            y: (lhs.y + rhs.y) * 0.5,
            time: (lhs.time + rhs.time) * 0.5,
            pressure: (lhs.pressure + rhs.pressure) * 0.5,
            azimuth: (lhs.azimuth + rhs.azimuth) * 0.5,
            altitude: (lhs.altitude + rhs.altitude) * 0.5
        )
    }
}
