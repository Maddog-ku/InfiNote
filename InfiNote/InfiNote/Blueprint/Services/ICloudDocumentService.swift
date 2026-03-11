import Foundation

final class ICloudDocumentService {
    func ubiquityDocumentsURL() -> URL? {
        FileManager.default
            .url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents", isDirectory: true)
    }

    func write(data: Data, fileName: String) throws {
        guard let dir = ubiquityDocumentsURL() else { return }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let target = dir.appendingPathComponent(fileName)
        var coordinatorError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: target, options: .forReplacing, error: &coordinatorError) { url in
            try? data.write(to: url, options: .atomic)
        }

        if let coordinatorError { throw coordinatorError }
    }

    func read(fileName: String) throws -> Data? {
        guard let dir = ubiquityDocumentsURL() else { return nil }
        let target = dir.appendingPathComponent(fileName)
        var coordinatorError: NSError?
        var output: Data?
        NSFileCoordinator().coordinate(readingItemAt: target, options: [], error: &coordinatorError) { url in
            output = try? Data(contentsOf: url)
        }

        if let coordinatorError { throw coordinatorError }
        return output
    }
}
