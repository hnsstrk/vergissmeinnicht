import Foundation

/// Wandelt einen `due:`-Token aus dem QuickCaptureParser in einen Unix-Sekunden-Timestamp.
///
/// Unterstützte Formen (klein-/großschreibungsunabhängig):
/// - `today`, `tomorrow`
/// - `+Nd` / `+Nw` (relativ: Tage / Wochen ab jetzt)
/// - `yyyy-MM-dd` (ISO-Datum)
///
/// Alle anderen Eingaben liefern `nil` — die Aufrufseite persistiert in dem Fall keine
/// Fälligkeit. Der Stichtag wird auf das **Ende des Zieltages** in der lokalen
/// Zeitzone gesetzt, damit "heute fällig" nicht direkt nach Mitternacht in
/// "überfällig" umkippt.
enum DueDateParser {
    static func parse(_ value: String, now: Date = Date()) -> Int64? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.lowercased()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current

        if normalized == "today" {
            return endOfDay(now, calendar: calendar)
        }
        if normalized == "tomorrow" {
            guard let t = calendar.date(byAdding: .day, value: 1, to: now) else { return nil }
            return endOfDay(t, calendar: calendar)
        }
        if normalized.hasPrefix("+"), normalized.count >= 3 {
            let unitChar = normalized.last!
            let numPart = String(normalized.dropFirst().dropLast())
            if let n = Int(numPart) {
                let component: Calendar.Component?
                switch unitChar {
                case "d": component = .day
                case "w": component = .weekOfYear
                default:  component = nil
                }
                if let c = component, let t = calendar.date(byAdding: c, value: n, to: now) {
                    return endOfDay(t, calendar: calendar)
                }
            }
        }

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = calendar.timeZone
        if let d = fmt.date(from: trimmed) {
            return endOfDay(d, calendar: calendar)
        }
        return nil
    }

    private static func endOfDay(_ date: Date, calendar: Calendar) -> Int64 {
        let start = calendar.startOfDay(for: date)
        // start of next day - 1 Sekunde = letzte Sekunde des Tages
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: start) else {
            return Int64(date.timeIntervalSince1970)
        }
        return Int64(nextDay.addingTimeInterval(-1).timeIntervalSince1970)
    }
}
