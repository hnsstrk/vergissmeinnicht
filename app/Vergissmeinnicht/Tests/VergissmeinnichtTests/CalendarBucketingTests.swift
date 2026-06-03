import XCTest
import VergissmeinnichtKit
@testable import Vergissmeinnicht

/// Tests für die reine Tag-Bucketing-Logik des Kalenders/Wochen-Streifens (#11).
/// `CalendarBucketing` ist nonisolated und synchron → diese Klasse ist bewusst ein
/// schlichtes `XCTestCase` (NICHT `@MainActor`), wodurch die Swift-6.0-async-setUp-
/// Falter komplett entfällt. Fester UTC-Kalender für Zeitzonen-Determinismus
/// (wie in AppContainerIntegrationTests).
final class CalendarBucketingTests: XCTestCase {

    private func utcCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    /// 2026-06-15 12:00 UTC — Bezugspunkt im Monat Juni 2026.
    private let reference = Date(timeIntervalSince1970: 1_781_006_400)

    /// Unix-Sekunden für ein Datum (UTC) zu Mittag.
    private func unix(_ year: Int, _ month: Int, _ day: Int) -> Int64 {
        let cal = utcCalendar()
        let comps = DateComponents(year: year, month: month, day: day, hour: 12)
        return Int64(cal.date(from: comps)!.timeIntervalSince1970)
    }

    private func dayStart(_ year: Int, _ month: Int, _ day: Int) -> Date {
        utcCalendar().startOfDay(for: Date(timeIntervalSince1970: TimeInterval(unix(year, month, day))))
    }

    private func task(
        uuid: String = UUID().uuidString,
        description: String = "Task",
        due: Int64? = nil,
        status: TaskStatus = .pending,
        recur: String? = nil,
        scheduled: Int64? = nil
    ) -> TaskInfo {
        TaskInfo(
            uuid: uuid, description: description, project: nil, tags: [],
            due: due, status: status, entry: nil, workingSetId: nil,
            priority: nil, annotations: [], wait: nil, recur: recur,
            scheduled: scheduled, depends: [], isBlocked: false, isBlocking: false
        )
    }

    // MARK: - due-only → Chip am Fälligkeitstag

    func testDueOnlyLandsOnDueDay() {
        let t = task(due: unix(2026, 6, 15))
        let buckets = CalendarBucketing.buckets(tasks: [t], monthOf: reference, calendar: utcCalendar())
        let entries = buckets[dayStart(2026, 6, 15)] ?? []
        XCTAssertEqual(entries.count, 1)
        if case .chip(let task) = entries.first {
            XCTAssertEqual(task.uuid, t.uuid)
        } else {
            XCTFail("Erwartet: .chip am Fälligkeitstag")
        }
    }

    func testDueOutsideMonthIsExcluded() {
        let t = task(due: unix(2026, 7, 5))
        let buckets = CalendarBucketing.buckets(tasks: [t], monthOf: reference, calendar: utcCalendar())
        XCTAssertTrue(buckets.isEmpty)
    }

    func testCompletedTaskIsIgnored() {
        let t = task(due: unix(2026, 6, 15), status: .completed)
        let buckets = CalendarBucketing.buckets(tasks: [t], monthOf: reference, calendar: utcCalendar())
        XCTAssertTrue(buckets.isEmpty)
    }

    // MARK: - scheduled→due Span ("Dauer")

    func testScheduledToDueSpansDayRange() {
        let t = task(due: unix(2026, 6, 12), scheduled: unix(2026, 6, 10))
        let buckets = CalendarBucketing.buckets(tasks: [t], monthOf: reference, calendar: utcCalendar())
        // 10., 11., 12. → drei Span-Tage.
        XCTAssertEqual(buckets[dayStart(2026, 6, 10)]?.count, 1)
        XCTAssertEqual(buckets[dayStart(2026, 6, 11)]?.count, 1)
        XCTAssertEqual(buckets[dayStart(2026, 6, 12)]?.count, 1)
        XCTAssertNil(buckets[dayStart(2026, 6, 13)])

        // Start- und End-Flags korrekt.
        if case .span(_, let isStart, let isEnd) = buckets[dayStart(2026, 6, 10)]?.first {
            XCTAssertTrue(isStart); XCTAssertFalse(isEnd)
        } else { XCTFail("Erwartet: .span am Starttag") }
        if case .span(_, let isStart, let isEnd) = buckets[dayStart(2026, 6, 12)]?.first {
            XCTAssertFalse(isStart); XCTAssertTrue(isEnd)
        } else { XCTFail("Erwartet: .span am Endtag") }
        if case .span(_, let isStart, let isEnd) = buckets[dayStart(2026, 6, 11)]?.first {
            XCTAssertFalse(isStart); XCTAssertFalse(isEnd)
        } else { XCTFail("Erwartet: .span am Mitteltag") }
    }

    func testSpanClippedToMonthBoundary() {
        // Span beginnt im Vormonat, endet im Monat.
        let t = task(due: unix(2026, 6, 2), scheduled: unix(2026, 5, 29))
        let buckets = CalendarBucketing.buckets(tasks: [t], monthOf: reference, calendar: utcCalendar())
        XCTAssertNil(buckets[dayStart(2026, 5, 29)]) // außerhalb sichtbarem Monat
        XCTAssertEqual(buckets[dayStart(2026, 6, 1)]?.count, 1)
        XCTAssertEqual(buckets[dayStart(2026, 6, 2)]?.count, 1)
    }

    // MARK: - recur-Expansion

    func testWeeklyRecurExpandsWithinMonth() {
        // Anker 1. Juni, wöchentlich → 1., 8., 15., 22., 29. Juni.
        let t = task(due: unix(2026, 6, 1), recur: "weekly")
        let buckets = CalendarBucketing.buckets(tasks: [t], monthOf: reference, calendar: utcCalendar())
        for day in [1, 8, 15, 22, 29] {
            XCTAssertEqual(buckets[dayStart(2026, 6, day)]?.count, 1, "Vorkommen am \(day). Juni fehlt")
        }
        // Kein Vorkommen am 2. Juni.
        XCTAssertNil(buckets[dayStart(2026, 6, 2)])
    }

    func testDailyRecurFromPastAnchorAppearsThroughMonth() {
        // Anker weit in der Vergangenheit, täglich → jeder Tag des Monats markiert.
        let t = task(due: unix(2025, 1, 1), recur: "daily")
        let buckets = CalendarBucketing.buckets(tasks: [t], monthOf: reference, calendar: utcCalendar())
        XCTAssertEqual(buckets[dayStart(2026, 6, 1)]?.count, 1)
        XCTAssertEqual(buckets[dayStart(2026, 6, 30)]?.count, 1)
        // 30 Tage Juni → 30 markierte Tage.
        XCTAssertEqual(buckets.count, 30)
    }

    func testUnparseableRecurShowsOnlyBaseMarker() {
        // "fortnightly" kennt RecurParser nicht → nur Basis-Marker am Ankertag.
        let t = task(due: unix(2026, 6, 15), recur: "fortnightly")
        let buckets = CalendarBucketing.buckets(tasks: [t], monthOf: reference, calendar: utcCalendar())
        XCTAssertEqual(buckets[dayStart(2026, 6, 15)]?.count, 1)
        XCTAssertEqual(buckets.count, 1)
    }

    // MARK: - Überlauf-Zählung

    /// Grundlage für die "+N"-Anzeige in `CalendarView`: alle Tasks eines Tages
    /// landen im selben Bucket; die View kappt erst bei der Darstellung.
    func testManyTasksSameDayAllBucketed() {
        let day = unix(2026, 6, 15)
        let tasks = (0..<5).map { task(uuid: "u\($0)", due: day) }
        let buckets = CalendarBucketing.buckets(tasks: tasks, monthOf: reference, calendar: utcCalendar())
        XCTAssertEqual(buckets[dayStart(2026, 6, 15)]?.count, 5)
    }

    // MARK: - Wochen-Streifen-Zählung

    func testCountCombinesDueAndScheduled() {
        let day = dayStart(2026, 6, 15)
        let tasks = [
            task(due: unix(2026, 6, 15)),                       // due heute
            task(scheduled: unix(2026, 6, 15)),                 // scheduled heute
            task(due: unix(2026, 6, 16)),                       // anderer Tag
            task(due: unix(2026, 6, 15), status: .completed)    // completed zählt nicht
        ]
        XCTAssertEqual(CalendarBucketing.count(on: day, tasks: tasks, calendar: utcCalendar()), 2)
    }

    func testCountZeroOnEmptyDay() {
        let day = dayStart(2026, 6, 20)
        let tasks = [task(due: unix(2026, 6, 15))]
        XCTAssertEqual(CalendarBucketing.count(on: day, tasks: tasks, calendar: utcCalendar()), 0)
    }
}
