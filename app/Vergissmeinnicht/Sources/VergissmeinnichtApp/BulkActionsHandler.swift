import Foundation

/// View-seitiger Dispatcher für die sechs Aktionen über eine Mehrfach-Selektion
/// (Erledigt, Löschen, Projekt zuweisen, Tag hinzufügen, Priorität, Fälligkeit).
///
/// Aus `RootView` extrahiert (#19), damit die View schlank bleibt. Bewusst dünn:
/// die Batch-Schleifen samt Teilfehler-Report („X von Y fehlgeschlagen") leben in
/// `AppContainer` neben `renameProject`/`renameTag` — dort, wo `lastError`
/// (`private(set)`) gesetzt werden darf (#5). `BulkActions` übernimmt nur das
/// `Task { }`-Wrapping und nimmt die Selektion als Parameter entgegen.
@MainActor
struct BulkActions {
    let container: AppContainer

    func markDone(_ uuids: Set<String>) {
        Task { await container.markDoneBatch(uuids: uuids) }
    }

    func delete(_ uuids: Set<String>) {
        Task { await container.deleteBatch(uuids: uuids) }
    }

    func assignProject(_ uuids: Set<String>, _ project: String?) {
        Task { await container.assignProjectBatch(uuids: uuids, project: project) }
    }

    func addTag(_ uuids: Set<String>, _ tag: String) {
        Task { await container.addTagBatch(uuids: uuids, tag: tag) }
    }

    func setPriority(_ uuids: Set<String>, _ priority: String?) {
        Task { await container.setPriorityBatch(uuids: uuids, priority: priority) }
    }

    func setDue(_ uuids: Set<String>, _ due: Int64?) {
        Task { await container.setDueBatch(uuids: uuids, due: due) }
    }
}
