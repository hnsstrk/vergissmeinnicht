import Foundation
import VergissmeinnichtKit

/// Wert eines einzelnen Feldes über eine Mehrfachauswahl hinweg — die macOS-„Multiple
/// Values"-Konvention (Cocoa `NSMultipleValuesMarker`, vgl. Finder-Infofenster).
///
/// `uniform(nil)` bedeutet: alle selektierten Tasks stimmen überein und der Wert ist
/// leer (z.B. kein Projekt). `mixed` bedeutet: die Tasks haben unterschiedliche Werte.
enum BulkFieldValue<T: Equatable>: Equatable {
    case uniform(T?)
    case mixed

    /// Leitet den gemeinsamen Wert aus den einzelnen Task-Werten ab. `values` ist im
    /// Bulk-Editor nie leer (Mehrfachauswahl setzt mind. zwei Tasks voraus); ein leeres
    /// Array liefert `.uniform(nil)` als harmlosen Default statt zu crashen.
    static func derive(_ values: [T?]) -> BulkFieldValue<T> {
        guard let first = values.first else { return .uniform(nil) }
        return values.dropFirst().allSatisfy { $0 == first } ? .uniform(first) : .mixed
    }
}

/// Pro-Feld-Ableitung aus der aktuellen Mehrfachauswahl für den Bulk-Editor in
/// `TaskInspectorView` (#33). Reine, testbare Datenableitung — keine FFI-Zugriffe.
struct BulkEditState: Equatable {
    let project: BulkFieldValue<String>
    let tagSet: BulkFieldValue<Set<String>>
    let due: BulkFieldValue<Int64>
    let scheduled: BulkFieldValue<Int64>
    let priority: BulkFieldValue<String>

    init(tasks: [TaskInfo]) {
        project = .derive(tasks.map { $0.project })
        // Tags haben keinen Optional-Charakter (leere Menge statt nil), werden hier aber
        // in Optional gehoben, damit `derive` dieselbe Vergleichslogik nutzen kann.
        tagSet = .derive(tasks.map { Optional(Set($0.tags)) })
        due = .derive(tasks.map { $0.due })
        scheduled = .derive(tasks.map { $0.scheduled })
        priority = .derive(tasks.map { $0.priority })
    }
}
