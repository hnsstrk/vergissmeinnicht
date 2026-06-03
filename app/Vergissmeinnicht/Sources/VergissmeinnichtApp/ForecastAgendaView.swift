import SwiftUI
import VergissmeinnichtKit

/// Tagesgruppierte Agenda über der Aufgabenliste (Follow-up #11, Things-„Upcoming"-
/// Qualität): großer Tages-Header (Tag-Nummer + Wochentag + Relativ-Label
/// „Heute"/„Morgen"), darunter die Aufgaben des Tages mit kleinem grauem
/// Projekt-Untertitel, KW-Trenner zwischen ISO-Wochen.
///
/// Reine Darstellung: Tag-Buckets liefert `CalendarBucketing.agendaBuckets`, die
/// Kappung `CalendarBucketing.capped`, die KW `CalendarBucketing.isoWeek` (alle
/// separat unit-getestet). Rendert nur native Felder (`due`/`scheduled`/`project`/
/// `recur`) — kein macOS-Kalender (Product-Prinzip „Taskwarrior-treu").
///
/// Höhe gedeckelt + interne `ScrollView`, damit die Agenda die Liste nicht
/// verdrängt, wenn sie im `safeAreaInset(edge:.top)` sitzt.
struct ForecastAgendaView: View {
    let tasks: [TaskInfo]
    let range: ForecastRange
    let maxPerDay: ForecastMaxPerDay
    let showCalendarWeeks: Bool
    let onOpenDetail: (String) -> Void

    private let calendar = Calendar.current
    /// Obergrenze der Agenda-Höhe; darüber scrollt der Inhalt intern.
    private static let maxHeight: CGFloat = 280

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(days.enumerated()), id: \.element) { index, day in
                    weekSeparator(for: day, previous: index > 0 ? days[index - 1] : nil)
                    daySection(day)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(maxHeight: Self.maxHeight)
        .background(.bar)
    }

    // MARK: - Tages-Abschnitt

    @ViewBuilder
    private func daySection(_ day: Date) -> some View {
        let items = sortedItems(buckets[calendar.startOfDay(for: day)] ?? [])
        let (shown, overflow) = CalendarBucketing.capped(items, cap: maxPerDay.cap)
        VStack(alignment: .leading, spacing: 4) {
            dayHeader(day, count: items.count)
            ForEach(shown, id: \.self) { item in
                agendaRow(item)
            }
            if overflow > 0 {
                Text("+\(overflow)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 2)
            }
        }
        .padding(.bottom, 10)
    }

    private func dayHeader(_ day: Date, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(calendar.component(.day, from: day))")
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(calendar.isDateInToday(day) ? Color.accentColor : Color.primary)
            VStack(alignment: .leading, spacing: 0) {
                Text(relativeLabel(day))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(calendar.isDateInToday(day) ? Color.accentColor : Color.primary)
                Text(weekdayName(day))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if count > 0 {
                Text("\(count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Aufgaben-Zeile (Things-Stil: Titel + grauer Projekt-Untertitel)

    private func agendaRow(_ item: CalendarBucketing.AgendaItem) -> some View {
        Button {
            onOpenDetail(item.task.uuid)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(dotColor(item))
                    .frame(width: 6, height: 6)
                    .padding(.top, 5)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.task.description)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let subtitle = subtitle(item) {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                Spacer(minLength: 4)
            }
            .padding(.vertical, 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Grauer Untertitel: Projekt und/oder „geplant"-Marker mit Uhrzeit. Nur
    /// native Felder — `nil`, wenn nichts darzustellen ist.
    private func subtitle(_ item: CalendarBucketing.AgendaItem) -> String? {
        var parts: [String] = []
        if case .scheduled(let time) = item.reason {
            let date = Date(timeIntervalSince1970: TimeInterval(time))
            let hasTime = !calendar.isDate(date, equalTo: calendar.startOfDay(for: date), toGranularity: .second)
            if hasTime {
                let t = date.formatted(date: .omitted, time: .shortened)
                parts.append(String(localized: "geplant \(t)", comment: "Agenda: geplant mit Uhrzeit"))
            } else {
                parts.append(String(localized: "geplant", comment: "Agenda: geplant ohne Uhrzeit"))
            }
        }
        if let project = item.task.project {
            parts.append(project)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func dotColor(_ item: CalendarBucketing.AgendaItem) -> Color {
        if case .scheduled = item.reason { return .teal }
        if let due = item.task.due, TimeInterval(due) < Date().timeIntervalSince1970 { return .red }
        if item.task.priority == "H" { return .orange }
        return .accentColor
    }

    // MARK: - KW-Trenner (ISO, Montag-erste Woche)

    @ViewBuilder
    private func weekSeparator(for day: Date, previous: Date?) -> some View {
        if showCalendarWeeks, shouldShowSeparator(for: day, previous: previous) {
            let week = CalendarBucketing.isoWeek(of: day, timeZone: calendar.timeZone)
            HStack(spacing: 6) {
                Text("KW \(week)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Rectangle()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(height: 1)
            }
            .padding(.vertical, 4)
        }
    }

    /// Trenner vor dem ersten Tag jeder ISO-Woche (auch vor dem allerersten Tag).
    private func shouldShowSeparator(for day: Date, previous: Date?) -> Bool {
        let tz = calendar.timeZone
        guard let previous else { return true }
        let a = CalendarBucketing.isoWeek(of: previous, timeZone: tz)
        let b = CalendarBucketing.isoWeek(of: day, timeZone: tz)
        let ya = CalendarBucketing.isoYearForWeek(of: previous, timeZone: tz)
        let yb = CalendarBucketing.isoYearForWeek(of: day, timeZone: tz)
        return a != b || ya != yb
    }

    // MARK: - Daten / Datums-Helfer

    private var buckets: [Date: [CalendarBucketing.AgendaItem]] {
        let (start, end) = CalendarBucketing.window(for: range, today: Date(), calendar: calendar)
        return CalendarBucketing.agendaBuckets(tasks: tasks, from: start, to: end, calendar: calendar)
    }

    /// Alle Tage des Fensters, die mindestens eine Aufgabe haben (leere Tage werden
    /// in der Agenda nicht gezeigt — Things-Verhalten, hält die Liste kompakt).
    private var days: [Date] {
        buckets.keys.sorted()
    }

    private func sortedItems(_ items: [CalendarBucketing.AgendaItem]) -> [CalendarBucketing.AgendaItem] {
        items.sorted { a, b in
            sortKey(a) < sortKey(b)
        }
    }

    /// Sortierschlüssel: geplante (mit Uhrzeit) zuerst nach Zeit, dann fällige nach
    /// Titel. Deterministisch, damit die Reihenfolge stabil bleibt.
    private func sortKey(_ item: CalendarBucketing.AgendaItem) -> String {
        switch item.reason {
        case .scheduled(let time):
            let d = Date(timeIntervalSince1970: TimeInterval(time))
            return "0_" + d.formatted(.dateTime.hour().minute()) + item.task.description
        case .due:
            return "1_" + item.task.description
        }
    }

    /// Relativ-Label: „Heute"/„Morgen", sonst voller locale-Wochentag.
    private func relativeLabel(_ day: Date) -> String {
        if calendar.isDateInToday(day) { return String(localized: "Heute") }
        if calendar.isDateInTomorrow(day) { return String(localized: "Morgen") }
        return weekdayName(day)
    }

    /// Voller locale-Wochentagsname (kein hartkodierter String).
    private func weekdayName(_ day: Date) -> String {
        let fmt = DateFormatter()
        fmt.calendar = calendar
        fmt.locale = .autoupdatingCurrent
        let symbols = fmt.standaloneWeekdaySymbols ?? fmt.weekdaySymbols ?? []
        let idx = calendar.component(.weekday, from: day) - 1
        return symbols.indices.contains(idx) ? symbols[idx] : ""
    }
}
