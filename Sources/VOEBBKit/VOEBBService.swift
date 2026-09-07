import Foundation

public enum VOEBBError: LocalizedError {
    case loginFailed(String)
    case networkError(String)
    case parseError(String)

    public var errorDescription: String? {
        switch self {
        case .loginFailed(let msg): return "Login fehlgeschlagen: \(msg)"
        case .networkError(let msg): return "Netzwerkfehler: \(msg)"
        case .parseError(let msg): return "Fehler beim Lesen: \(msg)"
        }
    }
}

// Per-account scraping session
public final class VOEBBSession {
    private let baseURL = "https://www.voebb.de"
    private let session: URLSession
    private let account: LibraryAccount

    public init(account: LibraryAccount) {
        self.account = account
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public API

    public func fetchAccountData(password: String) async throws -> AccountData {
        let (appURL, overviewHTML) = try await login(password: password)
        var data = AccountData(account: account)

        // Alles Kontodaten-artige steht direkt auf der Übersichtsseite
        // (<dt>/<dd>-Liste): Gebühren, Abholcode, Ausweisgültigkeit —
        // keine *SGG-Navigation mehr nötig.
        applyFees(fromOverview: overviewHTML, to: &data)
        data.pickupCode = HTMLParser.parseAccountInfo(overviewHTML, term: "Abholcode")
        if let cardValid = HTMLParser.parseAccountInfo(overviewHTML, term: "Ausweis gültig bis") {
            data.cardValidUntil = cardValid
        }
        // VÖBBs Ablauf-Warnung ("Achtung" → "Ausweis läuft in N Tagen ab"):
        // erscheint in der App genau dann, wenn die Webseite sie zeigt.
        data.cardExpiryWarning = HTMLParser.parseAccountInfo(overviewHTML, term: "Achtung")

        let loanCount = HTMLParser.parseLoanCount(overviewHTML)
        let pickupCount = HTMLParser.parsePickupCount(overviewHTML)

        // Alles läuft in DIESER Session: Übersicht → *SZA → Verlängerbarkeits-Probe →
        // "Zur Übersicht" → *SZS → *SE (live verifiziert). Jede Seite liefert ein neues,
        // einmalig gültiges identity-Token, deshalb muss der jeweils nächste Request immer
        // von der zuletzt geladenen Seite ausgehen.
        var currentHTML = overviewHTML

        // loanCount == 0  → definitiv keine Ausleihen
        // loanCount > 0   → Ausleihen vorhanden, Seite abrufen
        // loanCount == nil → Erkennung unsicher, Ausleihen trotzdem probieren
        if loanCount != 0 {
            let (loansHTML, loansURL) = try await navigate(appURL: appURL, fromHTML: overviewHTML, navCode: "*SZA")
            currentHTML = loansHTML
            var parsed = HTMLParser.parseLoans(loansHTML)
            // Ein Parserfehler darf nicht wie ein leeres Konto aussehen.
            do {
                try Self.validateLoans(parsed, expectedCount: loanCount, pageHTML: loansHTML)
            } catch {
                await logout(appURL: appURL, fromHTML: loansHTML)
                throw error
            }

            if !parsed.isEmpty {
                // Verlängerbarkeit per "Markierte Medien verlängerbar?" (read-only) proben.
                // Fehlertolerant: schlägt die Probe hier fehl, wird sie einmal in einer frischen
                // Session wiederholt (der bisherige Weg); bleibt auch die aus, bleiben die
                // Verlängerbarkeits-Felder einfach nil.
                var rows: [RenewabilityRow] = []
                let checkboxes = parsed.map(\.checkboxValue).filter { !$0.isEmpty }
                do {
                    let probe = try await probeRenewability(
                        appURL: appURL, fromHTML: loansHTML, referer: loansURL,
                        checkboxValues: checkboxes
                    )
                    currentHTML = probe.html
                    rows = probe.rows
                } catch {
                    // Session-Zustand jetzt unsicher — der Rücksprung unten fängt das ab.
                }
                if rows.isEmpty {
                    rows = (try? await VOEBBSession(account: account).fetchRenewabilityRows(password: password)) ?? []
                }
                if !rows.isEmpty {
                    let byCheckbox = Dictionary(rows.map { ($0.checkboxValue, $0) },
                                                uniquingKeysWith: { first, _ in first })
                    for i in parsed.indices {
                        if let s = byCheckbox[parsed[i].checkboxValue] {
                            parsed[i].isRenewable = s.renewable
                            parsed[i].renewalReason = s.reason
                        }
                    }
                }
                data.loans = parsed
            }
        }

        // Bereitstellungen (abholbereite Bestellungen): nur wenn die Übersicht welche meldet.
        // Eine Listen-Navigation direkt von einer Listenseite ignoriert aDIS (nach *SZA liefert
        // *SZS still wieder die Ausleihen) — über den "Zur Übersicht"-Button dazwischen klappt
        // sie. Fehlertolerant, Fallback ist der bisherige Weg in einer frischen Session.
        if let pickupCount, pickupCount > 0 {
            var pickups: [PickupItem]?
            do {
                let overviewAgain = try await returnToOverview(appURL: appURL, fromHTML: currentHTML)
                let (html, _) = try await navigate(appURL: appURL, fromHTML: overviewAgain, navCode: "*SZS")
                currentHTML = html
                if HTMLParser.isPickupsPage(html) {
                    pickups = HTMLParser.parsePickups(html)
                }
            } catch {
                // Rücksprung oder Navigation fehlgeschlagen → frische Session unten
            }
            if pickups == nil {
                pickups = try? await VOEBBSession(account: account).fetchPickups(password: password)
            }
            if let pickups {
                data.pickups = pickups
            }
        }

        await logout(appURL: appURL, fromHTML: currentHTML)
        data.lastUpdated = Date()
        return data
    }

    /// Zurück zur Kontoübersicht über den "Zur Übersicht"-Button der aktuellen Seite (per
    /// Beschriftung gesucht, die Buttonnummer variiert je Seite). Ist die aktuelle Seite schon
    /// die Übersicht, wird sie unverändert zurückgegeben. Wirft, wenn kein Button gefunden
    /// wird oder die Antwort keine Übersicht ist — der Aufrufer fällt dann auf eine frische
    /// Session zurück.
    private func returnToOverview(appURL: String, fromHTML: String) async throws -> String {
        if HTMLParser.isOverviewPage(fromHTML) { return fromHTML }
        guard let button = HTMLParser.findSubmitButton(labelContaining: "Zur Übersicht", in: fromHTML) else {
            throw VOEBBError.parseError("„Zur Übersicht“-Button nicht gefunden")
        }
        let html = try await pressButton(appURL: appURL, fromHTML: fromHTML, referer: appURL,
                                         buttonField: button, focusID: "", checkboxValues: [])
        guard HTMLParser.isOverviewPage(html) else {
            throw VOEBBError.parseError("Rücksprung lieferte keine Kontoübersicht")
        }
        return html
    }

    /// Fallback in einer frischen Session: Login → Bereitstellungen (*SZS) → Logout.
    /// Regulär holt fetchAccountData die Bereitstellungen in derselben Session per Rücksprung.
    private func fetchPickups(password: String) async throws -> [PickupItem] {
        let (appURL, overviewHTML) = try await login(password: password)
        let (html, _) = try await navigate(appURL: appURL, fromHTML: overviewHTML, navCode: "*SZS")
        await logout(appURL: appURL, fromHTML: html)
        guard HTMLParser.isPickupsPage(html) else {
            throw VOEBBError.parseError("Bereitstellungs-Seite nicht erkannt")
        }
        return HTMLParser.parsePickups(html)
    }

    /// Fallback in einer frischen Session: Login → Ausleihen → "Markierte Medien
    /// verlängerbar?"-Probe. Regulär probt fetchAccountData in derselben Session; dieser Weg
    /// läuft nur, wenn die Probe dort unlesbar war oder fehlschlug.
    private func fetchRenewabilityRows(password: String) async throws -> [RenewabilityRow] {
        let (appURL, overviewHTML) = try await login(password: password)
        let (loansHTML, loansURL) = try await navigate(appURL: appURL, fromHTML: overviewHTML, navCode: "*SZA")
        let loans = HTMLParser.parseLoans(loansHTML)
        let checkboxes = loans.map(\.checkboxValue).filter { !$0.isEmpty }
        guard !checkboxes.isEmpty else { return [] }

        let probe = try await probeRenewability(
            appURL: appURL, fromHTML: loansHTML, referer: loansURL,
            checkboxValues: checkboxes
        )
        await logout(appURL: appURL, fromHTML: probe.html)
        return probe.rows
    }

    /// Plausibilisiert die geparste Ausleihliste gegen die Zahl aus der Kontoübersicht.
    /// Meldet die Übersicht N Ausleihen, die Seite liefert aber weniger (oder gar keine
    /// erkennbare Ausleihliste), ist das ein Parser-/Seitenfehler — kein leeres Konto.
    static func validateLoans(_ parsed: [Loan], expectedCount: Int?, pageHTML: String) throws {
        if let expected = expectedCount {
            guard expected > 0 else { return }  // Übersicht sagt explizit: keine Ausleihen
            if parsed.isEmpty {
                throw VOEBBError.parseError("Ausleihseite nicht lesbar – die Übersicht meldet \(expected) Ausleihen")
            }
            if parsed.count < expected {
                throw VOEBBError.parseError("Nur \(parsed.count) von \(expected) Ausleihen gelesen")
            }
        } else if parsed.isEmpty {
            // Übersicht war nicht lesbar: dann muss wenigstens die Seite als Ausleihliste erkennbar sein
            let looksLikeLoansPage = pageHTML.contains("Meine Ausleihen") || pageHTML.contains("rTable")
            if !looksLikeLoansPage {
                throw VOEBBError.parseError("Ausleihseite nicht erkannt")
            }
        }
    }

    /// Liest die fälligen Gebühren aus der <dl>-Liste der Kontoübersicht.
    /// Fehlt die Gebühren-Zeile, die Übersicht ist aber als solche erkennbar
    /// (andere <dt>-Begriffe vorhanden), gilt das als 0 € — ist die Seite gar nicht
    /// als Übersicht erkennbar, wird `feesUnknown` gesetzt, statt still 0 zu melden.
    private func applyFees(fromOverview html: String, to data: inout AccountData) {
        if let raw = HTMLParser.parseAccountInfo(html, term: "Fällige Gebühren"),
           let amount = HTMLParser.parseAmount(raw) {
            data.fees = amount
        } else if HTMLParser.parseAccountInfo(html, term: "Kontostand vom:") != nil
                    || HTMLParser.parseAccountInfo(html, term: "Abholcode") != nil {
            data.fees = 0
        } else {
            data.feesUnknown = true
        }
    }

    /// Meldet die aDIS-Session serverseitig ab (Nav-Code *SE) — Fire-and-forget,
    /// Fehler werden bewusst ignoriert. Reduziert verwaiste Sessions beim VÖBB.
    private func logout(appURL: String, fromHTML: String) async {
        _ = try? await navigate(appURL: appURL, fromHTML: fromHTML, navCode: "*SE")
    }

    /// Renews all renewable loans.
    public func renewAllLoans(password: String) async throws -> RenewalOutcome {
        try await renewLoans(password: password) { _ in true }
    }

    /// Renews only loans due within `days` days (overdue included), and only those.
    public func renewDueLoans(password: String, withinDays days: Int) async throws -> RenewalOutcome {
        try await renewLoans(password: password) { $0.daysUntilDue <= days }
    }

    /// Renews a single loan. Matched by title + due date + library within the freshly
    /// fetched loans list — checkbox values are session-specific and must not be reused
    /// across logins.
    public func renewLoan(password: String, matching loan: Loan) async throws -> RenewalOutcome {
        try await renewLoans(password: password) {
            $0.title == loan.title &&
            $0.dueDateString == loan.dueDateString &&
            $0.library == loan.library
        }
    }

    /// Renewal is a two-step flow because BOTH "Alle verlängern" and "Markierte Medien
    /// verlängern" abort the entire batch if a single selected item is blocked (e.g. by a
    /// Vormerkung). So we first probe renewability ("Markierte Medien verlängerbar?",
    /// $Button$2) on the selected candidates, then submit only the confirmed-renewable ones
    /// ("Markierte Medien verlängern", $Button$1). See memory `voebb-renewal-button-mapping`.
    /// `select` narrows which loans are considered (e.g. only soon-due ones).
    private func renewLoans(password: String, selecting select: (Loan) -> Bool) async throws -> RenewalOutcome {
        let (appURL, overviewHTML) = try await login(password: password)

        let (loansHTML, loansURL) = try await navigate(appURL: appURL, fromHTML: overviewHTML, navCode: "*SZA")
        let loans = HTMLParser.parseLoans(loansHTML)
        // Eine unlesbare Ausleihseite darf nicht als "Keine Ausleihen vorhanden" enden.
        do {
            try Self.validateLoans(loans, expectedCount: HTMLParser.parseLoanCount(overviewHTML), pageHTML: loansHTML)
        } catch {
            await logout(appURL: appURL, fromHTML: loansHTML)
            throw error
        }

        guard !loans.isEmpty else {
            await logout(appURL: appURL, fromHTML: loansHTML)
            return RenewalOutcome(specialMessage: "Keine Ausleihen vorhanden")
        }

        // Only the selected candidates are probed/renewed — never touch the others.
        let candidateCheckboxes = loans.filter(select).map(\.checkboxValue).filter { !$0.isEmpty }
        guard !candidateCheckboxes.isEmpty else {
            await logout(appURL: appURL, fromHTML: loansHTML)
            return RenewalOutcome()
        }

        // Step 1: probe "verlängerbar?" ($Button$2) with only the candidates checked.
        let probe = try await probeRenewability(
            appURL: appURL, fromHTML: loansHTML, referer: loansURL,
            checkboxValues: candidateCheckboxes
        )
        // The probe reports on the marked media; restrict to our candidate set defensively.
        let candidateSet = Set(candidateCheckboxes)
        let statuses = probe.rows.filter { candidateSet.contains($0.checkboxValue) }
        // Jede markierte Zeile muss einen Marker tragen — sonst ist die Antwort keine
        // Probe-Seite (Session-Fehler o.ä.) und der Status der Medien unbekannt.
        guard statuses.count == candidateCheckboxes.count else {
            await logout(appURL: appURL, fromHTML: probe.html)
            throw VOEBBError.parseError(
                "Verlängerbarkeits-Prüfung nicht lesbar (\(statuses.count) von \(candidateCheckboxes.count) Medien erkannt)"
            )
        }
        let renewable = statuses.filter { $0.renewable }
        let blocked = statuses.filter { !$0.renewable }

        guard !renewable.isEmpty else {
            await logout(appURL: appURL, fromHTML: probe.html)
            return RenewalOutcome(renewed: [], blocked: blocked)
        }

        // Step 2: renew only the confirmed-renewable candidates ($Button$1).
        let resultHTML = try await pressButton(
            appURL: appURL, fromHTML: probe.html, referer: appURL,
            buttonField: "$Button$1", focusID: "$$GFBO_4",
            checkboxValues: renewable.map(\.checkboxValue)
        )

        // Erfolg nur pro Medium anhand des verschobenen Fälligkeitsdatums auf der
        // Antwortseite melden — nie allein aus dem Probe-Ergebnis ableiten.
        let verification = RenewalVerifier.verify(
            submitted: renewable,
            before: loans,
            after: HTMLParser.parseLoans(resultHTML)
        )

        await logout(appURL: appURL, fromHTML: resultHTML)
        return RenewalOutcome(
            renewed: verification.confirmed,
            blocked: blocked,
            unconfirmed: verification.unconfirmed,
            unverifiable: verification.unverifiable
        )
    }

    /// Presses "Markierte Medien verlängerbar?" ($Button$2, read-only) for the given
    /// checkboxes and parses the per-row renewability markers from the response.
    private func probeRenewability(
        appURL: String, fromHTML: String, referer: String,
        checkboxValues: [String]
    ) async throws -> (html: String, rows: [RenewabilityRow]) {
        let html = try await pressButton(
            appURL: appURL, fromHTML: fromHTML, referer: referer,
            buttonField: "$Button$2", focusID: "$$GFBO_7",
            checkboxValues: checkboxValues
        )
        return (html, HTMLParser.parseRenewability(html))
    }

    /// Presses a `$Button$N` submit button by re-POSTing the page's hidden fields plus the
    /// selected checkboxes (empty for plain navigation buttons like "Zur Übersicht"; `focusID`
    /// may be empty — live-verified). aDISWeb expects duplicate `$RTable_checkbox[]` keys, so
    /// the body is encoded manually (URLSession can't send duplicate keys via a dictionary).
    private func pressButton(
        appURL: String, fromHTML: String, referer: String,
        buttonField: String, focusID: String,
        checkboxValues: [String]
    ) async throws -> String {
        var postData = extractHiddenInputs(fromHTML)
        _ = try Self.requiredRequestCount(in: postData)
        postData["scriptEnabled"] = "true"
        postData["overrideScrollPos"] = "0"
        postData["focus"] = focusID
        postData["source"] = "$B"
        postData[buttonField] = "pressed"

        var parts: [String] = []
        for (k, v) in postData {
            parts.append("\(urlEncode(k))=\(urlEncode(v))")
        }
        for cbVal in checkboxValues {
            parts.append("$RTable_checkbox%5B%5D=\(urlEncode(cbVal))")
        }
        let body = parts.joined(separator: "&")

        return try await postRaw(url: appURL, body: body, referer: referer)
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

    // Der aDIS-Request-Zähler (`requestCount`) ist ein hidden field jeder Seite und wird
    // wie im Browser unverändert zurückgesendet — nie mit festen Werten überschreiben:
    // die Sequenz hängt von der Session-Historie ab (nach Login z.B. 5, nicht 3).

    /// aDIS erwartet den Zähler bei jedem Folge-Request. Fehlt er, ist die aktuelle Seite
    /// keine reguläre aDIS-Seite (Session abgelaufen, Fehlerseite) — dann lieber sauber
    /// abbrechen als einen kaputten Request abzuschicken.
    static func requiredRequestCount(in hidden: [String: String]) throws -> String {
        guard let rc = hidden["requestCount"], Int(rc) != nil else {
            throw VOEBBError.parseError("Seite ohne gültigen Request-Zähler – Sitzung ungültig?")
        }
        return rc
    }

    private func navigate(appURL: String, fromHTML: String, navCode: String) async throws -> (html: String, url: String) {
        var data = extractHiddenInputs(fromHTML)
        _ = try Self.requiredRequestCount(in: data)
        data["scriptEnabled"] = "true"
        data["overrideScrollPos"] = "0"
        data["selected"] = "ZTEXT       \(navCode)"
        data["$Select"] = "Überall suchen"

        let html = try await post(url: appURL, data: data, referer: appURL)
        return (html, appURL)
    }

    // MARK: - Private: HTTP

    private func get(url: String) async throws -> String {
        var req = URLRequest(url: URL(string: url)!)
        req.addValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        req.addValue("de-DE,de;q=0.9", forHTTPHeaderField: "Accept-Language")
        req.addValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: req)
        try Self.checkStatus(response)
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
    }

    /// aDIS antwortet fachlich immer mit 200; ein 4xx/5xx ist ein Infrastruktur-Fehler,
    /// dessen Fehlerseite nie als "leere Liste" oder "Erfolg" durchgehen darf.
    private static func checkStatus(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode >= 400 {
            throw VOEBBError.networkError("Server antwortet mit HTTP \(http.statusCode)")
        }
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
        try Self.checkStatus(response)
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
    }

    // MARK: - Helpers

    private func extractHiddenInputs(_ html: String) -> [String: String] {
        HTMLParser.extractHiddenInputs(html)
    }

    private func urlEncode(_ string: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }
}
