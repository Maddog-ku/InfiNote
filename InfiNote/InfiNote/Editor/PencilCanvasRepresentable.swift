//
//  PencilCanvasRepresentable.swift
//  InfiNote
//

#if os(iOS)
import Foundation
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
    @Binding var loadPDFPageToken: Int
    @Binding var pdfPageLayer: CanvasPDFPageLayer?
    @Binding var pdfPageAnnotations: CanvasPageAnnotations
    @Binding var capturePDFPageToken: Int
    @Binding var capturedPDFPageAnnotations: CanvasPageAnnotations
    @Binding var insertTextToken: Int
    @Binding var exportPDFToken: Int
    @Binding var textContent: String
    @Binding var textFontPostScriptName: String
    @Binding var textFontSize: Double
    @Binding var textColor: Color
    @Binding var exportStatusMessage: String
    @Binding var color: Color
    @Binding var width: Double
    @Binding var opacity: Double

    func makeUIView(context: Context) -> PencilInkCanvasView {
        let view = PencilInkCanvasView()
        view.backgroundTemplate = backgroundTemplate
        applyToolState(to: view)
        view.setPDFLayer(pdfPageLayer)
        view.setPageAnnotations(pdfPageAnnotations)
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
        if context.coordinator.lastLoadPDFPageToken != loadPDFPageToken {
            context.coordinator.lastLoadPDFPageToken = loadPDFPageToken
            uiView.setPDFLayer(pdfPageLayer)
            uiView.setPageAnnotations(pdfPageAnnotations)
        }
        if context.coordinator.lastCapturePDFPageToken != capturePDFPageToken {
            context.coordinator.lastCapturePDFPageToken = capturePDFPageToken
            capturedPDFPageAnnotations = uiView.currentPageAnnotations()
        }
        if context.coordinator.lastInsertTextToken != insertTextToken {
            context.coordinator.lastInsertTextToken = insertTextToken
            uiView.insertTextBoxAtViewportCenter()
        }
        if context.coordinator.lastExportPDFToken != exportPDFToken {
            context.coordinator.lastExportPDFToken = exportPDFToken
            do {
                let result = try uiView.exportVisibleContentPDF()
                let filename = "InfiNote-\(Int(Date().timeIntervalSince1970)).pdf"
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
                try result.data.write(to: url, options: .atomic)
                if result.missingFontPostScriptNames.isEmpty {
                    exportStatusMessage = "PDF exported: \(url.lastPathComponent)"
                } else {
                    exportStatusMessage = "PDF exported with fallback fonts: \(result.missingFontPostScriptNames.joined(separator: ", "))"
                }
            } catch {
                exportStatusMessage = "PDF export failed: \(error.localizedDescription)"
            }
        }
    }

    private func applyToolState(to view: PencilInkCanvasView) {
        if tool == .eraser {
            view.setEraser(mode: eraserMode, size: CGFloat(eraserSize))
        } else if tool == .lasso {
            view.setLassoEnabled(true)
        } else if tool == .text {
            view.setTextToolEnabled(true)
        } else if let inkTool = tool.inkTool {
            view.setActiveBrush(
                tool: inkTool,
                color: UIColor(color),
                width: CGFloat(width),
                opacity: CGFloat(opacity)
            )
            view.setLassoEnabled(false)
        }
        view.setActiveTextContent(textContent)
        view.setActiveTextStyle(
            fontPostScriptName: textFontPostScriptName,
            fontSize: CGFloat(textFontSize),
            color: UIColor(textColor)
        )
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
        var lastLoadPDFPageToken: Int = 0
        var lastCapturePDFPageToken: Int = 0
        var lastInsertTextToken: Int = 0
        var lastExportPDFToken: Int = 0
    }
}
#endif
