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
        project: String? = nil,
        due: Int64? = nil,
        status: TaskStatus = .pending,
        recur: String? = nil,
        scheduled: Int64? = nil
    ) -> TaskInfo {
        TaskInfo(
            uuid: uuid, description: description, project: project, tags: [],
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

    // MARK: - ISO-Kalenderwoche (Follow-up #11)
    //
    // Ground-Truth via `date -j -f "%Y-%m-%d" <d> "+%V"` (macOS) — die KW-Werte
    // sind nicht aus dem Gedächtnis, sondern gegen das System verifiziert. 2026
    // hat eine KW53, die bis 3.1.2027 läuft; 4.1.2027 ist KW1/2027.

    private let utc = TimeZone(identifier: "UTC")!

    private func midday(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(unix(year, month, day)))
    }

    func testIsoWeekMidYear() {
        XCTAssertEqual(CalendarBucketing.isoWeek(of: midday(2026, 6, 15), timeZone: utc), 25)
    }

    func testIsoWeekYearBoundaryKW53() {
        // 28.12.2026 → KW53/2026, läuft bis 3.1.2027 (noch KW53).
        XCTAssertEqual(CalendarBucketing.isoWeek(of: midday(2026, 12, 28), timeZone: utc), 53)
        XCTAssertEqual(CalendarBucketing.isoYearForWeek(of: midday(2026, 12, 28), timeZone: utc), 2026)
        XCTAssertEqual(CalendarBucketing.isoWeek(of: midday(2027, 1, 3), timeZone: utc), 53)
        XCTAssertEqual(CalendarBucketing.isoYearForWeek(of: midday(2027, 1, 3), timeZone: utc), 2026)
    }

    func testIsoWeekRollsToKW1() {
        // 4.1.2027 → KW1/2027.
        XCTAssertEqual(CalendarBucketing.isoWeek(of: midday(2027, 1, 4), timeZone: utc), 1)
        XCTAssertEqual(CalendarBucketing.isoYearForWeek(of: midday(2027, 1, 4), timeZone: utc), 2027)
    }

    func testIsoWeek53BelongsToPreviousYear() {
        // 3.1.2021 → KW53/2020 (klassischer Jahreswechsel-Fall).
        XCTAssertEqual(CalendarBucketing.isoWeek(of: midday(2021, 1, 3), timeZone: utc), 53)
        XCTAssertEqual(CalendarBucketing.isoYearForWeek(of: midday(2021, 1, 3), timeZone: utc), 2020)
    }

    // MARK: - Fenster (ForecastRange)

    func testWindowDays3AndWeeks1AreRolling() {
        // Montag 15.6.2026: days3 = +3, weeks1 = +7 (rollend, nicht ISO-ausgerichtet).
        let cal = utcCalendar()
        let today = midday(2026, 6, 15)
        let start = dayStart(2026, 6, 15)
        XCTAssertEqual(CalendarBucketing.agendaWindow(for: .days3, today: today, calendar: cal).start, start)
        XCTAssertEqual(CalendarBucketing.agendaWindow(for: .days3, today: today, calendar: cal).end, dayStart(2026, 6, 18))
        XCTAssertEqual(CalendarBucketing.agendaWindow(for: .weeks1, today: today, calendar: cal).end, dayStart(2026, 6, 22))
    }

    func testWindowWeeks2to4ISOAligned() {
        // Montag 15.6.2026 = Start der ISO-Woche → weeks2/3/4 enden Montag + 14/21/28.
        let cal = utcCalendar()
        let today = midday(2026, 6, 15)
        XCTAssertEqual(CalendarBucketing.agendaWindow(for: .weeks2, today: today, calendar: cal).end, dayStart(2026, 6, 29))
        XCTAssertEqual(CalendarBucketing.agendaWindow(for: .weeks3, today: today, calendar: cal).end, dayStart(2026, 7, 6))
        XCTAssertEqual(CalendarBucketing.agendaWindow(for: .weeks4, today: today, calendar: cal).end, dayStart(2026, 7, 13))
    }

    func testWindowWeeks1RollingVersusWeeks2ISOOnNonMonday() {
        // Donnerstag 18.6.2026: weeks1 ist rollend (Do + 7 = 25.6.), weeks2 ist
        // ISO-ausgerichtet (Montag der Woche, 15.6., + 14 = 29.6.). Das beweist,
        // dass die beiden Semantiken verschieden sind.
        let cal = utcCalendar()
        let today = midday(2026, 6, 18)
        XCTAssertEqual(CalendarBucketing.agendaWindow(for: .weeks1, today: today, calendar: cal).start, dayStart(2026, 6, 18))
        XCTAssertEqual(CalendarBucketing.agendaWindow(for: .weeks1, today: today, calendar: cal).end, dayStart(2026, 6, 25))
        // weeks2: start bleibt heute (18.), Ende ISO-ausgerichtet (29.6.).
        XCTAssertEqual(CalendarBucketing.agendaWindow(for: .weeks2, today: today, calendar: cal).start, dayStart(2026, 6, 18))
        XCTAssertEqual(CalendarBucketing.agendaWindow(for: .weeks2, today: today, calendar: cal).end, dayStart(2026, 6, 29))
    }

    // MARK: - Kompakt-Gitter-Fenster (KW-ausgerichtet, volle Wochen)

    /// Zählt die Tage eines `[start, end)`-Fensters.
    private func dayCount(_ window: (start: Date, end: Date), _ cal: Calendar) -> Int {
        var count = 0
        var cursor = window.start
        while cursor < window.end {
            count += 1
            cursor = cal.date(byAdding: .day, value: 1, to: cursor)!
        }
        return count
    }

    func testCompactGridWindowStartsOnIsoMondayFromMonday() {
        // Montag 15.6.2026 ist bereits Wochenanfang → weeks1–4 starten am 15.6.,
        // umfassen exakt 7/14/21/28 Tage.
        let cal = utcCalendar()
        let today = midday(2026, 6, 15)
        let monday = dayStart(2026, 6, 15)
        for (range, n) in [(ForecastRange.weeks1, 1), (.weeks2, 2), (.weeks3, 3), (.weeks4, 4)] {
            let w = CalendarBucketing.compactGridWindow(for: range, today: today, calendar: cal)
            XCTAssertEqual(w.start, monday, "\(range.rawValue): Start = Montag")
            XCTAssertEqual(dayCount(w, cal), 7 * n, "\(range.rawValue): \(7 * n) Tage")
        }
    }

    func testCompactGridWindowPadsBackToMondayOnNonMonday() {
        // Donnerstag 18.6.2026: das Fenster beginnt trotzdem am Montag 15.6. (zurück-
        // gepolstert für die Spalten-Ausrichtung), nicht heute. Beweist die volle
        // erste Zeile.
        let cal = utcCalendar()
        let today = midday(2026, 6, 18)
        let monday = dayStart(2026, 6, 15)
        let w1 = CalendarBucketing.compactGridWindow(for: .weeks1, today: today, calendar: cal)
        XCTAssertEqual(w1.start, monday)
        XCTAssertEqual(w1.end, dayStart(2026, 6, 22))   // Mo + 7
        XCTAssertEqual(dayCount(w1, cal), 7)
        let w2 = CalendarBucketing.compactGridWindow(for: .weeks2, today: today, calendar: cal)
        XCTAssertEqual(w2.start, monday)
        XCTAssertEqual(dayCount(w2, cal), 14)
    }

    func testCompactGridWindowDays3StaysRolling() {
        // days3 bleibt rollend ab heute (kein KW-Raster), auch an einem Nicht-Montag.
        let cal = utcCalendar()
        let today = midday(2026, 6, 18)
        let w = CalendarBucketing.compactGridWindow(for: .days3, today: today, calendar: cal)
        XCTAssertEqual(w.start, dayStart(2026, 6, 18))
        XCTAssertEqual(w.end, dayStart(2026, 6, 21))
        XCTAssertEqual(dayCount(w, cal), 3)
    }

    func testCompactGridWindowGroupsAreAllFullWeeks() {
        // weekGroups über das Kompakt-Gitter-Fenster (Nicht-Montag, weeks3) → jede
        // Gruppe exakt 7 Tage (Spalten richten sich aus — der Kern der Korrektur).
        let cal = utcCalendar()
        let (start, end) = CalendarBucketing.compactGridWindow(for: .weeks3, today: midday(2026, 6, 18), calendar: cal)
        let groups = CalendarBucketing.weekGroups(from: start, to: end, calendar: cal)
        XCTAssertEqual(groups.count, 3)
        XCTAssertTrue(groups.allSatisfy { $0.days.count == 7 }, "Alle Gruppen müssen volle 7-Tage-Wochen sein")
        XCTAssertEqual(groups.first?.days.first, dayStart(2026, 6, 15)) // erste Zeile beginnt Montag
        XCTAssertEqual(groups.map(\.week), [25, 26, 27])
    }

    func testAgendaWindowStaysAtTodayUnchanged() {
        // Gegenstück: Das Agenda-Fenster beginnt weiterhin heute (Nicht-Montag), wird
        // NICHT auf Montag zurückgepolstert — die Agenda bleibt vorwärtsgerichtet.
        let cal = utcCalendar()
        let today = midday(2026, 6, 18)
        XCTAssertEqual(CalendarBucketing.agendaWindow(for: .weeks2, today: today, calendar: cal).start, dayStart(2026, 6, 18))
    }

    func testWeekGroupsSplitsByISOWeek() {
        // Fenster Do 18.6. bis exkl. 29.6. (= weeks2 ab Do): Gruppe KW25 (18.–21.),
        // Gruppe KW26 (22.–28.). Start ist NICHT Wochenanfang → erste Gruppe kürzer.
        let cal = utcCalendar()
        let (start, end) = CalendarBucketing.agendaWindow(for: .weeks2, today: midday(2026, 6, 18), calendar: cal)
        let groups = CalendarBucketing.weekGroups(from: start, to: end, calendar: cal)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].week, 25)
        XCTAssertEqual(groups[0].days, [dayStart(2026, 6, 18), dayStart(2026, 6, 19), dayStart(2026, 6, 20), dayStart(2026, 6, 21)])
        XCTAssertEqual(groups[1].week, 26)
        XCTAssertEqual(groups[1].days.first, dayStart(2026, 6, 22))
        XCTAssertEqual(groups[1].days.last, dayStart(2026, 6, 28))
        XCTAssertEqual(groups[1].days.count, 7)
    }

    func testWeekGroupsWeeks4HasFourGroupsFromMonday() {
        // Ab Montag 15.6. deckt weeks4 die KW25–28 vollständig ab (4 × 7 Tage).
        let cal = utcCalendar()
        let (start, end) = CalendarBucketing.agendaWindow(for: .weeks4, today: midday(2026, 6, 15), calendar: cal)
        let groups = CalendarBucketing.weekGroups(from: start, to: end, calendar: cal)
        XCTAssertEqual(groups.map(\.week), [25, 26, 27, 28])
        XCTAssertTrue(groups.allSatisfy { $0.days.count == 7 })
    }

    // MARK: - Agenda-Buckets: scheduled vs. due

    func testAgendaScheduledAndDueAppearSeparately() {
        // scheduled 10., due 12. → zwei getrennte Agenda-Einträge an je einem Tag.
        let t = task(due: unix(2026, 6, 12), scheduled: unix(2026, 6, 10))
        let cal = utcCalendar()
        let start = dayStart(2026, 6, 1)
        let end = dayStart(2026, 7, 1)
        let buckets = CalendarBucketing.agendaBuckets(tasks: [t], from: start, to: end, calendar: cal)
        let sched = buckets[dayStart(2026, 6, 10)] ?? []
        let due = buckets[dayStart(2026, 6, 12)] ?? []
        XCTAssertEqual(sched.count, 1)
        XCTAssertEqual(due.count, 1)
        if case .scheduled = sched.first?.reason {} else { XCTFail("Erwartet: .scheduled am 10.") }
        if case .due = due.first?.reason {} else { XCTFail("Erwartet: .due am 12.") }
        // Kein Span-Mittag.
        XCTAssertNil(buckets[dayStart(2026, 6, 11)])
    }

    func testAgendaCarriesProjectSubtitleData() {
        let t = task(project: "Arbeit", due: unix(2026, 6, 15))
        let cal = utcCalendar()
        let buckets = CalendarBucketing.agendaBuckets(
            tasks: [t], from: dayStart(2026, 6, 1), to: dayStart(2026, 7, 1), calendar: cal
        )
        XCTAssertEqual(buckets[dayStart(2026, 6, 15)]?.first?.task.project, "Arbeit")
    }

    func testAgendaCompletedIgnored() {
        let t = task(due: unix(2026, 6, 15), status: .completed)
        let cal = utcCalendar()
        let buckets = CalendarBucketing.agendaBuckets(
            tasks: [t], from: dayStart(2026, 6, 1), to: dayStart(2026, 7, 1), calendar: cal
        )
        XCTAssertTrue(buckets.isEmpty)
    }

    func testAgendaRespectsWindowExclusiveEnd() {
        // due exakt am end-Tag → außerhalb (Fenster ist [start, end)).
        let t = task(due: unix(2026, 6, 22))
        let cal = utcCalendar()
        let (start, end) = CalendarBucketing.agendaWindow(for: .weeks1, today: midday(2026, 6, 15), calendar: cal)
        let buckets = CalendarBucketing.agendaBuckets(tasks: [t], from: start, to: end, calendar: cal)
        XCTAssertTrue(buckets.isEmpty)
    }

    func testAgendaWeeklyRecurExpandsDue() {
        let t = task(due: unix(2026, 6, 1), recur: "weekly")
        let cal = utcCalendar()
        let buckets = CalendarBucketing.agendaBuckets(
            tasks: [t], from: dayStart(2026, 6, 1), to: dayStart(2026, 7, 1), calendar: cal
        )
        for day in [1, 8, 15, 22, 29] {
            XCTAssertEqual(buckets[dayStart(2026, 6, day)]?.count, 1, "Recur-Vorkommen am \(day). fehlt")
        }
    }

    // MARK: - Kappung / Überlauf

    func testCappedReturnsOverflow() {
        let items = (0..<5).map {
            CalendarBucketing.AgendaItem(task: task(uuid: "u\($0)", due: unix(2026, 6, 15)), reason: .due)
        }
        let (shown, overflow) = CalendarBucketing.capped(items, cap: 3)
        XCTAssertEqual(shown.count, 3)
        XCTAssertEqual(overflow, 2)
    }

    func testCappedNoOverflowUnderCap() {
        let items = (0..<2).map {
            CalendarBucketing.AgendaItem(task: task(uuid: "u\($0)", due: unix(2026, 6, 15)), reason: .due)
        }
        let (shown, overflow) = CalendarBucketing.capped(items, cap: 5)
        XCTAssertEqual(shown.count, 2)
        XCTAssertEqual(overflow, 0)
    }

    func testCappedNilCapShowsAll() {
        let items = (0..<7).map {
            CalendarBucketing.AgendaItem(task: task(uuid: "u\($0)", due: unix(2026, 6, 15)), reason: .due)
        }
        let (shown, overflow) = CalendarBucketing.capped(items, cap: nil)
        XCTAssertEqual(shown.count, 7)
        XCTAssertEqual(overflow, 0)
    }

    // MARK: - Agenda-Sortierung (Follow-up #11: Zeit statt locale-String)

    /// Unix-Sekunden für ein Datum mit Stunde (UTC).
    private func unixAt(_ year: Int, _ month: Int, _ day: Int, hour: Int) -> Int64 {
        let cal = utcCalendar()
        let comps = DateComponents(year: year, month: month, day: day, hour: hour)
        return Int64(cal.date(from: comps)!.timeIntervalSince1970)
    }

    /// Regressionstest gegen die alte String-Sortierung: zwei geplante Items um
    /// 09:00 und 13:00. `.formatted(.hour().minute())` ergäbe in 12h-Locales
    /// „1:00 PM" < „9:00 AM" → 13:00 fälschlich zuerst. Über den rohen Zeitstempel
    /// muss 09:00 zuerst kommen.
    func testAgendaSortScheduledByActualTimeNotFormattedString() {
        let nine = CalendarBucketing.AgendaItem(
            task: task(uuid: "a", description: "Morgens"),
            reason: .scheduled(time: unixAt(2026, 6, 15, hour: 9))
        )
        let thirteen = CalendarBucketing.AgendaItem(
            task: task(uuid: "b", description: "Nachmittags"),
            reason: .scheduled(time: unixAt(2026, 6, 15, hour: 13))
        )
        // Bewusst in „falscher" Reihenfolge übergeben.
        let sorted = CalendarBucketing.sortedAgendaItems([thirteen, nine])
        XCTAssertEqual(sorted.map(\.task.uuid), ["a", "b"], "09:00 muss vor 13:00 stehen")
    }

    func testAgendaSortScheduledBeforeDue() {
        let due = CalendarBucketing.AgendaItem(
            task: task(uuid: "d", description: "Aaa"), reason: .due
        )
        let scheduled = CalendarBucketing.AgendaItem(
            task: task(uuid: "s", description: "Zzz"),
            reason: .scheduled(time: unixAt(2026, 6, 15, hour: 23))
        )
        // Geplant (Gruppe 0) vor fällig (Gruppe 1), unabhängig von Titel/Uhrzeit.
        let sorted = CalendarBucketing.sortedAgendaItems([due, scheduled])
        XCTAssertEqual(sorted.map(\.task.uuid), ["s", "d"])
    }

    func testAgendaSortDueByDescription() {
        let zebra = CalendarBucketing.AgendaItem(task: task(uuid: "z", description: "Zebra"), reason: .due)
        let apfel = CalendarBucketing.AgendaItem(task: task(uuid: "a", description: "Apfel"), reason: .due)
        let sorted = CalendarBucketing.sortedAgendaItems([zebra, apfel])
        XCTAssertEqual(sorted.map(\.task.uuid), ["a", "z"])
    }

    // MARK: - AppLanguage: Formatierungs-Locale (Datumssprache folgt Sprachwahl)

    func testFormattingLocaleFollowsExplicitChoice() {
        XCTAssertEqual(AppLanguage.de.formattingLocale.identifier, "de_DE")
        XCTAssertEqual(AppLanguage.en.formattingLocale.identifier, "en_US")
    }

    func testFormattingLocaleSystemFollowsSystem() {
        XCTAssertEqual(AppLanguage.system.formattingLocale, Locale.autoupdatingCurrent)
    }

    /// Regressionstest gegen den Sprach-Mix „28. June": bei expliziter Sprachwahl
    /// müssen Monatsname UND Konventionen (Reihenfolge, Trennzeichen) der Sprache
    /// folgen — nicht der macOS-Region. Kalender und Zeitzone sind explizit
    /// gepinnt, damit der Test nicht von der Gerätekonfiguration abhängt.
    func testFormattingLocaleProducesLanguageTypicalDates() {
        let d = Date(timeIntervalSince1970: TimeInterval(unix(2026, 6, 15)))
        func style(_ locale: Locale) -> Date.FormatStyle {
            Date.FormatStyle(
                locale: locale,
                calendar: Calendar(identifier: .gregorian),
                timeZone: TimeZone(identifier: "UTC")!
            ).day().month(.wide)
        }
        XCTAssertEqual(d.formatted(style(AppLanguage.de.formattingLocale)), "15. Juni")
        XCTAssertEqual(d.formatted(style(AppLanguage.en.formattingLocale)), "June 15")
    }

    // MARK: - Nächster Termin (Agenda-Leerzustand)

    func testNextRelevantDatePicksEarliestDue() {
        let tasks = [
            task(due: unix(2026, 8, 1)),
            task(due: unix(2026, 7, 1)),
        ]
        let next = CalendarBucketing.nextRelevantDate(tasks: tasks, onOrAfter: dayStart(2026, 6, 19))
        XCTAssertEqual(next, Date(timeIntervalSince1970: TimeInterval(unix(2026, 7, 1))))
    }

    func testNextRelevantDateConsidersScheduled() {
        // scheduled (25.6.) liegt vor due (1.7.) → scheduled gewinnt.
        let tasks = [
            task(due: unix(2026, 7, 1)),
            task(scheduled: unix(2026, 6, 25)),
        ]
        let next = CalendarBucketing.nextRelevantDate(tasks: tasks, onOrAfter: dayStart(2026, 6, 19))
        XCTAssertEqual(next, Date(timeIntervalSince1970: TimeInterval(unix(2026, 6, 25))))
    }

    func testNextRelevantDateIgnoresPastAndNonPending() {
        let tasks = [
            task(due: unix(2026, 6, 1)),                       // vor dem Limit
            task(due: unix(2026, 7, 1), status: .completed),   // nicht pending
        ]
        XCTAssertNil(CalendarBucketing.nextRelevantDate(tasks: tasks, onOrAfter: dayStart(2026, 6, 19)))
    }

    func testNextRelevantDateNilWithoutAnyDates() {
        XCTAssertNil(CalendarBucketing.nextRelevantDate(tasks: [task()], onOrAfter: dayStart(2026, 6, 19)))
    }

    // MARK: - Vorschau-Perspektiven: Mapping + Sichtbarkeits-Gate (Follow-up #11)
    //
    // Reine Logik (`ForecastPerspective`) — daher hier im schlichten XCTestCase
    // statt im @MainActor-ViewModel-Test.

    func testPerspectiveMappingSystemRows() {
        XCTAssertEqual(ForecastPerspective(for: .today), .today)
        XCTAssertEqual(ForecastPerspective(for: .todo), .todo)
        XCTAssertEqual(ForecastPerspective(for: .dueSoon), .dueSoon)
        XCTAssertEqual(ForecastPerspective(for: .upcoming), .upcoming)
        XCTAssertEqual(ForecastPerspective(for: .inbox), .inbox)
        XCTAssertEqual(ForecastPerspective(for: .overdue), .overdue)
        XCTAssertEqual(ForecastPerspective(for: .waiting), .waiting)
        XCTAssertEqual(ForecastPerspective(for: .all), .all)
    }

    func testPerspectiveMappingDynamicRows() {
        XCTAssertEqual(ForecastPerspective(for: .project("Arbeit")), .dynamic)
        XCTAssertEqual(ForecastPerspective(for: .tag("urgent")), .dynamic)
        XCTAssertEqual(ForecastPerspective(for: .savedSearch(UUID())), .dynamic)
    }

    func testPerspectiveMappingDependencyReportsHaveNoPerspective() {
        XCTAssertNil(ForecastPerspective(for: .blocked))
        XCTAssertNil(ForecastPerspective(for: .blocking))
        XCTAssertNil(ForecastPerspective(for: .unblocked))
    }

    // MARK: - ForecastConfig: Defaults, Auflösung, Round-trip (Follow-up #11)

    func testConfigDefaultsForRelevantPerspectives() {
        // today/todo/dueSoon/upcoming → Agenda, 1 Woche, 5 pro Tag, KW an.
        for p in [ForecastPerspective.today, .todo, .dueSoon, .upcoming] {
            let c = ForecastConfig.default(for: p)
            XCTAssertEqual(c.display, .agenda, "\(p.rawValue): Agenda erwartet")
            XCTAssertEqual(c.range, .weeks1)
            XCTAssertEqual(c.maxPerDay, .five)
            XCTAssertTrue(c.showCalendarWeeks)
        }
    }

    func testConfigDefaultsForOffPerspectives() {
        // inbox/overdue/waiting/all/dynamic → aus.
        for p in [ForecastPerspective.inbox, .overdue, .waiting, .all, .dynamic] {
            XCTAssertEqual(ForecastConfig.default(for: p).display, .off, "\(p.rawValue): aus erwartet")
        }
    }

    func testConfigResolveFallsBackToDefaultWhenAbsent() {
        // Leeres Dictionary → jede Perspektive bekommt ihren Default.
        XCTAssertEqual(ForecastConfig.resolve(.today, from: "{}"), ForecastConfig.default(for: .today))
        XCTAssertEqual(ForecastConfig.resolve(.inbox, from: "{}"), ForecastConfig.default(for: .inbox))
    }

    func testConfigResolveCorruptFallsBackToDefault() {
        XCTAssertEqual(ForecastConfig.resolve(.today, from: "nonsense{"), ForecastConfig.default(for: .today))
    }

    func testConfigResolveStoredOverridesDefault() {
        // Gespeicherter Eintrag für inbox (Default = aus) → übersteuert auf Kompakt.
        let stored = ForecastConfig(display: .compact, range: .weeks3, maxPerDay: .three, showCalendarWeeks: false)
        let raw = ForecastConfig.update(.inbox, to: stored, in: "{}")
        XCTAssertEqual(ForecastConfig.resolve(.inbox, from: raw), stored)
        // Andere Perspektiven bleiben auf Default.
        XCTAssertEqual(ForecastConfig.resolve(.today, from: raw), ForecastConfig.default(for: .today))
    }

    func testConfigUpdatePreservesOtherEntries() {
        var raw = "{}"
        let a = ForecastConfig(display: .agenda, range: .weeks2, maxPerDay: .all, showCalendarWeeks: true)
        let b = ForecastConfig(display: .compact, range: .days3, maxPerDay: .five, showCalendarWeeks: false)
        raw = ForecastConfig.update(.today, to: a, in: raw)
        raw = ForecastConfig.update(.overdue, to: b, in: raw)
        XCTAssertEqual(ForecastConfig.resolve(.today, from: raw), a)
        XCTAssertEqual(ForecastConfig.resolve(.overdue, from: raw), b)
    }

    func testConfigEncodeDecodeRoundTrip() {
        let config = ForecastConfig(display: .compact, range: .weeks4, maxPerDay: .three, showCalendarWeeks: false)
        let raw = ForecastConfig.update(.dynamic, to: config, in: "{}")
        let map = ForecastConfig.decodeAll(from: raw)
        XCTAssertEqual(map[ForecastPerspective.dynamic.rawValue], config)
    }

    func testConfigOffMeansHiddenViaResolve() {
        // display == .off ist die Sichtbarkeitssteuerung: Default-aus-Perspektiven
        // lösen zu .off auf (= Vorschau verborgen).
        XCTAssertEqual(ForecastConfig.resolve(.overdue, from: "{}").display, .off)
        // Explizit auf .off gesetzt bleibt .off.
        let off = ForecastConfig(display: .off, range: .weeks1, maxPerDay: .five, showCalendarWeeks: true)
        let raw = ForecastConfig.update(.today, to: off, in: "{}")
        XCTAssertEqual(ForecastConfig.resolve(.today, from: raw).display, .off)
    }

    // MARK: - ForecastRange.weekCount (Single-Week- vs. Mehrwochen-Kompakt)

    func testRangeWeekCountTriggersStacking() {
        // days3/weeks1 → einzeilig (nil); weeks2/3/4 → gestapelt (2/3/4).
        XCTAssertNil(ForecastRange.days3.weekCount)
        XCTAssertNil(ForecastRange.weeks1.weekCount)
        XCTAssertEqual(ForecastRange.weeks2.weekCount, 2)
        XCTAssertEqual(ForecastRange.weeks3.weekCount, 3)
        XCTAssertEqual(ForecastRange.weeks4.weekCount, 4)
    }
}
