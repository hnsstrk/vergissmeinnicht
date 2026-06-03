import SwiftUI
import VergissmeinnichtKit

/// Schlanker horizontaler Wochen-Streifen über der Aufgabenliste: 7 Tageszellen
/// (locale-Wochentag + Datum + Task-Zähler-Badge aus `due`+`scheduled`), heute
/// hervorgehoben. Klick auf eine Zelle wechselt in den Kalender-Modus, fokussiert
/// auf den Monat dieses Tages — verbindet Streifen (A) und Kalender (B).
///
/// Zählung liefert `CalendarBucketing.count` (separat unit-getestet). Reine
/// Darstellung, schreibt nichts.
struct ForecastStripView: View {
    let tasks: [TaskInfo]
    let onSelectDay: (Date) -> Void

    private let calendar = Calendar.current

    var body: some View {
        HStack(spacing: 6) {
            ForEach(weekDays, id: \.self) { day in
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

    /// Die 7 Tage der aktuellen Woche, beginnend am `firstWeekday` des Kalenders.
    private var weekDays: [Date] {
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        guard let weekStart = calendar.date(byAdding: .day, value: -leading, to: today) else {
            return [today]
        }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
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
