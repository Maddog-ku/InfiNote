import CoreText
import Foundation

enum FontImportError: Error {
    case registerFailed
}

struct FontImportService {
    func registerFont(at securedURL: URL) throws {
        var cfError: Unmanaged<CFError>?
        let ok = CTFontManagerRegisterFontsForURL(securedURL as CFURL, .process, &cfError)
        if !ok {
            _ = cfError?.takeRetainedValue()
            throw FontImportError.registerFailed
        }
    }
}
