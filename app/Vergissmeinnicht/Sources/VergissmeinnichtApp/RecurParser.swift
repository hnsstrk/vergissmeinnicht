import Foundation

/// Wandelt einen Recur-Property-String (Taskwarrior-Format) in eine `DateComponents`-
/// Verschiebung um, die der Generator-Light auf das alte Due-Datum anwendet.
///
/// Erkannte Formen:
/// - `daily`, `weekly`, `monthly`, `yearly`
/// - `Nd`, `Nw`, `Nm`, `Ny` (z.B. `3d`, `2w`)
///
/// Alles andere liefert `nil` — die App ruft dann keine Generator-Light-Logik auf.
enum RecurParser {
    static func components(from raw: String) -> DateComponents? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }

        switch trimmed {
        case "daily":   return DateComponents(day: 1)
        case "weekly":  return DateComponents(weekOfYear: 1)
        case "monthly": return DateComponents(month: 1)
        case "yearly":  return DateComponents(year: 1)
        default:
            break
        }

        guard trimmed.count >= 2 else { return nil }
        let unit = trimmed.last!
        let numPart = String(trimmed.dropLast())
        guard let n = Int(numPart), n > 0 else { return nil }
        switch unit {
        case "d": return DateComponents(day: n)
        case "w": return DateComponents(weekOfYear: n)
        case "m": return DateComponents(month: n)
        case "y": return DateComponents(year: n)
        default:  return nil
        }
    }

    /// Lokalisierter Anzeige-Text für die Picker-Optionen.
    static let standardOptions: [(value: String, labelKey: String)] = [
        ("",        "(keine)"),
        ("daily",   "Täglich"),
        ("weekly",  "Wöchentlich"),
        ("monthly", "Monatlich"),
        ("yearly",  "Jährlich"),
    ]
}
