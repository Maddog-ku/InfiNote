//
//  PencilCanvasRepresentable.swift
//  InfiNote
//

#if os(iOS)
import SwiftUI
import UIKit

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}

struct PencilCanvasRepresentable: UIViewRepresentable {
    @Binding var clearToken: Int
    @Binding var backgroundTemplate: CanvasBackgroundTemplate
    @Binding var tool: EditorTool
    @Binding var eraserMode: EraserMode
    @Binding var eraserSize: Double
    @Binding var lassoMoveToken: Int
    @Binding var lassoMoveDelta: CGSize
    @Binding var lassoScaleToken: Int
    @Binding var lassoScaleFactor: Double
    @Binding var lassoDeleteToken: Int
    @Binding var lassoMergeToken: Int
    @Binding var color: Color
    @Binding var width: Double
    @Binding var opacity: Double

    func makeUIView(context: Context) -> PencilInkCanvasView {
        let view = PencilInkCanvasView()
        view.backgroundTemplate = backgroundTemplate
        applyToolState(to: view)
        return view
    }

    func updateUIView(_ uiView: PencilInkCanvasView, context: Context) {
        uiView.backgroundTemplate = backgroundTemplate
        applyToolState(to: uiView)
        if context.coordinator.lastClearToken != clearToken {
            context.coordinator.lastClearToken = clearToken
            uiView.clear()
        }
        if context.coordinator.lastLassoMoveToken != lassoMoveToken {
            context.coordinator.lastLassoMoveToken = lassoMoveToken
            uiView.moveSelection(byViewTranslation: lassoMoveDelta)
        }
        if context.coordinator.lastLassoScaleToken != lassoScaleToken {
            context.coordinator.lastLassoScaleToken = lassoScaleToken
            uiView.scaleSelection(aroundViewPoint: uiView.bounds.center, scale: CGFloat(lassoScaleFactor))
        }
        if context.coordinator.lastLassoDeleteToken != lassoDeleteToken {
            context.coordinator.lastLassoDeleteToken = lassoDeleteToken
            uiView.deleteSelection()
        }
        if context.coordinator.lastLassoMergeToken != lassoMergeToken {
            context.coordinator.lastLassoMergeToken = lassoMergeToken
            uiView.mergeSelection()
        }
    }

    private func applyToolState(to view: PencilInkCanvasView) {
        if tool == .eraser {
            view.setEraser(mode: eraserMode, size: CGFloat(eraserSize))
        } else if tool == .lasso {
            view.setLassoEnabled(true)
        } else if let inkTool = tool.inkTool {
            view.setActiveBrush(
                tool: inkTool,
                color: UIColor(color),
                width: CGFloat(width),
                opacity: CGFloat(opacity)
            )
            view.setLassoEnabled(false)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var lastClearToken: Int = 0
        var lastLassoMoveToken: Int = 0
        var lastLassoScaleToken: Int = 0
        var lastLassoDeleteToken: Int = 0
        var lastLassoMergeToken: Int = 0
    }
}
#endif
