import Foundation

enum VOEBBError: LocalizedError {
    case loginFailed(String)
    case networkError(String)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .loginFailed(let msg): return "Login fehlgeschlagen: \(msg)"
        case .networkError(let msg): return "Netzwerkfehler: \(msg)"
        case .parseError(let msg): return "Fehler beim Lesen: \(msg)"
        }
    }
}

// Per-account scraping session
final class VOEBBSession {
    private let baseURL = "https://www.voebb.de"
    private let session: URLSession
    private let account: LibraryAccount

    init(account: LibraryAccount) {
        self.account = account
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public API

    func fetchAccountData(password: String) async throws -> AccountData {
        let (appURL, overviewHTML) = try await login(password: password)
        var data = AccountData(account: account)

        let loanCount = HTMLParser.parseLoanCount(overviewHTML)

        // loanCount == 0  → definitiv keine Ausleihen, direkt zu Gebühren
        // loanCount > 0   → Ausleihen vorhanden, Seite abrufen
        // loanCount == nil → Erkennung unsicher, Ausleihen trotzdem probieren
        if loanCount != 0 {
            let (loansHTML, _) = try await navigate(appURL: appURL, fromHTML: overviewHTML, navCode: "*SZA", rc: 3)
            let parsed = HTMLParser.parseLoans(loansHTML)
            data.loans = parsed

            // Gebühren: von der Ausleihseite aus (rc=4) falls Bücher gefunden,
            // sonst von der Übersicht (rc=3) – Fallback falls *SZA kein loans-HTML lieferte
            if !parsed.isEmpty {
                let (feesHTML, _) = try await navigate(appURL: appURL, fromHTML: loansHTML, navCode: "*SGG", rc: 4)
                let (fees, cardValid) = HTMLParser.parseFees(feesHTML)
                data.fees = fees
                data.cardValidUntil = cardValid
            } else {
                let (feesHTML, _) = try await navigate(appURL: appURL, fromHTML: overviewHTML, navCode: "*SGG", rc: 3)
                let (fees, cardValid) = HTMLParser.parseFees(feesHTML)
                data.fees = fees
                data.cardValidUntil = cardValid
            }
        } else {
            // Keine Ausleihen laut Übersicht → direkt Gebühren
            let (feesHTML, _) = try await navigate(appURL: appURL, fromHTML: overviewHTML, navCode: "*SGG", rc: 3)
            let (fees, cardValid) = HTMLParser.parseFees(feesHTML)
            data.fees = fees
            data.cardValidUntil = cardValid
        }

        data.lastUpdated = Date()
        return data
    }

    func renewAllLoans(password: String) async throws -> String {
        let (appURL, overviewHTML) = try await login(password: password)

        let (loansHTML, loansURL) = try await navigate(appURL: appURL, fromHTML: overviewHTML, navCode: "*SZA", rc: 3)
        let loans = HTMLParser.parseLoans(loansHTML)

        guard !loans.isEmpty else { return "Keine Ausleihen vorhanden" }

        // Extract hidden fields from loans page
        let hidden = extractHiddenInputs(loansHTML)

        // Build POST with all checkboxes selected
        var postData = hidden
        postData["requestCount"] = "4"
        postData["scriptEnabled"] = "true"
        postData["overrideScrollPos"] = "0"
        postData["focus"] = "$$GFBO_11"
        postData["source"] = "$B"
        postData["$Button$0"] = "pressed"

        // Add all checkboxes
        let checkboxValues = loans.map { $0.checkboxValue }.filter { !$0.isEmpty }
        // URLSession doesn't natively support duplicate keys, so we encode manually
        var parts: [String] = []
        for (k, v) in postData {
            parts.append("\(urlEncode(k))=\(urlEncode(v))")
        }
        for cbVal in checkboxValues {
            parts.append("$RTable_checkbox%5B%5D=\(urlEncode(cbVal))")
        }
        let body = parts.joined(separator: "&")

        let resultHTML = try await postRaw(url: appURL, body: body, referer: loansURL)
        return HTMLParser.parseRenewalResult(resultHTML)
    }

    // MARK: - Private: Login

    private func login(password: String) async throws -> (appURL: String, overviewHTML: String) {
        // 1. Load main page to get session ID from form action
        let mainHTML = try await get(url: "\(baseURL)/aDISWeb/app/prod00?sp=SPROD00")
        guard let sessionMatch = mainHTML.range(of: #"/aDISWeb/(_[a-z0-9]+)/app"#, options: .regularExpression) else {
            throw VOEBBError.loginFailed("Session-ID nicht gefunden")
        }
        let sessionMatchStr = String(mainHTML[sessionMatch])
        guard let sessionIDRange = sessionMatchStr.range(of: #"_[a-z0-9]+"#, options: .regularExpression) else {
            throw VOEBBError.loginFailed("Session-ID nicht extrahierbar")
        }
        let sessionID = String(sessionMatchStr[sessionIDRange])
        let formActionURL = "\(baseURL)/aDISWeb/\(sessionID)/app"

        // 2. POST navigation to account section → triggers OIDC redirect
        var navData = extractHiddenInputs(mainHTML)
        navData["scriptEnabled"] = "true"
        navData["overrideScrollPos"] = "0"
        navData["selected"] = "ZTEXT       *SBK"
        navData["$Select"] = "Überall suchen"
        _ = try await post(url: formActionURL, data: navData, referer: "\(baseURL)/aDISWeb/app/prod00")

        // 3. POST credentials
        let loginData: [String: String] = [
            "L#AUSW": account.cardNumber,
            "LPASSW": password,
            "LLOGIN": "Login",
        ]
        let afterLoginHTML = try await post(
            url: "\(baseURL)/oidcp/logincheck",
            data: loginData,
            referer: "\(baseURL)/oidcp/authorize"
        )

        if afterLoginHTML.contains("schiefgegangen") || afterLoginHTML.contains("ausgeschalteten Cookies") {
            throw VOEBBError.loginFailed("Cookie-Problem. Bitte erneut versuchen.")
        }
        if afterLoginHTML.contains("Ungültig") || afterLoginHTML.contains("ungültig") ||
           afterLoginHTML.contains("nicht korrekt") {
            throw VOEBBError.loginFailed("Ausweisnummer oder Passwort falsch")
        }

        // Extract new session ID from current URL (stored in response header tracking)
        // Parse from the HTML's form action or JS
        // Extract session ID: look in form action or JS timeout URL
        let sessionSources = [
            (#"/aDISWeb/(_[a-z0-9]+)/app"#, #"_[a-z0-9]+"#),
            (#"/_[a-z0-9]+/timeout"#, #"_[a-z0-9]+"#),
        ]
        var newSessionID: String?
        for (outerPattern, innerPattern) in sessionSources {
            if let outerRange = afterLoginHTML.range(of: outerPattern, options: .regularExpression) {
                let outerStr = String(afterLoginHTML[outerRange])
                if let innerRange = outerStr.range(of: innerPattern, options: .regularExpression) {
                    newSessionID = String(outerStr[innerRange])
                    break
                }
            }
        }
        guard let sid = newSessionID else {
            throw VOEBBError.loginFailed("Session nach Login nicht gefunden")
        }
        let appURL = "\(baseURL)/aDISWeb/\(sid)/app"
        return (appURL, afterLoginHTML)
    }

    // MARK: - Private: Navigation

    private func navigate(appURL: String, fromHTML: String, navCode: String, rc: Int) async throws -> (html: String, url: String) {
        var data = extractHiddenInputs(fromHTML)
        data["scriptEnabled"] = "true"
        data["overrideScrollPos"] = "0"
        data["requestCount"] = "\(rc)"
        data["selected"] = "ZTEXT       \(navCode)"
        data["$Select"] = "Überall suchen"

        let html = try await post(url: appURL, data: data, referer: appURL)
        return (html, appURL)
    }

    // MARK: - Private: HTTP

    private var lastURL = ""

    private func get(url: String) async throws -> String {
        var req = URLRequest(url: URL(string: url)!)
        req.addValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        req.addValue("de-DE,de;q=0.9", forHTTPHeaderField: "Accept-Language")
        req.addValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: req)
        lastURL = (response as? HTTPURLResponse)?.url?.absoluteString ?? url
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
    }

    private func post(url: String, data: [String: String], referer: String) async throws -> String {
        let body = data.map { "\(urlEncode($0.key))=\(urlEncode($0.value))" }.joined(separator: "&")
        return try await postRaw(url: url, body: body, referer: referer)
    }

    private func postRaw(url: String, body: String, referer: String) async throws -> String {
        var req = URLRequest(url: URL(string: url)!)
        req.httpMethod = "POST"
        req.httpBody = body.data(using: .utf8)
        req.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.addValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        req.addValue("de-DE,de;q=0.9", forHTTPHeaderField: "Accept-Language")
        req.addValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        if !referer.isEmpty {
            req.addValue(referer, forHTTPHeaderField: "Referer")
        }

        let (data, response) = try await session.data(for: req)
        lastURL = (response as? HTTPURLResponse)?.url?.absoluteString ?? url
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
    }

    // MARK: - Helpers

    private func extractHiddenInputs(_ html: String) -> [String: String] {
        var result: [String: String] = [:]
        let pattern = try! NSRegularExpression(
            pattern: #"<input[^>]+type=['"]hidden['"][^>]*>"#,
            options: .caseInsensitive
        )
        let matches = pattern.matches(in: html, range: NSRange(html.startIndex..., in: html))
        for match in matches {
            guard let range = Range(match.range, in: html) else { continue }
            let tag = String(html[range])
            let name = extractAttr(tag, attr: "name")
            let value = extractAttr(tag, attr: "value") ?? ""
            if let name = name { result[name] = value }
        }
        return result
    }

    private func extractAttr(_ tag: String, attr: String) -> String? {
        let pattern = "\(attr)=['\"]([^'\"]*)['\"]"
        guard let m = tag.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { return nil }
        let matchStr = String(tag[m])
        // Extract value between quotes
        let parts = matchStr.components(separatedBy: CharacterSet(charactersIn: "\"'"))
        return parts.count >= 2 ? parts[1] : nil
    }

    private func urlEncode(_ string: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }
}
