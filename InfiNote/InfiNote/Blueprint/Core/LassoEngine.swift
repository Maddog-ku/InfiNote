import CoreGraphics
import Foundation

struct LassoSelection {
    var path: [CGPoint]

    func contains(_ point: CGPoint) -> Bool {
        guard path.count > 2 else { return false }
        let polygon = CGMutablePath()
        polygon.addLines(between: path)
        polygon.closeSubpath()
        return polygon.contains(point)
    }

    func hits(stroke: StrokeEntityV1) -> Bool {
        stroke.points.contains { contains(CGPoint(x: Double($0.x), y: Double($0.y))) }
    }
}

struct SelectionResult {
    var strokeIDs: Set<UUID>
    var textObjectIDs: Set<UUID>
}
