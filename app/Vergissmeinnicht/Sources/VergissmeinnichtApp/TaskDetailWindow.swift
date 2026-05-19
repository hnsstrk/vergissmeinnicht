import SwiftUI
import VergissmeinnichtKit

/// Eigenständiges Fenster für die Detail-Ansicht eines Tasks.
///
/// Wird vom `RootView` per Doppelklick auf eine Task-Zeile geöffnet
/// (`openWindow(id: "task-detail", value: uuid)`). Bindet sich live an die
/// `pending`-Liste des `AppContainer` — wenn die Task verschwindet (mark done,
/// delete, sync-Auswirkung), zeigt das Fenster einen entsprechenden Hinweis.
struct TaskDetailWindow: View {
    @Environment(AppContainer.self) private var container
    let uuid: String?

    var body: some View {
        Group {
            if let task = currentTask {
                DetailView(task: task)
            } else {
                ContentUnavailableView(
                    "Task nicht gefunden",
                    systemImage: "questionmark.folder",
                    description: Text("Die Aufgabe wurde gelöscht oder ist nicht mehr Teil des Working Sets.")
                )
            }
        }
        .frame(minWidth: 380, idealWidth: 480, minHeight: 320, idealHeight: 480)
        .navigationTitle(currentTask?.description ?? String(localized: "Task-Detail"))
    }

    private var currentTask: TaskInfo? {
        guard let uuid else { return nil }
        return container.tasks.first { $0.uuid == uuid }
    }
}
