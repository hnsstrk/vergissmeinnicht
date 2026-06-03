import XCTest
@testable import Vergissmeinnicht

/// Unit-Tests für die drei reinen Parser-Module (#6): QuickCaptureParser,
/// RecurParser, DueDateParser. Alles deterministische, store-freie Funktionen.
///
/// Zeitzonen-Hinweis: DueDateParser nutzt `TimeZone.current`. CI läuft in UTC,
/// der Autor in CEST — deshalb werden Absolut-Timestamps NIE hartkodiert, sondern
/// gegen denselben `TimeZone.current` berechnet bzw. strukturell geprüft
/// (heute < morgen; Ende-des-Tages == Mitternacht-Folgetag − 1s).
final class ParserTests: XCTestCase {

    // MARK: - QuickCaptureParser

    func testQuickCaptureExtractsTagProjectDuePriority() {
        let p = QuickCaptureParser.parse("Einkaufen +haushalt project:Privat due:tomorrow priority:H")
        XCTAssertEqual(p.description, "Einkaufen")
        XCTAssertEqual(p.tags, ["haushalt"])
        XCTAssertEqual(p.project, "Privat")
        XCTAssertEqual(p.due, "tomorrow")
        XCTAssertEqual(p.priority, "H")
        XCTAssertTrue(p.hasMetadata)
    }

    func testQuickCaptureMultipleTagsPreserveOrder() {
        let p = QuickCaptureParser.parse("Task +a +b +c")
        XCTAssertEqual(p.tags, ["a", "b", "c"])
        XCTAssertEqual(p.description, "Task")
    }

    func testQuickCaptureReconstructsDescriptionInOrder() {
        // Nicht-Metadaten-Tokens bilden die Description in Eingabe-Reihenfolge.
        let p = QuickCaptureParser.parse("kaufe +work Milch und Brot project:Haus")
        XCTAssertEqual(p.description, "kaufe Milch und Brot")
        XCTAssertEqual(p.tags, ["work"])
        XCTAssertEqual(p.project, "Haus")
    }

    func testQuickCaptureEscapedWhitespaceJoinsToken() {
        // `\ ` (Backslash + Leerzeichen) ist ein literales Leerzeichen im Token.
        let p = QuickCaptureParser.parse(#"meeting\ notes +work"#)
        XCTAssertEqual(p.description, "meeting notes")
        XCTAssertEqual(p.tags, ["work"])
    }

    func testQuickCaptureBareTokenIsDescription() {
        let p = QuickCaptureParser.parse("nur Text ohne Metadaten")
        XCTAssertEqual(p.description, "nur Text ohne Metadaten")
        XCTAssertTrue(p.tags.isEmpty)
        XCTAssertNil(p.project)
        XCTAssertNil(p.due)
        XCTAssertNil(p.priority)
        XCTAssertFalse(p.hasMetadata)
    }

    func testQuickCaptureLonePlusStaysDescription() {
        // `+` allein (count == 1) ist kein Tag, sondern Description-Text.
        let p = QuickCaptureParser.parse("rechne 2 + 2")
        XCTAssertEqual(p.description, "rechne 2 + 2")
        XCTAssertTrue(p.tags.isEmpty)
    }

    func testQuickCaptureEmptyPrefixValueStaysDescription() {
        // `project:` ohne Wert (count == prefix.count) wird nicht als Operator erkannt.
        let p = QuickCaptureParser.parse("text project:")
        XCTAssertNil(p.project)
        XCTAssertEqual(p.description, "text project:")
    }

    func testQuickCaptureUmlautsInDescriptionPreserved() {
        let p = QuickCaptureParser.parse("Käse für Müsli +frühstück")
        XCTAssertEqual(p.description, "Käse für Müsli")
        XCTAssertEqual(p.tags, ["frühstück"])
    }

    func testQuickCaptureEmptyInput() {
        let p = QuickCaptureParser.parse("")
        XCTAssertEqual(p.description, "")
        XCTAssertFalse(p.hasMetadata)
    }

    // MARK: - RecurParser

    func testRecurStandardForms() {
        XCTAssertEqual(RecurParser.components(from: "daily"),   DateComponents(day: 1))
        XCTAssertEqual(RecurParser.components(from: "weekly"),  DateComponents(weekOfYear: 1))
        XCTAssertEqual(RecurParser.components(from: "monthly"), DateComponents(month: 1))
        XCTAssertEqual(RecurParser.components(from: "yearly"),  DateComponents(year: 1))
    }

    func testRecurStandardFormsAreCaseInsensitiveAndTrimmed() {
        XCTAssertEqual(RecurParser.components(from: "  WEEKLY  "), DateComponents(weekOfYear: 1))
        XCTAssertEqual(RecurParser.components(from: "Daily"), DateComponents(day: 1))
    }

    func testRecurNumericForms() {
        XCTAssertEqual(RecurParser.components(from: "3d"), DateComponents(day: 3))
        XCTAssertEqual(RecurParser.components(from: "2w"), DateComponents(weekOfYear: 2))
        XCTAssertEqual(RecurParser.components(from: "6m"), DateComponents(month: 6))
        XCTAssertEqual(RecurParser.components(from: "1y"), DateComponents(year: 1))
    }

    func testRecurNumericCaseInsensitive() {
        XCTAssertEqual(RecurParser.components(from: "4D"), DateComponents(day: 4))
    }

    func testRecurEmptyReturnsNil() {
        XCTAssertNil(RecurParser.components(from: ""))
        XCTAssertNil(RecurParser.components(from: "   "))
    }

    func testRecurInvalidReturnsNil() {
        XCTAssertNil(RecurParser.components(from: "garbage"))
        XCTAssertNil(RecurParser.components(from: "d"))       // count < 2
        XCTAssertNil(RecurParser.components(from: "0d"))      // n muss > 0 sein
        XCTAssertNil(RecurParser.components(from: "-3d"))     // Int("-3") gültig, aber n <= 0
        XCTAssertNil(RecurParser.components(from: "3x"))      // unbekannte Einheit
        XCTAssertNil(RecurParser.components(from: "xd"))      // keine Zahl
    }

    // MARK: - DueDateParser

    /// Referenz-Kalender, identisch zur Parser-Implementierung (gregorianisch,
    /// `TimeZone.current`), damit Erwartungswerte zeitzonen-unabhängig stimmen.
    private func referenceCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        return cal
    }

    /// Erwartetes Ende-des-Tages (letzte Sekunde) als Unix-Sekunden, berechnet
    /// mit demselben Kalender wie der Parser.
    private func expectedEndOfDay(_ date: Date) -> Int64 {
        let cal = referenceCalendar()
        let start = cal.startOfDay(for: date)
        let next = cal.date(byAdding: .day, value: 1, to: start)!
        return Int64(next.addingTimeInterval(-1).timeIntervalSince1970)
    }

    func testDueDateToday() {
        let now = Date()
        XCTAssertEqual(DueDateParser.parse("today", now: now), expectedEndOfDay(now))
    }

    func testDueDateTomorrow() {
        let now = Date()
        let cal = referenceCalendar()
        let tomorrow = cal.date(byAdding: .day, value: 1, to: now)!
        XCTAssertEqual(DueDateParser.parse("tomorrow", now: now), expectedEndOfDay(tomorrow))
    }

    func testDueDateTomorrowIsAfterToday() {
        let now = Date()
        let today = DueDateParser.parse("today", now: now)!
        let tomorrow = DueDateParser.parse("tomorrow", now: now)!
        XCTAssertGreaterThan(tomorrow, today)
    }

    func testDueDateRelativeDays() {
        let now = Date()
        let cal = referenceCalendar()
        let plus3 = cal.date(byAdding: .day, value: 3, to: now)!
        XCTAssertEqual(DueDateParser.parse("+3d", now: now), expectedEndOfDay(plus3))
    }

    func testDueDateRelativeWeeks() {
        let now = Date()
        let cal = referenceCalendar()
        let plus2w = cal.date(byAdding: .weekOfYear, value: 2, to: now)!
        XCTAssertEqual(DueDateParser.parse("+2w", now: now), expectedEndOfDay(plus2w))
    }

    func testDueDateISOFormat() {
        // Festes ISO-Datum: Ende des 24.12.2026 in der lokalen Zeitzone.
        let cal = referenceCalendar()
        let comps = DateComponents(year: 2026, month: 12, day: 24, hour: 12)
        let noon = cal.date(from: comps)!
        XCTAssertEqual(DueDateParser.parse("2026-12-24"), expectedEndOfDay(noon))
    }

    func testDueDateIsCaseInsensitive() {
        let now = Date()
        XCTAssertEqual(DueDateParser.parse("TODAY", now: now), DueDateParser.parse("today", now: now))
        XCTAssertEqual(DueDateParser.parse("Tomorrow", now: now), DueDateParser.parse("tomorrow", now: now))
    }

    func testDueDateEndOfDayIsLastSecondBeforeNextMidnight() {
        // Strukturell: parse("today") == Mitternacht-Folgetag − 1 Sekunde.
        let now = Date()
        let cal = referenceCalendar()
        let startTomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now))!
        let ts = DueDateParser.parse("today", now: now)!
        XCTAssertEqual(ts, Int64(startTomorrow.timeIntervalSince1970) - 1)
    }

    func testDueDateInvalidReturnsNil() {
        XCTAssertNil(DueDateParser.parse(""))
        XCTAssertNil(DueDateParser.parse("   "))
        XCTAssertNil(DueDateParser.parse("garbage"))
        XCTAssertNil(DueDateParser.parse("+d"))         // count < 3
        XCTAssertNil(DueDateParser.parse("+3m"))        // Monat als relative Einheit nicht unterstützt
        XCTAssertNil(DueDateParser.parse("2026-13-01")) // ungültiger Monat
        XCTAssertNil(DueDateParser.parse("24.12.2026")) // falsches Format
    }
}
