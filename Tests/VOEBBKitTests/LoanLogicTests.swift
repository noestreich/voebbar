import XCTest
@testable import VOEBBKit

final class DueDateTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    private func loan(dueOn day: Int) -> Loan {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 9; comps.day = day
        let due = calendar.date(from: comps)!  // Mitternacht, wie vom Parser geliefert
        return Loan(title: "T", dueDate: due, dueDateString: "\(day).09.2026", library: "L",
                    renewalStatus: "", checkboxValue: "CheckCell")
    }

    private func now(day: Int, hour: Int) -> Date {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 9; comps.day = day; comps.hour = hour; comps.minute = 30
        return calendar.date(from: comps)!
    }

    func testDueToday() {
        let l = loan(dueOn: 10)
        XCTAssertEqual(l.daysUntilDue(relativeTo: now(day: 10, hour: 15), calendar: calendar), 0)
        XCTAssertFalse(l.isOverdue(relativeTo: now(day: 10, hour: 23), calendar: calendar))
    }

    func testDueTomorrowIsOneDayEvenInTheAfternoon() {
        let l = loan(dueOn: 11)
        XCTAssertEqual(l.daysUntilDue(relativeTo: now(day: 10, hour: 15), calendar: calendar), 1)
        XCTAssertEqual(l.daysUntilDue(relativeTo: now(day: 10, hour: 23), calendar: calendar), 1)
        XCTAssertEqual(l.daysUntilDue(relativeTo: now(day: 10, hour: 0), calendar: calendar), 1)
    }

    func testSelectionBoundaryForDueWithinDays() {
        let threshold = 3
        let dueIn3 = loan(dueOn: 13)
        let dueIn4 = loan(dueOn: 14)
        let at = now(day: 10, hour: 18)
        XCTAssertTrue(dueIn3.daysUntilDue(relativeTo: at, calendar: calendar) <= threshold)
        XCTAssertFalse(dueIn4.daysUntilDue(relativeTo: at, calendar: calendar) <= threshold,
                       "In 4 Tagen fällig darf abends nicht als ≤ 3 Tage gelten")
    }

    func testOverdue() {
        let l = loan(dueOn: 9)
        let at = now(day: 10, hour: 9)
        XCTAssertTrue(l.isOverdue(relativeTo: at, calendar: calendar))
        XCTAssertEqual(l.daysUntilDue(relativeTo: at, calendar: calendar), 0)
        XCTAssertEqual(l.bookEmoji, l.bookEmoji)  // stabil, kein Crash
    }
}

final class LoanValidationTests: XCTestCase {
    private func loans(_ n: Int) -> [Loan] {
        (0..<n).map {
            Loan(title: "T\($0)", dueDate: Date(), dueDateString: "", library: "L",
                 renewalStatus: "", checkboxValue: "CheckCell_\($0)")
        }
    }

    func testCompleteListPasses() throws {
        try VOEBBSession.validateLoans(loans(26), expectedCount: 26, pageHTML: Fixture.loans)
        try VOEBBSession.validateLoans(loans(3), expectedCount: nil, pageHTML: Fixture.loans)
    }

    func testEmptyResultDespiteExpectedLoansThrows() {
        XCTAssertThrowsError(try VOEBBSession.validateLoans([], expectedCount: 26, pageHTML: Fixture.unexpectedPage)) {
            XCTAssertTrue("\($0.localizedDescription)".contains("26"))
        }
        // Auch wenn die Seite wie eine Ausleihliste aussieht, aber nichts geparst wurde
        XCTAssertThrowsError(try VOEBBSession.validateLoans([], expectedCount: 5, pageHTML: Fixture.loans))
    }

    func testIncompleteListThrows() {
        XCTAssertThrowsError(try VOEBBSession.validateLoans(loans(20), expectedCount: 26, pageHTML: Fixture.loans)) {
            XCTAssertTrue("\($0.localizedDescription)".contains("20 von 26"))
        }
    }

    func testUnknownCountRequiresRecognizablePage() {
        // Übersicht unlesbar, Ausleihseite leer und nicht erkennbar → Fehler
        XCTAssertThrowsError(try VOEBBSession.validateLoans([], expectedCount: nil, pageHTML: Fixture.unexpectedPage))
        // Übersicht unlesbar, aber erkennbare (leere) Ausleihseite → ok
        XCTAssertNoThrow(try VOEBBSession.validateLoans([], expectedCount: nil, pageHTML: "<title>Meine Ausleihen</title>"))
        // Übersicht sagt 0 → wird gar nicht erst geprüft; hier nur Robustheit
        XCTAssertNoThrow(try VOEBBSession.validateLoans([], expectedCount: 0, pageHTML: ""))
    }
}
