//
//  HomeView.swift
//  InfiNote
//

import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @StateObject private var store = HomeLibraryStore()
    private let thumbnails = NotebookThumbnailService.shared

    @State private var showCreateFolder = false
    @State private var showCreateNotebook = false
    @State private var showPDFImporter = false
    @State private var showSettings = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if !store.currentPathFolders.isEmpty {
                        BreadcrumbView(path: store.currentPathFolders) { folder in
                            store.enterFolder(folder.id)
                        }
                    }

                    let childFolders = store.folders(in: store.currentFolderID)
                    ForEach(childFolders) { folder in
                        Button {
                            store.enterFolder(folder.id)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "folder.fill")
                                    .font(.title3)
                                    .foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(folder.name)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text(formattedDate(folder.updatedAtMillis))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(12)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }

                    if !store.notebooks(in: store.currentFolderID).isEmpty {
                        Text("home.section.notebooks")
                            .font(.headline)
                            .padding(.top, 6)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
                        ForEach(store.notebooks(in: store.currentFolderID)) { notebook in
                            NavigationLink {
                                NotebookPlaceholderDetailView(notebook: notebook)
                            } label: {
                                NotebookCardView(notebook: notebook, thumbnails: thumbnails)
                            }
                            .simultaneousGesture(TapGesture().onEnded {
                                try? store.touchNotebook(notebook.id)
                            })
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("home.title")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if store.currentFolderID != nil {
                        Button("home.back") {
                            store.enterFolder(store.currentPathFolders.dropLast().last?.id)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("home.action.new_folder") {
                            showCreateFolder = true
                        }
                        Button("home.action.new_notebook") {
                            showCreateNotebook = true
                        }
                        Button("home.action.import_pdfs") {
                            showPDFImporter = true
                        }
                        Button("home.action.settings") {
                            showSettings = true
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showCreateFolder) {
            CreateFolderSheet { name in
                do {
                    try store.createFolder(name: name, parentFolderID: store.currentFolderID)
                    showCreateFolder = false
                } catch {
                    errorMessage = String(
                        format: NSLocalizedString("error.create_folder_failed", comment: ""),
                        error.localizedDescription
                    )
                }
            }
        }
        .sheet(isPresented: $showCreateNotebook) {
            CreateNotebookSheet { title, template, orientation in
                do {
                    try store.createNotebook(
                        title: title,
                        template: template,
                        orientation: orientation,
                        parentFolderID: store.currentFolderID
                    )
                    showCreateNotebook = false
                } catch {
                    errorMessage = String(
                        format: NSLocalizedString("error.create_notebook_failed", comment: ""),
                        error.localizedDescription
                    )
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(settings)
        }
        .fileImporter(
            isPresented: $showPDFImporter,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case let .success(urls):
                do {
                    try store.importPDFs(urls: urls, parentFolderID: store.currentFolderID)
                } catch {
                    errorMessage = String(
                        format: NSLocalizedString("error.import_pdf_failed", comment: ""),
                        error.localizedDescription
                    )
                }
            case let .failure(error):
                errorMessage = String(
                    format: NSLocalizedString("error.import_pdf_failed", comment: ""),
                    error.localizedDescription
                )
            }
        }
        .alert("error.title", isPresented: Binding(
            get: { !errorMessage.isEmpty },
            set: { if !$0 { errorMessage = "" } }
        )) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private func formattedDate(_ millis: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(millis) / 1000.0)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let prefix = NSLocalizedString("home.edited_prefix", comment: "")
        return "\(prefix) \(formatter.string(from: date))"
    }
}

private struct NotebookCardView: View {
    let notebook: NotebookRecord
    let thumbnails: NotebookThumbnailService
    @State private var image: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        Rectangle().fill(Color.secondary.opacity(0.15))
                        ProgressView()
                    }
                }
            }
            .frame(height: 130)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(notebook.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(.primary)

            Text(Self.timeText(millis: notebook.lastEditedAtMillis))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .task(id: notebook.thumbnailKey) {
            image = await thumbnails.thumbnail(
                for: notebook,
                targetSize: CGSize(width: 320, height: 220)
            )
        }
    }

    private static func timeText(millis: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(millis) / 1000.0)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        let prefix = NSLocalizedString("home.edited_prefix", comment: "")
        return "\(prefix) \(formatter.localizedString(for: date, relativeTo: Date()))"
    }
}

private struct BreadcrumbView: View {
    let path: [NoteFolder]
    var onTap: (NoteFolder) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(path) { folder in
                    Button(folder.name) {
                        onTap(folder)
                    }
                    .buttonStyle(.bordered)
                    if folder.id != path.last?.id {
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }
}

private struct CreateFolderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    var onCreate: (String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField("home.folder_name", text: $name)
            }
            .navigationTitle("home.action.new_folder")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.create") { onCreate(name) }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct CreateNotebookSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var template: NotebookTemplate = .lined
    @State private var orientation: NotebookOrientation = .portrait
    var onCreate: (String, NotebookTemplate, NotebookOrientation) -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField("home.notebook_name", text: $title)
                Picker("home.template", selection: $template) {
                    ForEach(NotebookTemplate.allCases) { option in
                        Text(option.titleKey).tag(option)
                    }
                }
                Picker("home.orientation", selection: $orientation) {
                    ForEach(NotebookOrientation.allCases) { option in
                        Text(option.titleKey).tag(option)
                    }
                }
            }
            .navigationTitle("home.action.new_notebook")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.create") { onCreate(title, template, orientation) }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct NotebookPlaceholderDetailView: View {
    let notebook: NotebookRecord

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "book.pages")
                .font(.system(size: 36))
                .foregroundStyle(Color.accentColor)
            Text(notebook.title)
                .font(.title3.weight(.semibold))
            HStack {
                Text("home.template")
                Spacer()
                Text(notebook.template.titleKey)
            }
            HStack {
                Text("home.orientation")
                Spacer()
                Text(notebook.orientation.titleKey)
            }
            HStack {
                Text("home.pages")
                Spacer()
                Text("\(notebook.pageCount)")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }
}
