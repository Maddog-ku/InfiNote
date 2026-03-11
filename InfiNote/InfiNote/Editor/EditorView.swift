import SwiftUI

struct EditorView: View {
    @ObservedObject var viewModel: NotebookDetailViewModel

    @State private var clearToken: Int = 0
    @State private var selectedTool: EditorTool = .pen
    @State private var eraserMode: EraserMode = .stroke
    @State private var eraserSize: Double = 20
    @State private var capturePageToken: Int = 0
    @State private var capturedPageAnnotations: CanvasPageAnnotations = .empty
    @State private var pendingPageIndex: Int?
    @State private var textContent: String = "Text"
    @State private var textFontPostScriptName: String = "Helvetica"
    @State private var textFontSize: Double = 18
    @State private var textColor: Color = .black
    @State private var exportStatusMessage: String = ""
    @State private var brushColor: Color = .black
    @State private var brushWidth: Double = 2.2
    @State private var brushOpacity: Double = 1

    var body: some View {
        CanvasView(
            clearToken: $clearToken,
            backgroundTemplate: Binding(
                get: { viewModel.backgroundTemplate },
                set: { _ in }
            ),
            tool: $selectedTool,
            eraserMode: $eraserMode,
            eraserSize: $eraserSize,
            loadPageToken: Binding(
                get: { viewModel.loadPageToken },
                set: { _ in }
            ),
            pdfPageLayer: Binding(
                get: { viewModel.pdfPageLayer },
                set: { _ in }
            ),
            pageAnnotations: $viewModel.pageAnnotations,
            capturePageToken: $capturePageToken,
            capturedPageAnnotations: $capturedPageAnnotations,
            textContent: $textContent,
            textFontPostScriptName: $textFontPostScriptName,
            textFontSize: $textFontSize,
            textColor: $textColor,
            exportStatusMessage: $exportStatusMessage,
            brushColor: $brushColor,
            brushWidth: $brushWidth,
            brushOpacity: $brushOpacity
        )
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    requestPageChange(to: viewModel.selectedPageIndex - 1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(!viewModel.canGoToPreviousPage)

                Text(viewModel.pageIndicatorText)
                    .font(.caption.monospacedDigit())

                Button {
                    requestPageChange(to: viewModel.selectedPageIndex + 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(!viewModel.canGoToNextPage)

                Button("Clear") {
                    clearToken &+= 1
                }
            }
        }
        .onChange(of: capturedPageAnnotations) { _, annotations in
            viewModel.persistCurrentPage(annotations)
            guard let nextPageIndex = pendingPageIndex else { return }
            pendingPageIndex = nil
            viewModel.selectPage(index: nextPageIndex, reloadNotebook: true)
        }
    }

    private func requestPageChange(to pageIndex: Int) {
        guard pageIndex != viewModel.selectedPageIndex else { return }
        pendingPageIndex = pageIndex
        capturePageToken &+= 1
    }
}
