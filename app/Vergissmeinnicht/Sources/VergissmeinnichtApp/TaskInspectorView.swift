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

    /// Kopf + scrollbare Liste ALLER selektierten Aufgaben + fixer Aktions-Footer.
    /// Anders als die frühere gekappte Vorschau (6 Titel, `lineLimit(1)`) soll der
    /// User die vollständige Auswahl lesen können, daher kein Kappen und kein
    /// Zeilenlimit auf dem Titel.
    @ViewBuilder
    private var multiSelectionSummary: some View {
        let tasks = selectedTasks
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text("\(tasks.count) Aufgaben ausgewählt")
                    .font(.headline)
            }
            .padding(.top, 20)
            .padding(.bottom, 12)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(tasks, id: \.uuid) { task in
                        multiSelectionRow(task)
                    }
                }
                .padding(.horizontal, 16)
            }

            Divider()

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
                Spacer()
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Einzelne Zeile der Mehrfachauswahl-Liste: Working-Set-ID, voll umbrechender
    /// Titel, Meta-Zeile mit Projekt/Fälligkeit (überfällig rot). Hintergrund-Karte
    /// statt Divider — analog der Sektionen in `DetailView`.
    @ViewBuilder
    private func multiSelectionRow(_ task: TaskInfo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let workingSetId = task.workingSetId {
                    Text("#\(workingSetId)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(task.description)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if task.project != nil || task.due != nil {
                HStack(spacing: 8) {
                    if let project = task.project {
                        Text(project)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let due = task.due {
                        Text(formatDue(due))
                            .font(.caption)
                            .foregroundStyle(isOverdue(due) ? .red : .secondary)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    private func formatDue(_ unixSeconds: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(unixSeconds))
        return date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: AppLanguage.currentFormattingLocale))
    }

    private func isOverdue(_ unixSeconds: Int64) -> Bool {
        Date(timeIntervalSince1970: TimeInterval(unixSeconds)) < .now
    }
}
