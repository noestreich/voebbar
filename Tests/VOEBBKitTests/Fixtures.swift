import Foundation
import XCTest

/// Anonymisierte VÖBB-Seiten aus einer echten Sitzung (siehe anonymize_fixtures.py).
enum Fixture {
    static func html(_ name: String, file: StaticString = #filePath, line: UInt = #line) -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: "html", subdirectory: "Fixtures"),
              let html = try? String(contentsOf: url, encoding: .utf8)
        else {
            XCTFail("Fixture \(name).html fehlt", file: file, line: line)
            return ""
        }
        return html
    }

    static var overview: String { html("overview") }
    static var loans: String { html("loans") }

    /// Eine aDIS-Seite, die weder Übersicht noch Ausleihliste ist (Session-Fehler o.ä.).
    static let unexpectedPage = """
    <html><head><title>Fehler - Verbund der Öffentlichen Bibliotheken Berlins</title></head>
    <body><form action="/aDISWeb/_x/app" method="post">
    <input type="hidden" name="identity" value="abc">
    <p>Ihre Sitzung ist abgelaufen. Bitte melden Sie sich erneut an.</p>
    </form></body></html>
    """
}
