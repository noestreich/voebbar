import XCTest
@testable import VOEBBKit

final class OverviewParserTests: XCTestCase {
    func testLoanCountFromServices() {
        XCTAssertEqual(HTMLParser.parseLoanCount(Fixture.overview), 26)
    }

    func testAccountInfoFields() {
        let html = Fixture.overview
        XCTAssertEqual(HTMLParser.parseAccountInfo(html, term: "Fällige Gebühren"), "0.40 EUR")
        XCTAssertEqual(HTMLParser.parseAccountInfo(html, term: "Ausweis gültig bis"), "12.08.2027")
        XCTAssertEqual(HTMLParser.parseAccountInfo(html, term: "Abholcode"), "00 Xx")
        XCTAssertNotNil(HTMLParser.parseAccountInfo(html, term: "Kontostand vom:"))
        // Kein Ablauf-Hinweis auf dieser Übersicht
        XCTAssertNil(HTMLParser.parseAccountInfo(html, term: "Achtung"))
    }

    func testAmountParsing() {
        XCTAssertEqual(HTMLParser.parseAmount("0.40 EUR"), 0.40)
        XCTAssertEqual(HTMLParser.parseAmount("1,50"), 1.5)
        XCTAssertEqual(HTMLParser.parseAmount("12 EUR"), 12)
        XCTAssertNil(HTMLParser.parseAmount("keine"))
    }

    func testUnexpectedPageYieldsNothing() {
        XCTAssertNil(HTMLParser.parseLoanCount(Fixture.unexpectedPage))
        XCTAssertNil(HTMLParser.parseAccountInfo(Fixture.unexpectedPage, term: "Fällige Gebühren"))
        XCTAssertNil(HTMLParser.parseAccountInfo(Fixture.unexpectedPage, term: "Abholcode"))
    }
}

final class LoansParserTests: XCTestCase {
    func testParsesAllRows() {
        let loans = HTMLParser.parseLoans(Fixture.loans)
        XCTAssertEqual(loans.count, 26)
        XCTAssertTrue(loans.allSatisfy { !$0.title.isEmpty }, "Jede Zeile braucht einen Titel")
        XCTAssertTrue(loans.allSatisfy { !$0.library.isEmpty }, "Jede Zeile braucht eine Bibliothek")
        XCTAssertTrue(loans.allSatisfy { $0.checkboxValue.hasPrefix("CheckCell") })
        XCTAssertEqual(Set(loans.map(\.checkboxValue)).count, 26, "Checkbox-Werte sind eindeutig")
    }

    func testRowDetails() {
        let loans = HTMLParser.parseLoans(Fixture.loans)
        let first = loans[0]
        XCTAssertEqual(first.dueDateString, "09.09.2026")
        XCTAssertEqual(first.library, "Friedrichshain-Kreuzberg: Bezirkszentralbibliothek Pablo Neruda")
        XCTAssertEqual(first.title, "W1 : W2 / W3 W4", "Nur die erste Titelzeile, ohne Signatur/Mediennummer")
        XCTAssertTrue(first.renewalStatus.contains("Vormerkungen"))

        // "¬Die¬"-Artikelmarkierung wird entfernt
        XCTAssertEqual(loans[1].title, "W6 W7 : W2 / W8 W9")
        // VÖBB-Platzhalter "X" als Verantwortlicher bleibt im Rohtitel erhalten (Filter ist UI-Sache)
        XCTAssertTrue(loans[2].title.hasSuffix(" / X"))
    }

    func testTitleColumnCleanup() {
        XCTAssertEqual(HTMLParser.cleanTitleColumn("[DVD-Video]<br>Der Film / Regie<br>Sig"), "Der Film / Regie")
        XCTAssertEqual(HTMLParser.cleanTitleColumn("¬Das¬ Buch<br>Sig<br>123"), "Das Buch")
        XCTAssertEqual(HTMLParser.cleanTitleColumn("Nur Titel"), "Nur Titel")
        XCTAssertEqual(HTMLParser.cleanTitleColumn(""), "")
    }

    func testUnexpectedPageYieldsEmptyList() {
        XCTAssertEqual(HTMLParser.parseLoans(Fixture.unexpectedPage).count, 0)
        XCTAssertEqual(HTMLParser.parseLoans("").count, 0)
    }
}

final class RenewabilityParserTests: XCTestCase {
    func testMarkersOnLoansPage() {
        let rows = HTMLParser.parseRenewability(Fixture.loans)
        XCTAssertEqual(rows.count, 26)
        XCTAssertEqual(rows.filter(\.renewable).count, 0, "Auf dieser Aufnahme ist nichts verlängerbar")

        let blockedByHold = rows.filter { $0.reason.contains("Vormerkungen") }
        XCTAssertEqual(blockedByHold.count, 2)
        let notYet = rows.filter { $0.reason.contains("noch nicht möglich") }
        XCTAssertEqual(notYet.count, 24)

        XCTAssertEqual(rows[0].shortReason, "Keine Verlängerung: Vormerkungen", "„- Stand …“-Suffix wird entfernt")
        XCTAssertEqual(rows[0].checkboxValue, HTMLParser.parseLoans(Fixture.loans)[0].checkboxValue)
    }

    func testMarkerVariants() {
        let renewable = """
        <tr class="rTable_tr_1"><td><input type="checkbox" value="CheckCell_7"></td><td>01.01.2027</td>
        <td>Bib</td><td>Titel</td><td><b>verlängerbar - Stand 01.01.2026</b></td></tr>
        """
        let rows = HTMLParser.parseRenewability(renewable)
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(rows[0].renewable)
        XCTAssertEqual(rows[0].reason, "")

        XCTAssertEqual(HTMLParser.parseRenewability(Fixture.unexpectedPage).count, 0)
    }
}

final class HiddenInputTests: XCTestCase {
    func testRequestCountComesFromPage() {
        // Der Server zählt pro Sitzung hoch; der Browser sendet exakt den Wert der aktuellen Seite.
        XCTAssertEqual(HTMLParser.extractHiddenInputs(Fixture.overview)["requestCount"], "5")
        XCTAssertEqual(HTMLParser.extractHiddenInputs(Fixture.loans)["requestCount"], "6")
    }

    func testRequestCountIsRequiredForFollowUpRequests() throws {
        XCTAssertEqual(try VOEBBSession.requiredRequestCount(in: HTMLParser.extractHiddenInputs(Fixture.overview)), "5")
        XCTAssertThrowsError(try VOEBBSession.requiredRequestCount(in: HTMLParser.extractHiddenInputs(Fixture.unexpectedPage)))
        XCTAssertThrowsError(try VOEBBSession.requiredRequestCount(in: ["requestCount": "abc"]))
        XCTAssertThrowsError(try VOEBBSession.requiredRequestCount(in: ["requestCount": ""]))
    }

    func testIdentityTokenPresent() {
        XCTAssertEqual(HTMLParser.extractHiddenInputs(Fixture.overview)["identity"], "IDENTITY_REDACTED")
        XCTAssertNil(HTMLParser.extractHiddenInputs(Fixture.unexpectedPage)["requestCount"])
    }
}

final class PickupParserTests: XCTestCase {
    func testPickupCountFromServices() {
        XCTAssertEqual(HTMLParser.parsePickupCount(Fixture.overview), 0, "„Keine Bereitstellungen“")
        XCTAssertEqual(HTMLParser.parsePickupCount(Fixture.html("overview-with-pickup")), 1, "„1 Bereitstellung“ (Singular)")
        XCTAssertNil(HTMLParser.parsePickupCount(Fixture.unexpectedPage))
    }

    func testParsesPickupRows() {
        let html = Fixture.html("pickups")
        XCTAssertTrue(HTMLParser.isPickupsPage(html))
        let items = HTMLParser.parsePickups(html)
        XCTAssertEqual(items.count, 1)
        let item = items[0]
        XCTAssertEqual(item.readyUntilString, "19.09.2026")
        XCTAssertNotNil(item.readyUntil)
        XCTAssertEqual(item.library, "Friedrichshain-Kreuzberg: Bezirkszentralbibliothek Pablo Neruda")
        XCTAssertEqual(item.title, "W1 W2. - W3 1. W4 W5 W6 W7 W8 / X", "Erste Titelzeile, ¬-Marker entfernt, Signatur/Mediennummer weg")
    }

    func testLoansPageIsNotMistakenForPickups() {
        // Die Ausleihseite hat dieselbe <title>; ohne Seitenmarker darf nichts geparst werden
        XCTAssertFalse(HTMLParser.isPickupsPage(Fixture.loans))
        XCTAssertEqual(HTMLParser.parsePickups(Fixture.loans).count, 0)
        XCTAssertEqual(HTMLParser.parsePickups(Fixture.unexpectedPage).count, 0)
    }
}

final class AccountDataCacheTests: XCTestCase {
    func testDecodesCacheFromOlderVersionWithoutNewFields() throws {
        // Cache-Format vor pickups/feesUnknown/pickupCode/cardExpiryWarning
        let json = """
        [{"account":{"name":"Test","cardNumber":"1"},"loans":[],"fees":0.4,
          "cardValidUntil":"12.08.2027","lastUpdated":0}]
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode([AccountData].self, from: json)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].fees, 0.4)
        XCTAssertEqual(decoded[0].pickups, [])
        XCTAssertNil(decoded[0].pickupCode)
    }

    func testRoundTrip() throws {
        var data = AccountData(account: LibraryAccount(name: "A", cardNumber: "2"))
        data.pickups = [PickupItem(title: "T", readyUntilString: "19.09.2026", readyUntil: nil, library: "L")]
        data.cardExpiryWarning = "Ausweis läuft in 3 Tagen ab"
        let back = try JSONDecoder().decode(AccountData.self, from: JSONEncoder().encode(data))
        XCTAssertEqual(back.pickups, data.pickups)
        XCTAssertEqual(back.cardExpiryWarning, data.cardExpiryWarning)
    }
}
