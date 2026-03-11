import SwiftUI
import UniformTypeIdentifiers

private enum HomeRoute: Hashable {
    case notebook(UUID)
}

struct HomeView: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @StateObject private var store = HomeLibraryStore()
    private let thumbnails = NotebookThumbnailService.shared

    @State private var showCreateFolder = false
    @State private var showCreateNotebook = false
    @State private var showPDFImporter = false
    @State private var showSettings = false
    @State private var errorMessage = ""

    @State private var pendingDelete: PendingDeleteAction?
    @State private var pendingRename: PendingRenameAction?

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
                            FolderRow(folder: folder, formattedDate: formattedDate(folder.updatedAtMillis))
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                pendingRename = .folder(folder)
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }

                            Button(role: .destructive) {
                                pendingDelete = .folder(folder)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }

                    let notebooks = store.notebooks(in: store.currentFolderID)
                    if !notebooks.isEmpty {
                        Text("home.section.notebooks")
                            .font(.headline)
                            .padding(.top, 6)
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
                        ForEach(notebooks) { notebook in
                            NavigationLink(value: HomeRoute.notebook(notebook.id)) {
                                NotebookCardView(notebook: notebook, thumbnails: thumbnails)
                            }
                            .simultaneousGesture(TapGesture().onEnded {
                                try? store.touchNotebook(notebook.id)
                            })
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    pendingRename = .notebook(notebook)
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }

                                Button(role: .destructive) {
                                    pendingDelete = .notebook(notebook)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }

                    let resources = store.resources
                        .filter { !$0.isDeleted }
                        .sorted { $0.originalFileName.localizedStandardCompare($1.originalFileName) == .orderedAscending }

                    if !resources.isEmpty {
                        Text("Imported Files")
                            .font(.headline)
                            .padding(.top, 6)
                    }

                    ForEach(resources) { resource in
                        ImportedFileRow(
                            resource: resource,
                            referenceCount: store.referenceCount(for: resource.id)
                        )
                        .contextMenu {
                            Button {
                                pendingRename = .resource(resource)
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }

                            Button(role: .destructive) {
                                pendingDelete = .resource(resource)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("home.title")
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case let .notebook(notebookID):
                    NotebookDetailView(notebookID: notebookID, store: store)
                }
            }
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
        .sheet(item: $pendingRename) { action in
            RenameItemSheet(
                title: action.title,
                initialName: action.currentName
            ) { newName in
                do {
                    try applyRename(action: action, newName: newName)
                    pendingRename = nil
                } catch {
                    errorMessage = humanReadable(error)
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
        .confirmationDialog(
            pendingDelete?.title ?? "Delete",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                do {
                    try performDelete()
                    pendingDelete = nil
                } catch {
                    errorMessage = humanReadable(error)
                }
            }
            Button("Cancel", role: .cancel) {
                pendingDelete = nil
            }
        } message: {
            Text(pendingDelete?.message ?? "")
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

    private func applyRename(action: PendingRenameAction, newName: String) throws {
        switch action {
        case let .folder(folder):
            try store.renameFolder(folder.id, to: newName)
        case let .notebook(notebook):
            try store.renameNotebook(notebook.id, to: newName)
        case let .resource(resource):
            if resource.kind == .pdf {
                try store.renamePDF(resource.id, to: newName)
            } else {
                try store.renameFile(resource.id, to: newName)
            }
        }
    }

    private func performDelete() throws {
        guard let pendingDelete else { return }
        switch pendingDelete {
        case let .folder(folder):
            _ = try store.deleteFolder(folder.id, policy: .deleteIfNoReferences)
        case let .notebook(notebook):
            _ = try store.deleteNotebook(notebook.id, policy: .deleteIfNoReferences)
        case let .resource(resource):
            if resource.kind == .pdf {
                _ = try store.deletePDF(resource.id, policy: .deleteIfNoReferences)
            } else {
                _ = try store.deleteFile(resource.id, policy: .deleteIfNoReferences)
            }
        }
    }

    private func humanReadable(_ error: Error) -> String {
        if let libraryError = error as? HomeLibraryError {
            switch libraryError {
            case .invalidName:
                return "Name is empty or contains invalid characters: / \\ : * ? \" < > |"
            case .resourceInUse:
                return "This file is still referenced by one or more notes."
            default:
                return String(describing: libraryError)
            }
        }
        return error.localizedDescription
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

private enum PendingDeleteAction: Identifiable {
    case folder(NoteFolder)
    case notebook(NotebookRecord)
    case resource(ImportedResource)

    var id: String {
        switch self {
        case let .folder(folder): return "folder-\(folder.id.uuidString)"
        case let .notebook(notebook): return "notebook-\(notebook.id.uuidString)"
        case let .resource(resource): return "resource-\(resource.id.uuidString)"
        }
    }

    var title: String {
        switch self {
        case .folder: return "Delete Folder"
        case .notebook: return "Delete Notebook"
        case let .resource(resource):
            return resource.kind == .pdf ? "Delete PDF" : "Delete File"
        }
    }

    var message: String {
        switch self {
        case let .folder(folder):
            return "Delete folder \"\(folder.name)\" and all nested notebooks?"
        case let .notebook(notebook):
            return "Delete notebook \"\(notebook.title)\"?"
        case let .resource(resource):
            return "Delete file \"\(resource.originalFileName)\"?"
        }
    }
}

private enum PendingRenameAction: Identifiable {
    case folder(NoteFolder)
    case notebook(NotebookRecord)
    case resource(ImportedResource)

    var id: String {
        switch self {
        case let .folder(folder): return "folder-\(folder.id.uuidString)"
        case let .notebook(notebook): return "notebook-\(notebook.id.uuidString)"
        case let .resource(resource): return "resource-\(resource.id.uuidString)"
        }
    }

    var title: String {
        switch self {
        case .folder: return "Rename Folder"
        case .notebook: return "Rename Notebook"
        case let .resource(resource):
            return resource.kind == .pdf ? "Rename PDF" : "Rename File"
        }
    }

    var currentName: String {
        switch self {
        case let .folder(folder): return folder.name
        case let .notebook(notebook): return notebook.title
        case let .resource(resource): return resource.originalFileName
        }
    }
}

private struct FolderRow: View {
    let folder: NoteFolder
    let formattedDate: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.fill")
                .font(.title3)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(folder.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(formattedDate)
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
}

private struct ImportedFileRow: View {
    let resource: ImportedResource
    let referenceCount: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(resource.originalFileName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("\(resource.kind.rawValue.uppercased()) · refs \(referenceCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var iconName: String {
        switch resource.kind {
        case .pdf: return "doc.richtext"
        case .image: return "photo"
        case .font: return "textformat"
        case .file: return "doc"
        case .page, .canvas: return "square.stack"
        }
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

private struct RenameItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let initialName: String
    var onSave: (String) -> Void

    @State private var name: String = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(name)
                        dismiss()
                    }
                }
            }
            .onAppear {
                name = initialName
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
