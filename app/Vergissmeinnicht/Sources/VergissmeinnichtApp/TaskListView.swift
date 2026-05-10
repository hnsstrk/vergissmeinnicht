import SwiftUI
import VergissmeinnichtKit

/// Sidebar-Liste der pending Tasks.
///
/// Die Daten sind bereits gefiltert und sortiert (siehe `TaskListViewModel.visibleTasks`).
/// Selection-Binding zeigt auf die aktuell selektierte UUID im ViewModel.
struct TaskListView: View {
    let tasks: [TaskInfo]
    @Binding var selectedUuid: String?

    var body: some View {
        List(tasks, id: \.uuid, selection: $selectedUuid) { task in
            TaskRowView(task: task)
        }
        .overlay {
            if tasks.isEmpty {
                ContentUnavailableView(
                    "Keine Tasks",
                    systemImage: "tray",
                    description: Text("Working Set ist leer oder kein Treffer für die Suche.")
                )
            }
        }
    }
}
