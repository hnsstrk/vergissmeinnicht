import SwiftUI
import VergissmeinnichtKit

/// Kompakte Wochen-Vorschau über der Aufgabenliste. Zwei Darstellungen je nach
/// `ForecastRange`:
///
/// - `days3` (kurzes, explizit unausgerichtetes Fenster) → EINE rollende Zeile ab
///   heute, je Zelle mit locale-Wochentag, Datum und Task-Zähler-Badge.
/// - `weeks1/2/3/4` → ein KW-AUSGERICHTETES RASTER: jede Zeile eine volle ISO-Woche
///   (Mo–So), Spalten untereinander bündig (Mini-Monats-Kalender bei 3–4 Wochen).
///   Wochentags-Köpfe einmal oben, KW-Marken in einer durchgehenden linken Spalte.
///   Das Fenster beginnt am Montag der laufenden ISO-Woche — vergangene Tage der
///   aktuellen Woche werden für die Ausrichtung gezeigt, aber gedimmt; heute ist
///   hervorgehoben.
///
/// Höhe dynamisch wie die Agenda: kurzer Inhalt passt sich an, ein 4-Wochen-Raster
/// scrollt intern unter einer Obergrenze (`maxHeight`), damit die Liste nie
/// verdrängt wird. Klick auf eine Zelle wechselt in den Kalender-Modus.
///
/// Zählung liefert `CalendarBucketing.count`, das Fenster
/// `CalendarBucketing.compactGridWindow`, die Wochen-Gruppierung
/// `CalendarBucketing.weekGroups`, die KW `CalendarBucketing.isoWeek` (alle separat
/// unit-getestet). Reine Darstellung.
struct ForecastStripView: View {
    let tasks: [TaskInfo]
    let range: ForecastRange
    let showCalendarWeeks: Bool
    let onSelectDay: (Date) -> Void

    private let calendar = Calendar.current
    /// Obergrenze der Streifen-Höhe; darüber scrollt der Inhalt intern (Sicherheit
    /// gegen ein hohes 4-Wochen-Raster). Spiegelt bewusst den Agenda-Deckel.
    private static let maxHeight: CGFloat = 320
    /// Gemessene intrinsische Inhaltshöhe (via Hintergrund-GeometryReader).
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            content
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: ForecastStripHeightKey.self, value: proxy.size.height)
                    }
                )
        }
        // Dynamisch: kurzer Inhalt → exakte Inhaltshöhe, sonst gedeckelt mit Scroll.
        // Vor erster Messung (`== 0`) den Deckel als sichere Obergrenze nehmen —
        // sonst greift die ScrollView im `safeAreaInset` kurz die volle Höhe und
        // schiebt die Liste (gleiches Muster wie die Agenda).
        .frame(height: contentHeight > 0 ? min(contentHeight, Self.maxHeight) : Self.maxHeight)
        .onPreferenceChange(ForecastStripHeightKey.self) { contentHeight = $0 }
        .background(.bar)
    }

    @ViewBuilder
    private var content: some View {
        if range == .days3 {
            // Kurzes Fenster: eine rollende Zeile ab heute (nicht KW-ausgerichtet).
            rollingRow
        } else {
            // Mehrwöchiges KW-Raster (weeks1 = 1 Zeile, weeks4 = 4 Zeilen).
            weekGrid
        }
    }

    // MARK: - days3: rollende Einzelzeile

    private var rollingRow: some View {
        HStack(spacing: 6) {
            ForEach(rollingDays, id: \.self) { day in
                rollingCell(day)
            }
        }
    }

    /// Tage des rollenden Fensters ab heute (nur `days3`).
    private var rollingDays: [Date] {
        let (start, end) = CalendarBucketing.compactGridWindow(for: range, today: Date(), calendar: calendar)
        var days: [Date] = []
        var cursor = start
        while cursor < end {
            days.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return days
    }

    /// Zelle mit eigenem Wochentags-Kopf (rollende Zeile hat keine Kopfzeile).
    private func rollingCell(_ day: Date) -> some View {
        VStack(spacing: 2) {
            Text(weekdaySymbol(day))
                .font(.caption2)
                .foregroundStyle(.secondary)
            dayCellCore(day)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - weeks1–4: KW-ausgerichtetes Raster

    private var weekGroups: [(week: Int, days: [Date])] {
        let (start, end) = CalendarBucketing.compactGridWindow(for: range, today: Date(), calendar: calendar)
        return CalendarBucketing.weekGroups(from: start, to: end, calendar: calendar)
    }

    /// Das Raster: Kopfzeile (KW-Gutter + 7 Wochentage) und eine `GridRow` je Woche.
    /// `Grid` richtet die Spalten automatisch bündig aus; geringer `verticalSpacing`
    /// lässt 3–4 Wochen als zusammenhängenden Block lesen (kein gestapelter Balken).
    private var weekGrid: some View {
        let groups = weekGroups
        return Grid(alignment: .center, horizontalSpacing: 6, verticalSpacing: 3) {
            // Kopfzeile: Wochentage aus der ERSTEN vollen Woche abgeleitet — da jede
            // Zeile eine volle Mo–So-Woche ist, passen Kopf und Spalten strukturell.
            if let headerDays = groups.first?.days {
                GridRow {
                    weekColumnLabel(nil) // leere Gutter-Zelle (hält Spaltenbreite)
                    ForEach(headerDays, id: \.self) { day in
                        Text(weekdaySymbol(day))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            ForEach(groups, id: \.week) { group in
                GridRow {
                    weekColumnLabel(showCalendarWeeks ? group.week : nil)
                    ForEach(group.days, id: \.self) { day in
                        dayCellCore(day)
                    }
                }
            }
        }
    }

    /// KW-Marke in der linken Gutter-Spalte (durchgehend ausgerichtet). `nil` →
    /// unsichtbare Platzhalter-Marke, die die Spaltenbreite konstant hält (so bleibt
    /// das Raster auch ohne KW-Anzeige bündig).
    private func weekColumnLabel(_ week: Int?) -> some View {
        Text(week.map { "KW \($0)" } ?? "KW 00")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .opacity(week == nil ? 0 : 1)
            .padding(.trailing, 2)
    }

    // MARK: - Tageszelle (gemeinsamer Kern: Datum + Badge)

    /// Datum + Zähler-Badge, ohne Wochentags-Kopf. Heute hervorgehoben; vergangene
    /// Tage gedimmt (inkl. Badge — z. B. Überfälliges bleibt sichtbar, aber zurück-
    /// genommen). Klick öffnet den Kalender-Monat dieses Tages.
    private func dayCellCore(_ day: Date) -> some View {
        let isToday = calendar.isDateInToday(day)
        let isPast = day < calendar.startOfDay(for: Date())
        let count = CalendarBucketing.count(on: day, tasks: tasks, calendar: calendar)
        return Button {
            onSelectDay(day)
        } label: {
            VStack(spacing: 2) {
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
                    // Platzhalter hält die Zellenhöhe konstant → Zeilen bleiben bündig.
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
            .opacity(isPast ? 0.4 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Text("\(count) Aufgaben"))
    }

    // MARK: - Helfer

    /// Locale-Wochentags-Kürzel (kein hartkodierter String); App-Sprach-Locale
    /// statt System-Region (siehe `AppLanguage.formattingLocale`).
    private func weekdaySymbol(_ day: Date) -> String {
        let fmt = DateFormatter()
        fmt.calendar = calendar
        fmt.locale = AppLanguage.currentFormattingLocale
        let symbols = fmt.shortStandaloneWeekdaySymbols ?? fmt.shortWeekdaySymbols ?? []
        let idx = calendar.component(.weekday, from: day) - 1
        return symbols.indices.contains(idx) ? symbols[idx] : ""
    }
}

/// Trägt die gemessene intrinsische Inhaltshöhe des Streifens nach oben, damit die
/// Höhe dynamisch (Inhalt vs. Deckel) gesetzt werden kann — lokale Kopie des
/// Agenda-Musters, damit der Diff `ForecastAgendaView` nicht berührt.
private struct ForecastStripHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
