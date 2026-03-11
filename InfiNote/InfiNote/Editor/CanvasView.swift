import SwiftUI

struct CanvasView: View {
    @Binding var clearToken: Int
    @Binding var backgroundTemplate: CanvasBackgroundTemplate
    @Binding var tool: EditorTool
    @Binding var eraserMode: EraserMode
    @Binding var eraserSize: Double
    @Binding var loadPageToken: Int
    @Binding var pdfPageLayer: CanvasPDFPageLayer?
    @Binding var pageAnnotations: CanvasPageAnnotations
    @Binding var capturePageToken: Int
    @Binding var capturedPageAnnotations: CanvasPageAnnotations
    @Binding var textContent: String
    @Binding var textFontPostScriptName: String
    @Binding var textFontSize: Double
    @Binding var textColor: Color
    @Binding var exportStatusMessage: String
    @Binding var brushColor: Color
    @Binding var brushWidth: Double
    @Binding var brushOpacity: Double

    var body: some View {
        PencilCanvasRepresentable(
            clearToken: $clearToken,
            backgroundTemplate: $backgroundTemplate,
            tool: $tool,
            eraserMode: $eraserMode,
            eraserSize: $eraserSize,
            lassoMoveToken: .constant(0),
            lassoMoveDelta: .constant(.zero),
            lassoScaleToken: .constant(0),
            lassoScaleFactor: .constant(1),
            lassoDeleteToken: .constant(0),
            lassoMergeToken: .constant(0),
            loadPDFPageToken: $loadPageToken,
            pdfPageLayer: $pdfPageLayer,
            pdfPageAnnotations: $pageAnnotations,
            capturePDFPageToken: $capturePageToken,
            capturedPDFPageAnnotations: $capturedPageAnnotations,
            insertTextToken: .constant(0),
            exportPDFToken: .constant(0),
            textContent: $textContent,
            textFontPostScriptName: $textFontPostScriptName,
            textFontSize: $textFontSize,
            textColor: $textColor,
            exportStatusMessage: $exportStatusMessage,
            color: $brushColor,
            width: $brushWidth,
            opacity: $brushOpacity
        )
        .background(Color(uiColor: .systemBackground))
    }
}
