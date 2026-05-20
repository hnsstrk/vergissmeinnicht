import Foundation

/// Persistente gespeicherte Suchanfrage: Name + Abfragestring.
///
/// Karpathy 2: minimales Modell — kein Icon, kein Farbfeld.
/// Persistenz via `@AppStorage` über statische Encode-/Decode-Helfer
/// (vermeidet retroaktive RawRepresentable-Conformance auf Array).
struct SavedSearch: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var query: String

    /// Dekodiert eine JSON-kodierte Liste aus einem `@AppStorage`-String.
    /// Gibt bei Fehler eine leere Liste zurück — kein Datenverlust.
    static func decodeAll(from raw: String) -> [SavedSearch] {
        guard let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([SavedSearch].self, from: data)
        else { return [] }
        return decoded
    }

    /// Kodiert eine Liste zu einem JSON-String für `@AppStorage`.
    static func encodeAll(_ searches: [SavedSearch]) -> String {
        guard let data = try? JSONEncoder().encode(searches),
              let string = String(data: data, encoding: .utf8)
        else { return "[]" }
        return string
    }
}
