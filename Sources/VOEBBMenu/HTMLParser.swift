import Foundation

enum HTMLParser {
    // MARK: - Overview Page

    static func parseLoanCount(_ html: String) -> Int? {
        // Suche NUR innerhalb des #konto-services Blocks, damit
        // "Keine Ausleihen" in der Navigationsleiste nicht stört.
        let servicesHTML = extractKontoServices(html) ?? html

        if servicesHTML.contains("Keine Ausleihen") { return 0 }
        if let m = servicesHTML.range(of: #"(\d+)\s+Ausleihen"#, options: .regularExpression),
           let numStr = String(servicesHTML[m]).split(separator: " ").first,
           let n = Int(numStr) {
            return n
        }
        return nil
    }

    private static func extractKontoServices(_ html: String) -> String? {
        guard let start = html.range(of: #"id="konto-services""#, options: .regularExpression) else { return nil }
        // Suche das Ende des Blocks: </section> oder </div> nach dem Start
        let tail = html[start.lowerBound...]
        if let end = tail.range(of: "</section>") {
            return String(tail[tail.startIndex..<end.upperBound])
        }
        return String(tail.prefix(2000))
    }

    // MARK: - Loans Page

    static func parseLoans(_ html: String) -> [Loan] {
        var loans: [Loan] = []
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy"
        formatter.locale = Locale(identifier: "de_DE")

        // Extract <tr> rows from the rTable_table
        let trPattern = try! NSRegularExpression(
            pattern: #"<tr[^>]*class="[^"]*rTable_tr[^"]*"[^>]*>(.*?)</tr>"#,
            options: [.dotMatchesLineSeparators, .caseInsensitive]
        )
        let fullRange = NSRange(html.startIndex..., in: html)
        let matches = trPattern.matches(in: html, range: fullRange)

        for match in matches {
            guard let rowRange = Range(match.range(at: 1), in: html) else { continue }
            let rowHTML = String(html[rowRange])

            guard let loan = parseLoanRow(rowHTML, formatter: formatter) else { continue }
            loans.append(loan)
        }

        return loans
    }

    private static func parseLoanRow(_ rowHTML: String, formatter: DateFormatter) -> Loan? {
        // Current VÖBB HTML layout: all columns use rTable_td_text
        // Column order: [0]=date, [1]=library, [2]=title, [3]=status
        let textCols = extractAllTDContents(rowHTML, classFragment: "rTable_td_text")
        guard textCols.count >= 4 else { return nil }

        let dateStr = stripHTML(textCols[0]).trimmingCharacters(in: .whitespaces)
        guard let dueDate = formatter.date(from: dateStr) else { return nil }

        let library = stripHTML(textCols[1]).trimmingCharacters(in: .whitespaces)

        // Title column: split on <br>, skip leading media-type tags like [DVD-Video]
        let titleParts = textCols[2]
            .components(separatedBy: "<br>")
            .map { stripHTML($0).trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "¬", with: "") }
            .filter { !$0.isEmpty }
        // A media-type indicator looks like "[DVD-Video]", "[ND-Video]", "[Blu-ray]" etc.
        let mediaTypePattern = try! NSRegularExpression(pattern: #"^\[.+\]$"#)
        let title = titleParts.first(where: {
            mediaTypePattern.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) == nil
        }) ?? titleParts.first ?? ""

        let status = stripHTML(textCols[3]).trimmingCharacters(in: .whitespaces)

        // Checkbox value for renewal
        let cbPattern = try! NSRegularExpression(
            pattern: #"value="(CheckCell[^"]*)"#,
            options: .caseInsensitive
        )
        let cbMatch = cbPattern.firstMatch(in: rowHTML, range: NSRange(rowHTML.startIndex..., in: rowHTML))
        let cbValue = cbMatch.flatMap { Range($0.range(at: 1), in: rowHTML).map { String(rowHTML[$0]) } } ?? ""

        return Loan(
            title: title,
            dueDate: dueDate,
            dueDateString: dateStr,
            library: library,
            renewalStatus: status,
            checkboxValue: cbValue
        )
    }

    // MARK: - Fees Page

    static func parseFees(_ html: String) -> (fees: Double, cardValid: String) {
        var fees = 0.0
        var cardValid = ""

        // Pattern: Fällige Gebühren 1.00
        // Also: 1.00 EUR at the end
        let feePatterns = [
            #"Fällige Gebühren\s+([\d,\.]+)"#,
            #"([\d]+[,\.][\d]+)\s*EUR"#,
        ]
        for pattern in feePatterns {
            if let m = html.range(of: pattern, options: .regularExpression) {
                let matchStr = String(html[m])
                // Extract number
                let numPattern = try! NSRegularExpression(pattern: #"([\d]+[,\.][\d]+)"#)
                let matchRange = NSRange(matchStr.startIndex..., in: matchStr)
                if let numMatch = numPattern.firstMatch(in: matchStr, range: matchRange),
                   let numRange = Range(numMatch.range(at: 1), in: matchStr) {
                    let numStr = String(matchStr[numRange])
                        .replacingOccurrences(of: ",", with: ".")
                    fees = Double(numStr) ?? 0
                    break
                }
            }
        }

        // Card validity: "Ausweis gültig bis 5.7.2026"
        if let m = html.range(of: #"Ausweis gültig bis\s+([^\s<]+)"#, options: .regularExpression) {
            let matchStr = String(html[m])
            cardValid = matchStr
                .replacingOccurrences(of: "Ausweis gültig bis", with: "")
                .trimmingCharacters(in: .whitespaces)
        }

        return (fees, cardValid)
    }

    // MARK: - Renewal Result

    static func parseRenewalResult(_ html: String) -> String {
        // Look for success or error messages
        let clean = stripHTML(html)
        if clean.localizedCaseInsensitiveContains("wurde verlängert") ||
           clean.localizedCaseInsensitiveContains("erfolgreich") {
            return "Verlängerung erfolgreich"
        }
        if clean.localizedCaseInsensitiveContains("nicht möglich") {
            return "Verlängerung noch nicht möglich"
        }
        if clean.localizedCaseInsensitiveContains("bereits verlängert") {
            return "Bereits verlängert"
        }
        return "Unbekanntes Ergebnis"
    }

    // MARK: - Helpers

    private static func extractTDContent(_ html: String, classFragment: String) -> String? {
        let pattern = #"<td[^>]*class="[^"]*\b"# + classFragment + #"\b[^"]*"[^>]*>(.*?)</td>"#
        guard let m = html.range(of: pattern, options: [.regularExpression, .caseInsensitive],
                                  range: html.startIndex..<html.endIndex) else { return nil }
        let matchStr = String(html[m])
        // Extract content between > and </td>
        if let start = matchStr.range(of: ">")?.upperBound,
           let end = matchStr.range(of: "</td>", options: .backwards)?.lowerBound {
            return String(matchStr[start..<end])
        }
        return nil
    }

    private static func extractAllTDContents(_ html: String, classFragment: String) -> [String] {
        var results: [String] = []
        let pattern = #"<td[^>]*class="[^"]*\b"# + classFragment + #"\b[^"]*"[^>]*>(.*?)</td>"#
        let regex = try! NSRegularExpression(
            pattern: pattern,
            options: [.dotMatchesLineSeparators, .caseInsensitive]
        )
        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        for match in matches {
            if let range = Range(match.range(at: 1), in: html) {
                results.append(String(html[range]))
            }
        }
        return results
    }

    static func stripHTML(_ html: String) -> String {
        var result = html
        // Remove tags
        result = result.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        // Decode common HTML entities
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        result = result.replacingOccurrences(of: "&nbsp;", with: " ")
        result = result.replacingOccurrences(of: "&#160;", with: " ")
        // Collapse whitespace
        result = result.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespaces)
    }
}
