import SwiftUI
import VergissmeinnichtKit

/// Schlanker horizontaler Wochen-Streifen über der Aufgabenliste: Tageszellen ab
/// heute über das eingestellte Fenster (`ForecastRange`), je mit locale-Wochentag,
/// Datum und Task-Zähler-Badge (aus `due`+`scheduled`); heute hervorgehoben.
/// Optional links eine ISO-„KW <n>"-Marke. Klick auf eine Zelle wechselt in den
/// Kalender-Modus, fokussiert auf den Monat dieses Tages.
///
/// Zählung liefert `CalendarBucketing.count`, das Fenster `CalendarBucketing.window`,
/// die KW `CalendarBucketing.isoWeek` (separat unit-getestet). Reine Darstellung.
struct ForecastStripView: View {
    let tasks: [TaskInfo]
    let range: ForecastRange
    let showCalendarWeeks: Bool
    let onSelectDay: (Date) -> Void

    private let calendar = Calendar.current

    var body: some View {
        HStack(spacing: 6) {
            if showCalendarWeeks, let first = stripDays.first {
                Text("KW \(CalendarBucketing.isoWeek(of: first, timeZone: calendar.timeZone))")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 2)
            }
            ForEach(stripDays, id: \.self) { day in
                dayCell(day)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private func dayCell(_ day: Date) -> some View {
        let isToday = calendar.isDateInToday(day)
        let count = CalendarBucketing.count(on: day, tasks: tasks, calendar: calendar)
        return Button {
            onSelectDay(day)
        } label: {
            VStack(spacing: 2) {
                Text(weekdaySymbol(day))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(calendar.component(.day, from: day))")
                    .font(.callout.weight(isToday ? .bold : .regular))
                    .foregroundStyle(isToday ? Color.accentColor : Color.primary)
                if count > 0 {
                    Text("\(count)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.accentColor, in: Capsule())
                } else {
                    Text(" ")
                        .font(.caption2)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isToday ? Color.accentColor.opacity(0.10) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Text("\(count) Aufgaben"))
    }

    /// Die Tage des eingestellten Fensters ab heute (geteiltes
    /// `CalendarBucketing.window` mit der Agenda).
    private var stripDays: [Date] {
        let (start, end) = CalendarBucketing.window(for: range, today: Date(), calendar: calendar)
        var days: [Date] = []
        var cursor = start
        while cursor < end {
            days.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return days
    }

    /// Locale-Wochentags-Kürzel (kein hartkodierter String).
    private func weekdaySymbol(_ day: Date) -> String {
        let fmt = DateFormatter()
        fmt.calendar = calendar
        fmt.locale = .autoupdatingCurrent
        let symbols = fmt.shortStandaloneWeekdaySymbols ?? fmt.shortWeekdaySymbols ?? []
        let idx = calendar.component(.weekday, from: day) - 1
        return symbols.indices.contains(idx) ? symbols[idx] : ""
    }
}
