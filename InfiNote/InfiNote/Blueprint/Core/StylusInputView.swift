import UIKit

struct InputSample {
    let location: CGPoint
    let timestamp: TimeInterval
    let force: CGFloat
    let altitude: CGFloat
    let azimuth: CGFloat
    let touchType: UITouch.TouchType
}

final class StylusInputView: UIView {
    var onSample: ((InputSample) -> Void)?
    var onlyAcceptPencil = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        let all = touches.flatMap { touch -> [UITouch] in
            let coalesced = event?.coalescedTouches(for: touch) ?? []
            return coalesced.isEmpty ? [touch] : coalesced
        }

        for t in all {
            if onlyAcceptPencil && t.type != .pencil { continue }
            onSample?(
                InputSample(
                    location: t.location(in: self),
                    timestamp: t.timestamp,
                    force: t.type == .pencil ? t.force : 1,
                    altitude: t.altitudeAngle,
                    azimuth: t.azimuthAngle(in: self),
                    touchType: t.type
                )
            )
        }
    }
}
