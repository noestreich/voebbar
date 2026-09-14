import XCTest
@testable import VOEBBKit

final class LoanHistoryTests: XCTestCase {
    private var fileURL: URL!

    override func setUp() {
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("voepp-history-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func loan(_ media: String?, title: String = "Titel", library: String = "Bib") -> Loan {
        var l = Loan(title: title, dueDate: Date(), dueDateString: "01.10.2026", library: library,
                     renewalStatus: "", checkboxValue: "CheckCell")
        l.mediaNumber = media
        return l
    }

    private func data(_ loans: [Loan], card: String = "1", error: String? = nil) -> AccountData {
        var d = AccountData(account: LibraryAccount(name: "Konto \(card)", cardNumber: card))
        d.loans = loans
        d.error = error
        return d
    }

    private func day(_ n: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(n) * 86_400) }

    func testFirstRecordingMarksStartUnknown() {
        let store = LoanHistoryStore(fileURL: fileURL)
        XCTAssertTrue(store.record([data([loan("A"), loan("B")])], now: day(1)))
        XCTAssertEqual(store.entries.count, 2)
        XCTAssertTrue(store.entries.allSatisfy { $0.startUnknown && $0.isOpen })

        // Später hinzukommende Medien haben einen bekannten Beginn
        store.record([data([loan("A"), loan("B"), loan("C")])], now: day(2))
        let c = store.entries.first { $0.key == "C" }!
        XCTAssertFalse(c.startUnknown)
        XCTAssertEqual(c.firstSeen, day(2))
    }

    func testDisappearanceIsRecordedAsReturn() {
        let store = LoanHistoryStore(fileURL: fileURL)
        store.record([data([loan("A"), loan("B")])], now: day(1))
        store.record([data([loan("A")])], now: day(5))

        let b = store.entries.first { $0.key == "B" }!
        XCTAssertEqual(b.lastSeen, day(1), "zuletzt gesehen beim vorherigen Abruf")
        XCTAssertEqual(b.returnedAt, day(5), "erstmals gefehlt bei diesem Abruf")
        let a = store.entries.first { $0.key == "A" }!
        XCTAssertTrue(a.isOpen)
        XCTAssertEqual(a.lastSeen, day(5))
    }

    func testEmptyValidatedListClosesEverything() {
        let store = LoanHistoryStore(fileURL: fileURL)
        store.record([data([loan("A")])], now: day(1))
        store.record([data([])], now: day(2))
        XCTAssertEqual(store.entries.first?.returnedAt, day(2))
    }

    func testReappearanceCreatesNewEntry() {
        let store = LoanHistoryStore(fileURL: fileURL)
        store.record([data([loan("A")])], now: day(1))
        store.record([data([])], now: day(2))
        store.record([data([loan("A")])], now: day(3))
        let a = store.entries.filter { $0.key == "A" }
        XCTAssertEqual(a.count, 2)
        XCTAssertEqual(a.filter(\.isOpen).count, 1)
        XCTAssertFalse(a.first { $0.isOpen }!.startUnknown)
    }

    func testErroredAccountIsIgnored() {
        let store = LoanHistoryStore(fileURL: fileURL)
        store.record([data([loan("A")])], now: day(1))
        // Abruf fehlgeschlagen → Liste leer, aber Fehler gesetzt: keine Rückgabe verbuchen
        XCTAssertFalse(store.record([data([], error: "Netzwerkfehler")], now: day(2)))
        XCTAssertTrue(store.entries.first!.isOpen)
        XCTAssertEqual(store.entries.first!.lastSeen, day(1))
    }

    func testFallbackKeyWithoutMediaNumber() {
        let store = LoanHistoryStore(fileURL: fileURL)
        store.record([data([loan(nil, title: "T", library: "L")])], now: day(1))
        XCTAssertEqual(store.entries.first?.key, "T|L")
        store.record([data([loan(nil, title: "T", library: "L")])], now: day(2))
        XCTAssertEqual(store.entries.count, 1, "gleicher Ersatzschlüssel → derselbe Eintrag")
    }

    func testAccountsAreIndependentAndRemovable() {
        let store = LoanHistoryStore(fileURL: fileURL)
        store.record([data([loan("A")], card: "1"), data([loan("A")], card: "2")], now: day(1))
        XCTAssertEqual(store.entries.count, 2)
        store.remove(cardNumber: "1")
        XCTAssertEqual(store.entries.map(\.cardNumber), ["2"])
    }

    func testPersistsAcrossInstances() {
        LoanHistoryStore(fileURL: fileURL).record([data([loan("A")])], now: day(1))
        let reloaded = LoanHistoryStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.entries.count, 1)
        XCTAssertEqual(reloaded.entries.first?.key, "A")
    }
}

final class MediaNumberParserTests: XCTestCase {
    func testMediaNumberFromFixture() {
        let loans = HTMLParser.parseLoans(Fixture.loans)
        XCTAssertEqual(loans[0].mediaNumber, "00000000001")
        XCTAssertEqual(Set(loans.compactMap(\.mediaNumber)).count, 26, "jedes Exemplar hat eine eigene Nummer")
    }

    func testMediaNumberExtraction() {
        XCTAssertEqual(HTMLParser.extractMediaNumber("Titel<br>Sig 12<br>0012345678"), "0012345678")
        XCTAssertNil(HTMLParser.extractMediaNumber("Titel<br>Sig"), "keine Ziffernzeile")
        XCTAssertNil(HTMLParser.extractMediaNumber("Titel<br>Band 3<br>12"), "zu kurz für eine Mediennummer")
        XCTAssertNil(HTMLParser.extractMediaNumber("0012345678"), "eine einzelne Zeile ist der Titel")
    }
}
