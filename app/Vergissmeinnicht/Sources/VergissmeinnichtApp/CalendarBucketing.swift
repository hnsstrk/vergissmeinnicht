import Foundation
import VergissmeinnichtKit

/// Reine, synchrone Präsentationslogik für Kalender (`CalendarView`) und
/// Wochen-Streifen (`ForecastStripView`): bucketet Tasks auf Kalendertage.
///
/// Bewusst `Calendar`-Parameter statt `Calendar.current` im Inneren — so ist die
/// Logik deterministisch testbar (fester UTC-Kalender wie in den Integrationstests)
/// und ohne Aktor-Isolation von den MainActor-Views aufrufbar. Schreibt nichts,
/// erfindet keine Daten: rendert nur die nativen Felder `due`, `scheduled`, `recur`
/// (Product-Prinzip „Taskwarrior-treu").
///
/// `SidebarFilter`/`matches` bleibt unberührt (Karpathy 3) — das hier ist
/// Darstellungslogik, kein Sidebar-Filter.
enum CalendarBucketing {

    /// Eintrag für eine Task an einem Kalendertag.
    enum Entry: Hashable {
        /// Einzel-Marker (nur `due`, oder eine Recur-Wiederholung, oder der Span-Anker).
        case chip(TaskInfo)
        /// Teil eines `scheduled`→`due`-Mehrtagesbalkens ("Dauer").
        /// `isStart`/`isEnd` markieren die Balkenenden für abgerundete Kanten.
        case span(TaskInfo, isStart: Bool, isEnd: Bool)

        var task: TaskInfo {
            switch self {
            case .chip(let t):       return t
            case .span(let t, _, _): return t
            }
        }
    }

    /// Sicherheitsobergrenze für Recur-Iteration: ein weit in der Vergangenheit
    /// liegender `daily`-Anker dürfte sonst pro Render unbegrenzt schleifen.
    static let maxRecurIterations = 2000

    /// Bucketet alle (pending) Tasks auf die Tage von `monthStart` bis exklusive
    /// nächsten Monatsanfang. Schlüssel ist `calendar.startOfDay(for:)` des Tages.
    ///
    /// - `due`-only → ein `.chip` am Fälligkeitstag.
    /// - `scheduled` UND `due` → `.span` über alle Tage von scheduled bis due.
    /// - `recur` → wiederholte `.chip`s je Vorkommen im sichtbaren Monat
    ///   (Span-Tasks: Balken auf Basis-Vorkommen, weitere Vorkommen als Chips).
    static func buckets(
        tasks: [TaskInfo],
        monthOf reference: Date,
        calendar: Calendar
    ) -> [Date: [Entry]] {
        let monthStart = startOfMonth(reference, calendar: calendar)
        guard let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else {
            return [:]
        }
        var result: [Date: [Entry]] = [:]

        for task in tasks where task.status == .pending {
            addEntries(for: task, monthStart: monthStart, monthEnd: monthEnd, calendar: calendar, into: &result)
        }
        return result
    }

    // MARK: - Agenda (Follow-up #11)

    /// Grund, warum eine Task an einem Agenda-Tag erscheint. Anders als das
    /// `Entry`-Modell des Monats-Grids (das nur *wo* kodiert) trägt die Agenda
    /// auch das *warum* — eine Task mit `scheduled` UND `due` erscheint zweimal:
    /// am `scheduled`-Tag als „geplant" (Things-Verhalten), am `due`-Tag als
    /// fällig. Das ist einfacher als der Mehrtagesbalken und nah am Things-Vorbild.
    enum AgendaReason: Hashable {
        /// Fällig an diesem Tag (`due`).
        case due
        /// Geplant an diesem Tag (`scheduled`); `time` = Unix-Sekunden des
        /// Zeitpunkts (für die Uhrzeit-Anzeige), falls vorhanden.
        case scheduled(time: Int64)
    }

    /// Ein Agenda-Eintrag: Task + Grund. Reine Daten, keine View-Abhängigkeit.
    struct AgendaItem: Hashable {
        let task: TaskInfo
        let reason: AgendaReason
    }

    /// Bucketet (pending) Tasks auf die Tage des Fensters `[windowStart, windowEnd)`.
    /// Schlüssel ist `calendar.startOfDay(for:)`. Eine Task landet pro relevantem
    /// Feld einmal: `due`-Tag als `.due`, `scheduled`-Tag als `.scheduled`. Recur
    /// expandiert in `.due`-Vorkommen (analog Monats-Grid, gemeinsames Stepping).
    /// Kein Span — die Agenda ist tagesgruppiert, nicht balkenorientiert.
    static func agendaBuckets(
        tasks: [TaskInfo],
        from windowStart: Date,
        to windowEnd: Date,
        calendar: Calendar
    ) -> [Date: [AgendaItem]] {
        let startDay = calendar.startOfDay(for: windowStart)
        var result: [Date: [AgendaItem]] = [:]

        for task in tasks where task.status == .pending {
            // scheduled → „geplant" am scheduled-Tag (mit Uhrzeit).
            if let scheduled = task.scheduled {
                let day = calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(scheduled)))
                if day >= startDay && day < windowEnd {
                    result[day, default: []].append(
                        AgendaItem(task: task, reason: .scheduled(time: scheduled))
                    )
                }
            }

            // due → fällig am due-Tag (Recur expandiert die due-Vorkommen).
            guard let due = task.due else { continue }
            let hasRecur = (task.recur.map { !$0.isEmpty } ?? false)
                && RecurParser.components(from: task.recur ?? "") != nil
            if hasRecur, let raw = task.recur, let delta = RecurParser.components(from: raw) {
                addRecurDueItems(task, anchorUnix: due, delta: delta,
                                 startDay: startDay, windowEnd: windowEnd,
                                 calendar: calendar, into: &result)
            } else {
                let day = calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(due)))
                if day >= startDay && day < windowEnd {
                    result[day, default: []].append(AgendaItem(task: task, reason: .due))
                }
            }
        }
        return result
    }

    /// Kappung pro Tag: gibt die anzuzeigenden Items und die Anzahl der
    /// verborgenen Überlauf-Items zurück. Pure Funktion (unit-getestet), damit die
    /// „+N"-Logik nicht im View-Body versteckt liegt.
    static func capped(_ items: [AgendaItem], cap: Int?) -> (shown: [AgendaItem], overflow: Int) {
        guard let cap, items.count > cap else { return (items, 0) }
        return (Array(items.prefix(cap)), items.count - cap)
    }

    /// Sortiert die Agenda-Items eines Tages: geplante (Gruppe 0) vor fälligen
    /// (Gruppe 1), innerhalb der geplanten nach tatsächlichem Zeitstempel, sonst
    /// nach Titel. Sortiert über den rohen `Int64`-Zeitstempel statt über einen
    /// locale-formatierten Uhrzeit-String — sonst kann „1:00 PM" < „9:00 AM"
    /// fälschlich 13:00 vor 09:00 einsortieren (Follow-up #11). Pure Funktion
    /// (unit-getestet).
    static func sortedAgendaItems(_ items: [AgendaItem]) -> [AgendaItem] {
        items.sorted { agendaSortPrecedes($0, $1) }
    }

    /// Vergleichs-Prädikat für `sortedAgendaItems` — separat, damit der Test es
    /// direkt aufrufen kann.
    static func agendaSortPrecedes(_ a: AgendaItem, _ b: AgendaItem) -> Bool {
        let (ga, ta) = agendaSortKey(a)
        let (gb, tb) = agendaSortKey(b)
        if ga != gb { return ga < gb }
        if ta != tb { return ta < tb }
        return a.task.description.localizedCaseInsensitiveCompare(b.task.description) == .orderedAscending
    }

    /// (Gruppe, Zeit): geplante = Gruppe 0 mit ihrem Zeitstempel, fällige = Gruppe 1
    /// (Zeit irrelevant, daher 0 — nur der Titel ordnet sie).
    private static func agendaSortKey(_ item: AgendaItem) -> (Int, Int64) {
        switch item.reason {
        case .scheduled(let time): return (0, time)
        case .due:                 return (1, 0)
        }
    }

    /// ISO-8601-Kalenderwoche (deutsche KW-Konvention: Montag-erster Tag, Woche 1 =
    /// erste Woche mit ≥4 Tagen). Bewusst ein eigener, explizit konfigurierter
    /// Kalender — nicht der locale-abhängige `Calendar(identifier:.iso8601)` allein,
    /// dessen `firstWeekday` von der Locale verschoben werden kann.
    static func isoWeek(of date: Date, timeZone: TimeZone) -> Int {
        isoCalendar(timeZone: timeZone).component(.weekOfYear, from: date)
    }

    /// ISO-Wochen-Jahr (`yearForWeekOfYear`) — am Jahreswechsel kann es vom
    /// Kalenderjahr abweichen (z. B. 1.1.2027 liegt in KW53/2026).
    static func isoYearForWeek(of date: Date, timeZone: TimeZone) -> Int {
        isoCalendar(timeZone: timeZone).component(.yearForWeekOfYear, from: date)
    }

    /// Agenda-Fenster `[start, end)` für eine `ForecastRange`. Start = Tagesanfang
    /// von `today` (vorwärtsgerichtet — die Agenda listet nur Tage MIT Aufgaben,
    /// zeigt also keine vergangenen Tage; deshalb braucht sie keine
    /// Wochen-Ausrichtung). Gegenstück: `compactGridWindow` für den Kompakt-Streifen.
    ///
    /// - `days3` → rollende 3 Tage (`start + 3`).
    /// - `weeks1` → rollende 7 Tage (`start + 7`, entspricht dem alten `days7`,
    ///   NICHT ISO-ausgerichtet — straddelt ggf. zwei KW).
    /// - `weeks2/3/4` → bis zum Ende der N-ten ISO-Woche: Montag dieser Woche
    ///   + `7·N` Tage (exklusiv). `start` bleibt Tagesanfang heute; nur `end` ist
    ///   ISO-Wochen-ausgerichtet.
    static func agendaWindow(
        for range: ForecastRange,
        today: Date,
        calendar: Calendar
    ) -> (start: Date, end: Date) {
        let start = calendar.startOfDay(for: today)
        switch range {
        case .days3:
            let end = calendar.date(byAdding: .day, value: 3, to: start) ?? start
            return (start, end)
        case .weeks1:
            let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
            return (start, end)
        case .weeks2, .weeks3, .weeks4:
            let n = range.weekCount ?? 2
            let iso = isoCalendar(timeZone: calendar.timeZone)
            let weekday = iso.component(.weekday, from: start) // 1=So…2=Mo
            let leading = (weekday - iso.firstWeekday + 7) % 7
            let weekStart = iso.date(byAdding: .day, value: -leading, to: start) ?? start
            let end = iso.date(byAdding: .day, value: 7 * n, to: weekStart) ?? start
            return (start, end)
        }
    }

    /// Kompakt-Gitter-Fenster `[start, end)` für den Wochen-Streifen. Im Gegensatz
    /// zur Agenda zeigt der Streifen ein KW-ausgerichtetes RASTER: jede Zeile eine
    /// volle ISO-Woche (Mo–So), Spalten untereinander bündig. Deshalb kann `start`
    /// VOR heute liegen (Montag der aktuellen Woche) — die vergangenen Tage der
    /// laufenden Woche werden für die Spalten-Ausrichtung gezeigt (View dimmt sie).
    ///
    /// - `days3` → rollende 3 Tage ab heute (KEIN Raster — das ist das explizite
    ///   kurze Fenster, einzeilig und bewusst unausgerichtet).
    /// - `weeks1/2/3/4` → Montag der aktuellen ISO-Woche + `7·N` Tage (exklusiv);
    ///   `weeks1` → N=1 (volle laufende Woche), `weeks4` → N=4 (28 Tage = 4 volle
    ///   Wochen, Mini-Monats-Raster).
    static func compactGridWindow(
        for range: ForecastRange,
        today: Date,
        calendar: Calendar
    ) -> (start: Date, end: Date) {
        let start = calendar.startOfDay(for: today)
        switch range {
        case .days3:
            let end = calendar.date(byAdding: .day, value: 3, to: start) ?? start
            return (start, end)
        case .weeks1, .weeks2, .weeks3, .weeks4:
            // weeks1 hat weekCount == nil (steuert die einzeilige Darstellung),
            // ist im Gitter aber N=1. Daher hier explizit ableiten, nicht über
            // weekCount (Simplicity-Falle: nil ≠ 1).
            let n: Int
            switch range {
            case .weeks1: n = 1
            case .weeks2: n = 2
            case .weeks3: n = 3
            case .weeks4: n = 4
            case .days3:  n = 1 // unerreichbar (oben behandelt)
            }
            let iso = isoCalendar(timeZone: calendar.timeZone)
            let weekday = iso.component(.weekday, from: start) // 1=So…2=Mo
            let leading = (weekday - iso.firstWeekday + 7) % 7
            let weekStart = iso.date(byAdding: .day, value: -leading, to: start) ?? start
            let end = iso.date(byAdding: .day, value: 7 * n, to: weekStart) ?? weekStart
            return (weekStart, end)
        }
    }

    /// Teilt das Fenster `[windowStart, windowEnd)` in ISO-Wochen-Gruppen für die
    /// mehrwöchige Kompakt-Stapelung: pro Gruppe die KW-Nummer (Montag-erste Woche)
    /// und die Tage dieser Woche, die ins Fenster fallen. Reihenfolge chronologisch.
    /// Reine Logik (unit-getestet) — der View stapelt nur die zurückgegebenen Gruppen.
    static func weekGroups(
        from windowStart: Date,
        to windowEnd: Date,
        calendar: Calendar
    ) -> [(week: Int, days: [Date])] {
        let tz = calendar.timeZone
        var groups: [(week: Int, days: [Date])] = []
        var cursor = calendar.startOfDay(for: windowStart)
        var guardCount = 0
        while cursor < windowEnd && guardCount < maxRecurIterations {
            let week = isoWeek(of: cursor, timeZone: tz)
            let year = isoYearForWeek(of: cursor, timeZone: tz)
            var days: [Date] = []
            while cursor < windowEnd
                && isoWeek(of: cursor, timeZone: tz) == week
                && isoYearForWeek(of: cursor, timeZone: tz) == year
                && guardCount < maxRecurIterations {
                days.append(cursor)
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
                guardCount += 1
            }
            groups.append((week: week, days: days))
        }
        return groups
    }

    /// Explizit konfigurierter ISO-Kalender: Montag-erster, ≥4 Tage in Woche 1.
    static func isoCalendar(timeZone: TimeZone) -> Calendar {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = timeZone
        cal.firstWeekday = 2            // Montag
        cal.minimumDaysInFirstWeek = 4  // Woche 1 = erste Woche mit ≥4 Tagen
        return cal
    }

    private static func addRecurDueItems(
        _ task: TaskInfo,
        anchorUnix: Int64,
        delta: DateComponents,
        startDay: Date,
        windowEnd: Date,
        calendar: Calendar,
        into result: inout [Date: [AgendaItem]]
    ) {
        var occurrence = Date(timeIntervalSince1970: TimeInterval(anchorUnix))
        var iterations = 0
        while occurrence < startDay && iterations < maxRecurIterations {
            guard let next = calendar.date(byAdding: delta, to: occurrence) else { return }
            occurrence = next
            iterations += 1
        }
        while occurrence < windowEnd && iterations < maxRecurIterations {
            let day = calendar.startOfDay(for: occurrence)
            if day >= startDay {
                result[day, default: []].append(AgendaItem(task: task, reason: .due))
            }
            guard let next = calendar.date(byAdding: delta, to: occurrence) else { break }
            occurrence = next
            iterations += 1
        }
    }

    /// Frühester Termin (`due` ODER `scheduled`) einer pending Task ab `limit` —
    /// für den Agenda-Leerzustand („Nächster Termin: …"). `nil`, wenn keine
    /// pending Task einen Zeitpunkt ab `limit` trägt. Kein Recur-Stepping (wie
    /// `count(on:)`): eine Recur-Task mit künftigem Anker zählt über ihren Anker;
    /// ein Anker in der Vergangenheit hätte Vorkommen im Agenda-Fenster und der
    /// Leerzustand griffe gar nicht erst (Simplicity).
    static func nextRelevantDate(tasks: [TaskInfo], onOrAfter limit: Date) -> Date? {
        let threshold = Int64(limit.timeIntervalSince1970)
        var best: Int64?
        for task in tasks where task.status == .pending {
            for stamp in [task.due, task.scheduled].compactMap({ $0 })
            where stamp >= threshold && stamp < (best ?? Int64.max) {
                best = stamp
            }
        }
        return best.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    /// Tages-Zählung (für den Wochen-Streifen-Badge): Anzahl Tasks, die an `day`
    /// einen `due`- ODER `scheduled`-Zeitpunkt haben. Kein Recur-Stepping —
    /// der Streifen zeigt die nahe Woche, Recur-Wiederholungen sind dort selten
    /// relevant und würden die Zählung verfälschen (Simplicity).
    static func count(on day: Date, tasks: [TaskInfo], calendar: Calendar) -> Int {
        let target = calendar.startOfDay(for: day)
        return tasks.reduce(0) { acc, task in
            guard task.status == .pending else { return acc }
            let dueHit = task.due.map { sameDay($0, target, calendar) } ?? false
            let schedHit = task.scheduled.map { sameDay($0, target, calendar) } ?? false
            return acc + (dueHit || schedHit ? 1 : 0)
        }
    }

    // MARK: - Intern

    private static func addEntries(
        for task: TaskInfo,
        monthStart: Date,
        monthEnd: Date,
        calendar: Calendar,
        into result: inout [Date: [Entry]]
    ) {
        let hasRecur = (task.recur.map { !$0.isEmpty } ?? false)
            && RecurParser.components(from: task.recur ?? "") != nil

        // Span-Task (scheduled UND due): Balken auf dem Basis-Vorkommen.
        if let scheduled = task.scheduled, let due = task.due, due >= scheduled {
            addSpan(task, fromUnix: scheduled, toUnix: due,
                    monthStart: monthStart, monthEnd: monthEnd, calendar: calendar, into: &result)
            // Recur + Span: weitere Vorkommen nur als Chips (kein kombinatorischer Balken).
            if hasRecur {
                addRecurChips(task, anchorUnix: due, skipFirst: true,
                              monthStart: monthStart, monthEnd: monthEnd, calendar: calendar, into: &result)
            }
            return
        }

        // Anker für reine `due`/`scheduled`-Tasks.
        let anchorUnix = task.due ?? task.scheduled
        guard let anchorUnix else { return }

        if hasRecur {
            addRecurChips(task, anchorUnix: anchorUnix, skipFirst: false,
                          monthStart: monthStart, monthEnd: monthEnd, calendar: calendar, into: &result)
        } else {
            let day = calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(anchorUnix)))
            if day >= monthStart && day < monthEnd {
                result[day, default: []].append(.chip(task))
            }
        }
    }

    private static func addSpan(
        _ task: TaskInfo,
        fromUnix: Int64,
        toUnix: Int64,
        monthStart: Date,
        monthEnd: Date,
        calendar: Calendar,
        into result: inout [Date: [Entry]]
    ) {
        let spanStart = calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(fromUnix)))
        let spanEnd = calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(toUnix)))
        var cursor = spanStart
        var guardCount = 0
        while cursor <= spanEnd && guardCount < maxRecurIterations {
            if cursor >= monthStart && cursor < monthEnd {
                result[cursor, default: []].append(
                    .span(task, isStart: cursor == spanStart, isEnd: cursor == spanEnd)
                )
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
            guardCount += 1
        }
    }

    private static func addRecurChips(
        _ task: TaskInfo,
        anchorUnix: Int64,
        skipFirst: Bool,
        monthStart: Date,
        monthEnd: Date,
        calendar: Calendar,
        into result: inout [Date: [Entry]]
    ) {
        guard let raw = task.recur, let delta = RecurParser.components(from: raw) else {
            // Unparsebar → nur Basis-Marker, keine erfundenen Daten.
            let day = calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(anchorUnix)))
            if day >= monthStart && day < monthEnd {
                result[day, default: []].append(.chip(task))
            }
            return
        }

        var occurrence = Date(timeIntervalSince1970: TimeInterval(anchorUnix))
        var iterations = 0
        var first = true

        // Vorrücken bis ins/über den sichtbaren Monat.
        while occurrence < monthStart && iterations < maxRecurIterations {
            guard let next = calendar.date(byAdding: delta, to: occurrence) else { return }
            occurrence = next
            iterations += 1
            first = false
        }

        while occurrence < monthEnd && iterations < maxRecurIterations {
            let day = calendar.startOfDay(for: occurrence)
            if day >= monthStart && !(skipFirst && first) {
                result[day, default: []].append(.chip(task))
            }
            guard let next = calendar.date(byAdding: delta, to: occurrence) else { break }
            occurrence = next
            iterations += 1
            first = false
        }
    }

    // MARK: - Datums-Helfer

    /// Erster Tag des Monats, der `reference` enthält (Tagesanfang).
    static func startOfMonth(_ reference: Date, calendar: Calendar) -> Date {
        let comps = calendar.dateComponents([.year, .month], from: reference)
        return calendar.date(from: comps) ?? calendar.startOfDay(for: reference)
    }

    private static func sameDay(_ unix: Int64, _ dayStart: Date, _ calendar: Calendar) -> Bool {
        let d = calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(unix)))
        return d == dayStart
    }
}
