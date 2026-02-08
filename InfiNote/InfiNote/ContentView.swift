//
//  ContentView.swift
//  InfiNote
//

import SwiftUI
#if os(iOS)
import UniformTypeIdentifiers
#endif

struct ContentView: View {
#if os(iOS)
    @State private var clearToken: Int = 0
    @State private var backgroundTemplate: CanvasBackgroundTemplate = .lines
    @State private var selectedTool: EditorTool = .pen
    @State private var eraserMode: EraserMode = .stroke
    @State private var eraserSize: Double = 20
    @State private var lassoMoveToken: Int = 0
    @State private var lassoMoveDelta: CGSize = .zero
    @State private var lassoScaleToken: Int = 0
    @State private var lassoScaleFactor: Double = 1
    @State private var lassoDeleteToken: Int = 0
    @State private var lassoMergeToken: Int = 0
    @State private var insertTextToken: Int = 0
    @State private var exportPDFToken: Int = 0
    @State private var showFontImporter = false
    @State private var showPDFImporter = false
    @State private var textContent: String = "Text"
    @State private var textFontPostScriptName: String = "Helvetica"
    @State private var textFontSize: Double = 18
    @State private var textColor: Color = .black
    @State private var availableFonts: [String] = ["Helvetica"]
    @State private var exportStatusMessage: String = ""
    @State private var notebooks: [PDFNotebook] = []
    @State private var selectedNotebookID: UUID?
    @State private var selectedPageIndex: Int = 0
    @State private var loadPDFPageToken: Int = 0
    @State private var pdfPageLayer: CanvasPDFPageLayer?
    @State private var pdfPageAnnotations: CanvasPageAnnotations = .empty
    @State private var capturePDFPageToken: Int = 0
    @State private var capturedPDFPageAnnotations: CanvasPageAnnotations = .empty
    @State private var pendingSwitchNotebookID: UUID?
    @State private var pendingSwitchPageIndex: Int?
    @State private var pendingExportNotebookID: UUID?
    @State private var brushColor: Color = .black
    @State private var brushWidth: Double = 2.2
    @State private var brushOpacity: Double = 1
#endif

    var body: some View {
#if os(iOS)
        NavigationStack {
            VStack(spacing: 0) {
                PencilCanvasRepresentable(
                    clearToken: $clearToken,
                    backgroundTemplate: $backgroundTemplate,
                    tool: $selectedTool,
                    eraserMode: $eraserMode,
                    eraserSize: $eraserSize,
                    lassoMoveToken: $lassoMoveToken,
                    lassoMoveDelta: $lassoMoveDelta,
                    lassoScaleToken: $lassoScaleToken,
                    lassoScaleFactor: $lassoScaleFactor,
                    lassoDeleteToken: $lassoDeleteToken,
                    lassoMergeToken: $lassoMergeToken,
                    loadPDFPageToken: $loadPDFPageToken,
                    pdfPageLayer: $pdfPageLayer,
                    pdfPageAnnotations: $pdfPageAnnotations,
                    capturePDFPageToken: $capturePDFPageToken,
                    capturedPDFPageAnnotations: $capturedPDFPageAnnotations,
                    insertTextToken: $insertTextToken,
                    exportPDFToken: $exportPDFToken,
                    textContent: $textContent,
                    textFontPostScriptName: $textFontPostScriptName,
                    textFontSize: $textFontSize,
                    textColor: $textColor,
                    exportStatusMessage: $exportStatusMessage,
                    color: $brushColor,
                    width: $brushWidth,
                    opacity: $brushOpacity
                )
                .overlay(alignment: .bottom) {
                    VStack(spacing: 10) {
                        if !notebooks.isEmpty {
                            HStack(spacing: 10) {
                                Picker("Notebook", selection: Binding(
                                    get: { selectedNotebookID ?? notebooks.first?.id ?? UUID() },
                                    set: { requestNotebookSwitch(to: $0) }
                                )) {
                                    ForEach(notebooks) { notebook in
                                        Text(notebook.title).tag(notebook.id)
                                    }
                                }
                                .frame(width: 260)

                                Button("Prev") {
                                    guard let notebook = selectedNotebook else { return }
                                    let prev = max(0, selectedPageIndex - 1)
                                    if prev != selectedPageIndex {
                                        requestPageSwitch(to: prev, notebookID: notebook.id)
                                    }
                                }
                                .disabled(selectedNotebook == nil || selectedPageIndex <= 0)

                                Text("Page \(selectedPageIndex + 1)/\(selectedNotebook?.pages.count ?? 0)")
                                    .font(.caption)
                                    .frame(minWidth: 90)

                                Button("Next") {
                                    guard let notebook = selectedNotebook else { return }
                                    let last = max(0, notebook.pages.count - 1)
                                    let next = min(last, selectedPageIndex + 1)
                                    if next != selectedPageIndex {
                                        requestPageSwitch(to: next, notebookID: notebook.id)
                                    }
                                }
                                .disabled(selectedNotebook == nil || selectedPageIndex >= (selectedNotebook?.pages.count ?? 1) - 1)
                            }
                        }

                        Picker("Tool", selection: $selectedTool) {
                            ForEach(EditorTool.allCases) { tool in
                                Text(tool.title).tag(tool)
                            }
                        }
                        .pickerStyle(.segmented)

                        if selectedTool == .eraser {
                            HStack(spacing: 12) {
                                Picker("Mode", selection: $eraserMode) {
                                    ForEach(EraserMode.allCases) { mode in
                                        Text(mode.title).tag(mode)
                                    }
                                }
                                .pickerStyle(.segmented)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Size \(eraserSize, specifier: "%.0f")")
                                        .font(.caption2)
                                    Slider(value: $eraserSize, in: 4...80)
                                }
                            }
                        } else if selectedTool == .lasso {
                            HStack(spacing: 10) {
                                Button("Left") {
                                    lassoMoveDelta = CGSize(width: -18, height: 0)
                                    lassoMoveToken &+= 1
                                }
                                Button("Right") {
                                    lassoMoveDelta = CGSize(width: 18, height: 0)
                                    lassoMoveToken &+= 1
                                }
                                Button("Up") {
                                    lassoMoveDelta = CGSize(width: 0, height: -18)
                                    lassoMoveToken &+= 1
                                }
                                Button("Down") {
                                    lassoMoveDelta = CGSize(width: 0, height: 18)
                                    lassoMoveToken &+= 1
                                }
                                Button("−") {
                                    lassoScaleFactor = 0.92
                                    lassoScaleToken &+= 1
                                }
                                Button("+") {
                                    lassoScaleFactor = 1.08
                                    lassoScaleToken &+= 1
                                }
                                Button("Delete", role: .destructive) {
                                    lassoDeleteToken &+= 1
                                }
                                Button("Merge") {
                                    lassoMergeToken &+= 1
                                }
                            }
                            .buttonStyle(.bordered)
                        } else if selectedTool == .text {
                            VStack(spacing: 8) {
                                HStack(spacing: 10) {
                                    Button("Insert Text") {
                                        insertTextToken &+= 1
                                    }
                                    Button("Import Fonts") {
                                        showFontImporter = true
                                    }
                                    Button("Export PDF") {
                                        exportPDFToken &+= 1
                                    }
                                }
                                .buttonStyle(.bordered)

                                HStack(spacing: 12) {
                                    TextField("Text", text: $textContent)
                                        .textFieldStyle(.roundedBorder)

                                    Picker("Font", selection: $textFontPostScriptName) {
                                        ForEach(availableFonts, id: \.self) { fontName in
                                            Text(fontName).tag(fontName)
                                        }
                                    }
                                    .frame(width: 220)
                                }

                                HStack(spacing: 14) {
                                    ColorPicker("Text Color", selection: $textColor, supportsOpacity: false)
                                        .labelsHidden()

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Size \(textFontSize, specifier: "%.0f")")
                                            .font(.caption2)
                                        Slider(value: $textFontSize, in: 10...96)
                                    }
                                }
                            }
                        } else {
                            HStack(spacing: 14) {
                                ColorPicker("Color", selection: $brushColor, supportsOpacity: false)
                                    .labelsHidden()

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Width \(brushWidth, specifier: "%.1f")")
                                        .font(.caption2)
                                    Slider(value: $brushWidth, in: 1...18)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Opacity \(brushOpacity, specifier: "%.2f")")
                                        .font(.caption2)
                                    Slider(value: $brushOpacity, in: 0.08...1)
                                }
                            }
                        }
                    }
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(12)
                }
            }
            .navigationTitle("InfiNote")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 8) {
                        Picker("Template", selection: $backgroundTemplate) {
                            ForEach(CanvasBackgroundTemplate.allCases) { template in
                                Text(template.title).tag(template)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 220)

                        Button("Import PDFs") {
                            showPDFImporter = true
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 8) {
                        Button("Save Page") {
                            capturePDFPageToken &+= 1
                        }
                        .disabled(selectedNotebook == nil)

                        Button("Export Notebook") {
                            guard let notebook = selectedNotebook else { return }
                            pendingExportNotebookID = notebook.id
                            capturePDFPageToken &+= 1
                        }
                        .disabled(selectedNotebook == nil)

                        Button("Clear") {
                            clearToken &+= 1
                        }
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showFontImporter,
            allowedContentTypes: [.font],
            allowsMultipleSelection: true
        ) { result in
            handleFontImport(result: result)
        }
        .fileImporter(
            isPresented: $showPDFImporter,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: true
        ) { result in
            handlePDFImport(result: result)
        }
        .onAppear {
            refreshAvailableFonts()
        }
#if os(iOS)
        .onChange(of: selectedTool) { _, newValue in
            if newValue == .text {
                refreshAvailableFonts()
            }
        }
        .onChange(of: capturedPDFPageAnnotations) { _, newValue in
            persistCurrentPageAnnotations(newValue)
            if let exportID = pendingExportNotebookID {
                pendingExportNotebookID = nil
                exportNotebook(id: exportID)
                return
            }
            if let notebookID = pendingSwitchNotebookID {
                let pageIndex = pendingSwitchPageIndex ?? 0
                pendingSwitchNotebookID = nil
                pendingSwitchPageIndex = nil
                switchToNotebook(id: notebookID, pageIndex: pageIndex)
            }
        }
#endif
        .safeAreaInset(edge: .bottom) {
            if !exportStatusMessage.isEmpty {
                Text(exportStatusMessage)
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 8)
            }
        }
#else
        VStack(spacing: 8) {
            Text("InfiNote")
                .font(.title2)
            Text("Apple Pencil ink canvas is available on iPadOS / iOS.")
                .foregroundStyle(.secondary)
        }
        .padding(24)
#endif
    }
}

#Preview {
    ContentView()
}

#if os(iOS)
private extension ContentView {
    var selectedNotebook: PDFNotebook? {
        guard let id = selectedNotebookID else { return nil }
        return notebooks.first(where: { $0.id == id })
    }

    func refreshAvailableFonts() {
        _ = try? FontRegistry.shared.registerPersistedFonts()
        let all = FontRegistry.shared.allPostScriptNames()
        availableFonts = all.isEmpty ? ["Helvetica"] : all
        if !availableFonts.contains(textFontPostScriptName) {
            textFontPostScriptName = availableFonts[0]
        }
    }

    func handleFontImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            do {
                let imported = try FontRegistry.shared.importFontFiles(urls: urls)
                refreshAvailableFonts()
                let names = imported.flatMap(\.postScriptNames)
                exportStatusMessage = names.isEmpty ? "Fonts imported." : "Fonts imported: \(names.joined(separator: ", "))"
            } catch {
                exportStatusMessage = "Font import failed: \(error.localizedDescription)"
            }
        case .failure(let error):
            exportStatusMessage = "Font import failed: \(error.localizedDescription)"
        }
    }

    func handlePDFImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            do {
                let imported = try PDFImportService().importPDFs(urls: urls)
                notebooks.append(contentsOf: imported)
                if selectedNotebookID == nil, let first = imported.first {
                    selectedNotebookID = first.id
                    selectedPageIndex = 0
                    loadSelectedPDFPage()
                }
                exportStatusMessage = imported.isEmpty ? "No PDFs imported." : "Imported \(imported.count) PDF notebook(s)."
            } catch {
                exportStatusMessage = "PDF import failed: \(error.localizedDescription)"
            }
        case .failure(let error):
            exportStatusMessage = "PDF import failed: \(error.localizedDescription)"
        }
    }

    func requestNotebookSwitch(to notebookID: UUID) {
        pendingSwitchNotebookID = notebookID
        pendingSwitchPageIndex = 0
        capturePDFPageToken &+= 1
    }

    func requestPageSwitch(to pageIndex: Int, notebookID: UUID) {
        pendingSwitchNotebookID = notebookID
        pendingSwitchPageIndex = pageIndex
        capturePDFPageToken &+= 1
    }

    func switchToNotebook(id: UUID, pageIndex: Int) {
        selectedNotebookID = id
        selectedPageIndex = pageIndex
        loadSelectedPDFPage()
    }

    func loadSelectedPDFPage() {
        guard let notebookIndex = notebooks.firstIndex(where: { $0.id == selectedNotebookID }) else {
            pdfPageLayer = nil
            pdfPageAnnotations = .empty
            loadPDFPageToken &+= 1
            return
        }
        guard !notebooks[notebookIndex].pages.isEmpty else {
            pdfPageLayer = nil
            pdfPageAnnotations = .empty
            loadPDFPageToken &+= 1
            return
        }
        let clamped = max(0, min(selectedPageIndex, notebooks[notebookIndex].pages.count - 1))
        selectedPageIndex = clamped
        let page = notebooks[notebookIndex].pages[clamped]
        pdfPageLayer = CanvasPDFPageLayer(
            sourceFileURL: notebooks[notebookIndex].sourceFileURL,
            pageIndex: page.pageIndex,
            pageWidth: page.width,
            pageHeight: page.height,
            worldOrigin: .zero
        )
        pdfPageAnnotations = notebooks[notebookIndex].annotationsByPageIndex[page.pageIndex] ?? .empty
        loadPDFPageToken &+= 1
    }

    func persistCurrentPageAnnotations(_ annotations: CanvasPageAnnotations) {
        guard let notebookID = selectedNotebookID,
              let notebookIndex = notebooks.firstIndex(where: { $0.id == notebookID }),
              !notebooks[notebookIndex].pages.isEmpty else {
            return
        }
        let clamped = max(0, min(selectedPageIndex, notebooks[notebookIndex].pages.count - 1))
        let pageIndex = notebooks[notebookIndex].pages[clamped].pageIndex
        notebooks[notebookIndex].annotationsByPageIndex[pageIndex] = annotations
    }

    func exportNotebook(id: UUID) {
        guard let notebook = notebooks.first(where: { $0.id == id }) else { return }
        do {
            let result = try PDFNotebookExporter().export(notebook: notebook)
            let filename = "\(notebook.title)-annotated-\(Int(Date().timeIntervalSince1970)).pdf"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try result.data.write(to: url, options: .atomic)
            if result.missingFontPostScriptNames.isEmpty {
                exportStatusMessage = "Merged PDF exported: \(url.lastPathComponent)"
            } else {
                exportStatusMessage = "Merged PDF exported with fallback fonts: \(result.missingFontPostScriptNames.joined(separator: ", "))"
            }
        } catch {
            exportStatusMessage = "Merged PDF export failed: \(error.localizedDescription)"
        }
    }
}
#endif
