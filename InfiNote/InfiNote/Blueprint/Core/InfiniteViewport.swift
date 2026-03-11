import CoreGraphics

struct ViewportState {
    var scale: CGFloat = 1
    var translation: CGPoint = .zero
    let minScale: CGFloat = 0.2
    let maxScale: CGFloat = 6.0

    mutating func applyPan(_ delta: CGSize) {
        translation.x += delta.width
        translation.y += delta.height
    }

    mutating func applyZoom(multiplier: CGFloat, anchorInView: CGPoint) {
        let oldScale = scale
        let next = max(minScale, min(maxScale, scale * multiplier))
        guard abs(next - oldScale) > .ulpOfOne else { return }

        let worldAnchorBefore = screenToWorld(anchorInView)
        scale = next
        let worldAnchorAfter = screenToWorld(anchorInView)
        translation.x += (worldAnchorAfter.x - worldAnchorBefore.x) * scale
        translation.y += (worldAnchorAfter.y - worldAnchorBefore.y) * scale
    }

    func screenToWorld(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - translation.x) / scale, y: (p.y - translation.y) / scale)
    }

    func worldToScreen(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x * scale + translation.x, y: p.y * scale + translation.y)
    }
}
