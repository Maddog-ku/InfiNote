import Foundation
import simd

enum BrushKind: String, Codable, CaseIterable {
    case pencil
    case pen
    case highlighter
}

struct BrushModel: Codable, Hashable, Identifiable {
    var id: UUID
    var kind: BrushKind
    var rgba: SIMD4<Float>
    var size: Float
    var opacity: Float
    var smoothing: Float
    var pressureCurve: [SIMD2<Float>] // (input, output)

    static let `default` = BrushModel(
        id: UUID(),
        kind: .pen,
        rgba: SIMD4<Float>(0, 0, 0, 1),
        size: 2.2,
        opacity: 1.0,
        smoothing: 0.35,
        pressureCurve: [SIMD2<Float>(0, 0), SIMD2<Float>(1, 1)]
    )
}
