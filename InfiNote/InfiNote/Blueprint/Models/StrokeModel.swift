import Foundation
import CoreGraphics

struct StrokePointV1: Codable, Hashable {
    var x: Float
    var y: Float
    var t: Float
    var pressure: Float
    var altitude: Float
    var azimuth: Float
}

struct StrokeEntityV1: Codable, Identifiable, Hashable {
    var id: UUID
    var brushID: UUID
    var points: [StrokePointV1]
    var bbox: CGRectCodable
    var isDeleted: Bool
}

struct CGRectCodable: Codable, Hashable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(_ rect: CGRect) {
        self.x = rect.origin.x
        self.y = rect.origin.y
        self.width = rect.size.width
        self.height = rect.size.height
    }

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}
