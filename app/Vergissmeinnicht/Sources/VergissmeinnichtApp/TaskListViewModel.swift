import Foundation
import VergissmeinnichtKit

/// UI-State für die Task-Liste: Such-Query und aktuelle Auswahl.
///
/// Die `pending`-Liste selbst lebt im `AppContainer` (Single Source of Truth);
/// dieses ViewModel hält bewusst nur abgeleiteten UI-State und Filter-/Sort-Logik.
/// Damit bleibt `AppContainer` der einzige Owner der FFI-Daten — siehe Karpathy 2 (Simplicity).
///
/// - Sortierung: Phase-2-FFI exportiert nur `uuid` + `description`. Daher alphabetisch
///   nach Description als Platzhalter. **TODO**: auf Urgency umstellen, sobald die FFI
///   `urgency`/`due`/`project` exportiert (Welle ≥ 4 / FFI-Erweiterung).
/// - Filter: Volltext-Substring in Description. **TODO**: Project-/Tag-Filter ergänzen,
///   sobald die FFI diese Felder liefert.
@MainActor
@Observable
final class TaskListViewModel {
    var searchQuery: String = ""
    var selectedUuid: String?

    /// Filtert nach `searchQuery` (Description-Substring) und sortiert alphabetisch.
    func visibleTasks(from pending: [TaskInfo]) -> [TaskInfo] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered: [TaskInfo]
        if query.isEmpty {
            filtered = pending
        } else {
            filtered = pending.filter {
                $0.description.localizedCaseInsensitiveContains(query)
            }
        }
        return filtered.sorted {
            $0.description.localizedCaseInsensitiveCompare($1.description) == .orderedAscending
        }
    }
}
