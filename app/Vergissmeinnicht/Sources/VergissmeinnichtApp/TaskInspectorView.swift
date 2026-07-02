import SwiftUI
import VergissmeinnichtKit

/// Inhalt der Detailspalte rechts der Hauptliste (Mail-Stil-Lesebereich, #33).
///
/// Rendert abhängig vom Selektionszustand der Liste:
/// - keine Auswahl → Platzhalter mit Hinweis
/// - genau eine Aufgabe → die bekannte `DetailView` inline (gleicher Editor wie
///   im eigenständigen `task-detail`-Fenster; Doppelklick öffnet weiterhin das Fenster)
/// - Mehrfachauswahl → Zusammenfassung mit Titel-Vorschau und Bulk-Aktionen
///
/// Verschwindet eine selektierte Aufgabe aus dem Working Set (erledigt, gelöscht,
/// Sync), räumt `RootView` die Selektion bereits auf (`onChange(of: container.tasks)`)
/// — die Spalte fällt dann automatisch auf den Platzhalter zurück. Der
/// „nicht gefunden"-Zweig deckt nur das transiente Fenster dazwischen ab.
struct TaskInspectorView: View {
    @Environment(AppContainer.self) private var container
    let selectedUuids: Set<String>
    let onMarkDoneSelection: () -> Void
    let onRequestDelete: (Set<String>) -> Void

    /// Titel-Vorschau der Mehrfachauswahl: mehr Zeilen helfen nicht beim
    /// Wiedererkennen, sie verschieben nur die Aktionen aus dem Blickfeld.
    private static let maxPreviewTitles = 6

    var body: some View {
        if selectedUuids.isEmpty {
            ContentUnavailableView(
                "Keine Auswahl",
                systemImage: "sidebar.trailing",
                description: Text("Wähle eine Aufgabe aus der Liste, um ihre Details hier zu sehen.")
            )
        } else if selectedUuids.count == 1 {
            if let task = selectedTasks.first {
                DetailView(task: task)
            } else {
                ContentUnavailableView(
                    "Task nicht gefunden",
                    systemImage: "questionmark.folder",
                    description: Text("Die Aufgabe wurde gelöscht oder ist nicht mehr Teil des Working Sets.")
                )
            }
        } else {
            multiSelectionSummary
        }
    }

    /// Aufgaben der Selektion in Listen-Reihenfolge (Reihenfolge von
    /// `container.tasks`, nicht die zufällige Set-Reihenfolge).
    private var selectedTasks: [TaskInfo] {
        container.tasks.filter { selectedUuids.contains($0.uuid) }
    }

    // MARK: - Mehrfachauswahl

    @ViewBuilder
    private var multiSelectionSummary: some View {
        let tasks = selectedTasks
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("\(tasks.count) Aufgaben ausgewählt")
                .font(.title3.bold())

            VStack(alignment: .leading, spacing: 4) {
                ForEach(tasks.prefix(Self.maxPreviewTitles), id: \.uuid) { task in
                    Text(task.description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if tasks.count > Self.maxPreviewTitles {
                    Text("+ \(tasks.count - Self.maxPreviewTitles) weitere")
                        .font(.callout.italic())
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: 320, alignment: .leading)

            HStack(spacing: 12) {
                Button {
                    onMarkDoneSelection()
                } label: {
                    Label("Erledigt", systemImage: "checkmark.circle")
                }
                Button(role: .destructive) {
                    onRequestDelete(selectedUuids)
                } label: {
                    Label("Löschen", systemImage: "trash")
                }
            }
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
