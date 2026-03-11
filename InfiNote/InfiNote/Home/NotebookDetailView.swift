import SwiftUI
import Combine

@MainActor
final class NotebookDetailViewModel: ObservableObject {
    @Published private(set) var notebook: NotebookRecord?
    @Published private(set) var pages: [NotebookPageRecord] = []
    @Published private(set) var selectedPageIndex: Int = 0
    @Published private(set) var pdfPageLayer: CanvasPDFPageLayer?
    @Published var pageAnnotations: CanvasPageAnnotations = .empty
    @Published private(set) var backgroundTemplate: CanvasBackgroundTemplate = .lines
    @Published private(set) var loadPageToken: Int = 0
    @Published var errorMessage: String = ""

    private let notebookID: UUID
    private let store: HomeLibraryStore

    init(notebookID: UUID, store: HomeLibraryStore) {
        self.notebookID = notebookID
        self.store = store
        reload()
    }

    var navigationTitle: String {
        notebook?.title ?? "Notebook"
    }

    var canGoToPreviousPage: Bool {
        selectedPageIndex > 0
    }

    var canGoToNextPage: Bool {
        selectedPageIndex < pages.count - 1
    }

    var pageIndicatorText: String {
        "\(selectedPageIndex + 1) / \(max(1, pages.count))"
    }

    func reload() {
        do {
            notebook = store.notebookRecord(with: notebookID)
            backgroundTemplate = notebook?.template.canvasBackgroundTemplate ?? .lines
            let document = try store.loadNotebookDocument(for: notebookID)
            pages = document.pages
            selectPage(index: selectedPageIndex, reloadNotebook: true)
        } catch {
            notebook = store.notebookRecord(with: notebookID)
            backgroundTemplate = notebook?.template.canvasBackgroundTemplate ?? .lines
            pages = [
                NotebookPageRecord(
                    id: UUID(),
                    pageIndex: 0,
                    width: 768,
                    height: 1024,
                    annotations: .empty
                )
            ]
            selectedPageIndex = 0
            pdfPageLayer = nil
            pageAnnotations = .empty
            loadPageToken &+= 1
            errorMessage = error.localizedDescription
        }
    }

    func selectPreviousPage() {
        guard canGoToPreviousPage else { return }
        selectPage(index: selectedPageIndex - 1)
    }

    func selectNextPage() {
        guard canGoToNextPage else { return }
        selectPage(index: selectedPageIndex + 1)
    }

    func selectPage(index: Int, reloadNotebook: Bool = false) {
        if reloadNotebook {
            notebook = store.notebookRecord(with: notebookID)
            backgroundTemplate = notebook?.template.canvasBackgroundTemplate ?? .lines
        }
        guard !pages.isEmpty else {
            pageAnnotations = .empty
            pdfPageLayer = nil
            loadPageToken &+= 1
            return
        }

        let clampedIndex = max(0, min(index, pages.count - 1))
        selectedPageIndex = clampedIndex

        let page = pages[clampedIndex]
        if let notebook, let pdfURL = store.urlForNotebookPDF(notebook) {
            pdfPageLayer = CanvasPDFPageLayer(
                sourceFileURL: pdfURL,
                pageIndex: page.pageIndex,
                pageWidth: page.width,
                pageHeight: page.height,
                worldOrigin: .zero
            )
        } else {
            pdfPageLayer = nil
        }
        pageAnnotations = page.annotations
        loadPageToken &+= 1
    }

    func persistCurrentPage(_ annotations: CanvasPageAnnotations) {
        guard pages.indices.contains(selectedPageIndex) else { return }

        pages[selectedPageIndex].annotations = annotations
        let document = NotebookDocumentRecord(notebookID: notebookID, pages: pages)

        do {
            try store.saveNotebookDocument(document)
            notebook = store.notebookRecord(with: notebookID)
            errorMessage = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct NotebookDetailView: View {
    @StateObject private var viewModel: NotebookDetailViewModel

    init(notebookID: UUID, store: HomeLibraryStore) {
        _viewModel = StateObject(wrappedValue: NotebookDetailViewModel(notebookID: notebookID, store: store))
    }

    var body: some View {
        EditorView(viewModel: viewModel)
            .navigationTitle(viewModel.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .alert("Error", isPresented: Binding(
                get: { !viewModel.errorMessage.isEmpty },
                set: { if !$0 { viewModel.errorMessage = "" } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage)
            }
    }
}
