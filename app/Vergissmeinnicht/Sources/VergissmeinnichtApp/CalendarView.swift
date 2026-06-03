import SwiftUI
import VergissmeinnichtKit

/// Monats-Grid-Kalender als eigener Inhalts-Modus (nicht Sidebar-Filter).
/// GUI-Pendant zu Taskwarrior `task calendar`: rendert ausschließlich native
/// Felder (`due`, `scheduled`, `recur`). Schreibt nichts (Product-Prinzip).
///
/// Tag-Buckets liefert `CalendarBucketing` (separat unit-getestet); diese View
/// ist reine Darstellung. Klick auf eine Task öffnet das Detail-Fenster.
struct CalendarView: View {
    let tasks: [TaskInfo]
    /// Optionaler Fokus-Tag (vom Wochen-Streifen gesetzt) → bestimmt Startmonat.
    let focusDate: Date?
    let onOpenDetail: (String) -> Void

    @State private var visibleMonth: Date = Date()
    @State private var agendaDay: AgendaDay?

    private let calendar = Calendar.current
    /// Max. Chips pro Tag vor "+N"-Überlauf.
    private static let chipCap = 3

    var body: some View {
        VStack(spacing: 0) {
            header
            weekdayHeader
            grid
            Spacer(minLength: 0)
        }
        .onAppear {
            if let focusDate { visibleMonth = focusDate }
        }
        .onChange(of: focusDate) { _, new in
            if let new { visibleMonth = new }
        }
        .popover(item: $agendaDay) { day in
            agendaPopover(day)
        }
    }

    // MARK: - Kopf / Navigation

    private var header: some View {
        HStack {
            Button {
                shiftMonth(-1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .help(Text("Vorheriger Monat"))

            Text(monthTitle)
                .font(.title2.weight(.semibold))
                .frame(minWidth: 180)

            Button {
                shiftMonth(1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
            .help(Text("Nächster Monat"))

            Spacer()

            Button("Heute") {
                visibleMonth = Date()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var weekdayHeader: some View {
        HStack(spacing: 4) {
            ForEach(orderedWeekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 12)
    }

    private var grid: some View {
        let buckets = CalendarBucketing.buckets(tasks: tasks, monthOf: visibleMonth, calendar: calendar)
        let weeks = monthGridDays()
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(weeks, id: \.self) { day in
                dayCell(day, entries: buckets[calendar.startOfDay(for: day)] ?? [])
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Tag-Zelle

    @ViewBuilder
    private func dayCell(_ day: Date, entries: [CalendarBucketing.Entry]) -> some View {
        let inMonth = calendar.isDate(day, equalTo: visibleMonth, toGranularity: .month)
        let isToday = calendar.isDateInToday(day)
        VStack(alignment: .leading, spacing: 2) {
            Text("\(calendar.component(.day, from: day))")
                .font(.caption.weight(isToday ? .bold : .regular))
                .foregroundStyle(isToday ? Color.accentColor : (inMonth ? Color.primary : Color.secondary))
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(Array(entries.prefix(Self.chipCap).enumerated()), id: \.offset) { _, entry in
                entryChip(entry)
            }
            if entries.count > Self.chipCap {
                Text("+\(entries.count - Self.chipCap)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(4)
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isToday ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isToday ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if !entries.isEmpty {
                agendaDay = AgendaDay(date: day, tasks: orderedUniqueTasks(entries))
            }
        }
    }

    @ViewBuilder
    private func entryChip(_ entry: CalendarBucketing.Entry) -> some View {
        let task = entry.task
        let color = chipColor(task)
        switch entry {
        case .span(_, let isStart, let isEnd):
            Text(task.description)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(color)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    UnevenRoundedRectangle(
                        topLeadingRadius: isStart ? 4 : 0,
                        bottomLeadingRadius: isStart ? 4 : 0,
                        bottomTrailingRadius: isEnd ? 4 : 0,
                        topTrailingRadius: isEnd ? 4 : 0
                    )
                    .fill(color.opacity(0.18))
                )
        case .chip:
            HStack(spacing: 3) {
                Circle().fill(color).frame(width: 5, height: 5)
                Text(task.description)
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.12), in: Capsule())
        }
    }

    // MARK: - Tages-Agenda-Popover

    private func agendaPopover(_ day: AgendaDay) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(day.date.formatted(date: .complete, time: .omitted))
                .font(.headline)
                .padding(.bottom, 2)
            ForEach(day.tasks, id: \.uuid) { task in
                Button {
                    agendaDay = nil
                    onOpenDetail(task.uuid)
                } label: {
                    TaskRowView(task: task)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(minWidth: 280, maxWidth: 360)
    }

    // MARK: - Farb-/Datums-Logik

    /// Chip-Farbe: überfällig → rot, hohe Priorität → orange, sonst akzentblau.
    /// Konsistent mit der Listen-Chip-Semantik (rot = überfällig).
    private func chipColor(_ task: TaskInfo) -> Color {
        if let due = task.due, TimeInterval(due) < Date().timeIntervalSince1970 {
            return .red
        }
        if task.priority == "H" { return .orange }
        return .accentColor
    }

    private func shiftMonth(_ delta: Int) {
        if let new = calendar.date(byAdding: .month, value: delta, to: visibleMonth) {
            visibleMonth = new
        }
    }

    private var monthTitle: String {
        let fmt = DateFormatter()
        fmt.calendar = calendar
        fmt.locale = .autoupdatingCurrent
        fmt.setLocalizedDateFormatFromTemplate("yMMMM")
        return fmt.string(from: visibleMonth)
    }

    /// Wochentags-Kürzel in der Reihenfolge des aktuellen Kalenders (locale-aware,
    /// keine hartkodierten Strings).
    private var orderedWeekdaySymbols: [String] {
        let fmt = DateFormatter()
        fmt.calendar = calendar
        fmt.locale = .autoupdatingCurrent
        let symbols = fmt.shortStandaloneWeekdaySymbols ?? fmt.shortWeekdaySymbols ?? []
        guard symbols.count == 7 else { return symbols }
        let first = calendar.firstWeekday - 1 // firstWeekday ist 1-basiert
        return Array(symbols[first...] + symbols[..<first])
    }

    /// Alle Tage des Grids: vom ersten Wochentag der Woche, in die der 1. fällt,
    /// bis das Grid eine volle Wochenzahl (i. d. R. 6) füllt.
    private func monthGridDays() -> [Date] {
        let monthStart = CalendarBucketing.startOfMonth(visibleMonth, calendar: calendar)
        let weekday = calendar.component(.weekday, from: monthStart)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        guard let gridStart = calendar.date(byAdding: .day, value: -leading, to: monthStart) else {
            return [monthStart]
        }
        // 6 Wochen × 7 = 42 Zellen decken jeden Monat ab.
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
    }

    /// Deduplizierte, stabil sortierte Tasks für die Tages-Agenda (eine Task kann
    /// als Span mehrere Entries am selben Tag haben — hier nur einmal zeigen).
    private func orderedUniqueTasks(_ entries: [CalendarBucketing.Entry]) -> [TaskInfo] {
        var seen = Set<String>()
        var out: [TaskInfo] = []
        for entry in entries where !seen.contains(entry.task.uuid) {
            seen.insert(entry.task.uuid)
            out.append(entry.task)
        }
        return out.sorted { a, b in
            a.description.localizedCaseInsensitiveCompare(b.description) == .orderedAscending
        }
    }
}

/// Identifizierbares Modell für das Tages-Agenda-Popover.
private struct AgendaDay: Identifiable {
    let date: Date
    let tasks: [TaskInfo]
    var id: Date { date }
}
