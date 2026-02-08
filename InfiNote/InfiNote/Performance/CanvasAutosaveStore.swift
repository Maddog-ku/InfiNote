//
//  CanvasAutosaveStore.swift
//  InfiNote
//

import Foundation

actor CanvasAutosaveStore {
    static let shared = CanvasAutosaveStore()

    private struct AutosaveBlob: Codable {
        var version: UInt16
        var strokesBinary: Data
        var textBoxes: [CanvasTextBox]
        var savedAtMillis: Int64
    }

    private let fileManager = FileManager.default
    private var pendingTask: Task<Void, Never>?
    private let debounceNanos: UInt64 = 450_000_000

    func scheduleSave(annotations: CanvasPageAnnotations) {
        pendingTask?.cancel()
        pendingTask = Task { [annotations] in
            do {
                try await Task.sleep(nanoseconds: debounceNanos)
                try await persist(annotations: annotations)
            } catch {
                // Ignore cancellation / IO failures for background autosave.
            }
        }
    }

    func loadLatest() -> CanvasPageAnnotations? {
        guard let url = try? autosaveURL(),
              fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let blob = try? JSONDecoder().decode(AutosaveBlob.self, from: data),
              let strokeDoc = try? StrokeCodec.decodeBinary(blob.strokesBinary) else {
            return nil
        }
        return CanvasPageAnnotations(strokes: strokeDoc.strokes, textBoxes: blob.textBoxes)
    }

    private func persist(annotations: CanvasPageAnnotations) async throws {
        let strokesDocument = StrokeDocument(
            formatVersion: StrokeDocument.currentVersion,
            strokes: annotations.strokes
        )
        let blob = AutosaveBlob(
            version: 1,
            strokesBinary: StrokeCodec.encodeBinary(strokesDocument),
            textBoxes: annotations.textBoxes,
            savedAtMillis: Int64(Date().timeIntervalSince1970 * 1000)
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(blob)
        let url = try autosaveURL()
        try data.write(to: url, options: .atomic)
    }

    private func autosaveURL() throws -> URL {
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw HomeLibraryError.appSupportUnavailable
        }
        let directory = appSupport.appendingPathComponent("CanvasAutosave", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory.appendingPathComponent("latest_page.json")
    }
}

