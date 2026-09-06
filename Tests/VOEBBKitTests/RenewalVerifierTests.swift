import XCTest
@testable import VOEBBKit

final class RenewalVerifierTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    private func date(_ day: Int) -> Date {
        var c = DateComponents(); c.year = 2026; c.month = 10; c.day = day
        return calendar.date(from: c)!
    }

    private func loan(_ title: String, due day: Int, cb: String, library: String = "Bib") -> Loan {
        Loan(title: title, dueDate: date(day), dueDateString: "\(day).10.2026", library: library,
             renewalStatus: "", checkboxValue: cb)
    }

    private func row(_ title: String, cb: String) -> RenewabilityRow {
        RenewabilityRow(checkboxValue: cb, title: title, renewable: true, reason: "")
    }

    func testAllRenewed() {
        let before = [loan("A", due: 5, cb: "c0"), loan("B", due: 5, cb: "c1")]
        let after  = [loan("A", due: 26, cb: "c0"), loan("B", due: 26, cb: "c1")]
        let r = RenewalVerifier.verify(submitted: [row("A", cb: "c0"), row("B", cb: "c1")], before: before, after: after)
        XCTAssertEqual(r.confirmed.map(\.title), ["A", "B"])
        XCTAssertTrue(r.unconfirmed.isEmpty)
        XCTAssertFalse(r.unverifiable)
    }

    func testPartialSuccess() {
        let before = [loan("A", due: 5, cb: "c0"), loan("B", due: 5, cb: "c1"), loan("C", due: 9, cb: "c2")]
        // B wurde nicht verlängert, C war gar nicht eingereicht
        let after  = [loan("A", due: 26, cb: "c0"), loan("B", due: 5, cb: "c1"), loan("C", due: 9, cb: "c2")]
        let r = RenewalVerifier.verify(submitted: [row("A", cb: "c0"), row("B", cb: "c1")], before: before, after: after)
        XCTAssertEqual(r.confirmed.map(\.title), ["A"])
        XCTAssertEqual(r.unconfirmed.map(\.title), ["B"])
        XCTAssertFalse(r.unverifiable)
    }

    func testNothingChangedIsNotSuccess() {
        let before = [loan("A", due: 5, cb: "c0")]
        let r = RenewalVerifier.verify(submitted: [row("A", cb: "c0")], before: before, after: before)
        XCTAssertTrue(r.confirmed.isEmpty)
        XCTAssertEqual(r.unconfirmed.map(\.title), ["A"])
        XCTAssertFalse(r.unverifiable)
    }

    func testUnreadableResultPageIsUnverifiable() {
        let before = [loan("A", due: 5, cb: "c0")]
        let r = RenewalVerifier.verify(submitted: [row("A", cb: "c0")], before: before, after: [])
        XCTAssertTrue(r.confirmed.isEmpty)
        XCTAssertEqual(r.unconfirmed.map(\.title), ["A"])
        XCTAssertTrue(r.unverifiable)
    }

    func testReorderedResultStillMatchesByTitle() {
        // Nach dem Submit sortiert aDIS neu; Checkbox-Positionen wandern mit.
        let before = [loan("A", due: 5, cb: "c0"), loan("B", due: 9, cb: "c1")]
        let after  = [loan("B", due: 9, cb: "c0"), loan("A", due: 26, cb: "c1")]
        let r = RenewalVerifier.verify(submitted: [row("A", cb: "c0")], before: before, after: after)
        XCTAssertEqual(r.confirmed.map(\.title), ["A"])
    }

    func testDuplicateCopiesCountedNotDoubled() {
        // Zwei Exemplare desselben Titels, nur eines wurde verlängert
        let before = [loan("A", due: 5, cb: "c0"), loan("A", due: 5, cb: "c1")]
        let after  = [loan("A", due: 26, cb: "c0"), loan("A", due: 5, cb: "c1")]
        let r = RenewalVerifier.verify(submitted: [row("A", cb: "c0"), row("A", cb: "c1")], before: before, after: after)
        XCTAssertEqual(r.confirmed.count, 1)
        XCTAssertEqual(r.unconfirmed.count, 1)
    }

    func testSameTitleDifferentLibraryIsSeparate() {
        let before = [loan("A", due: 5, cb: "c0", library: "X"), loan("A", due: 5, cb: "c1", library: "Y")]
        let after  = [loan("A", due: 26, cb: "c0", library: "X"), loan("A", due: 5, cb: "c1", library: "Y")]
        let r = RenewalVerifier.verify(submitted: [row("A", cb: "c1")], before: before, after: after)
        XCTAssertTrue(r.confirmed.isEmpty, "Verlängerung in Bibliothek X darf Exemplar in Y nicht bestätigen")
        XCTAssertEqual(r.unconfirmed.count, 1)
    }

    func testOutcomeMessages() {
        let a = row("A", cb: "c0"), b = row("B", cb: "c1")
        XCTAssertTrue(RenewalOutcome(renewed: [a]).userMessage.hasPrefix("1 Medium verlängert."))
        XCTAssertTrue(RenewalOutcome(renewed: [a, b]).userMessage.hasPrefix("2 Medien verlängert."))

        let partial = RenewalOutcome(renewed: [a], unconfirmed: [b]).userMessage
        XCTAssertTrue(partial.contains("Nicht bestätigt"))
        XCTAssertTrue(partial.contains("• B"))

        let unverifiable = RenewalOutcome(unconfirmed: [a], unverifiable: true).userMessage
        XCTAssertTrue(unverifiable.hasPrefix("Keine Verlängerung bestätigt."))
        XCTAssertTrue(unverifiable.contains("nicht überprüft"))

        XCTAssertEqual(RenewalOutcome().userMessage, "Keine Medien verlängert.")
    }
}
