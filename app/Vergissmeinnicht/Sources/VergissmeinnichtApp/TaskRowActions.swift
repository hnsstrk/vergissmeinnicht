import SwiftUI
import VergissmeinnichtKit

/// Inhalt des Context-Menus auf `TaskRowView`.
///
/// Liefert die drei Mutations-Aktionen Done / Description bearbeiten / Löschen.
/// Done und Löschen rufen direkt den `AppContainer` an (der `pending` nach jeder
/// Mutation refresht). Description-Edit delegiert an die `onEdit`-Closure, weil
/// das den präsentierenden Sheet im umgebenden View-State öffnet.
///
/// Karpathy 2: kein Confirm-Dialog für Delete — kann später per `.alert`
/// nachgerüstet werden, wenn der Bedarf entsteht.
struct TaskRowActions: View {
    let task: TaskInfo
    let onEdit: () -> Void

    @Environment(AppContainer.self) private var container

    var body: some View {
        Button {
            Task { await container.markDone(uuid: task.uuid) }
        } label: {
            Label("Done", systemImage: "checkmark")
        }

        Button {
            onEdit()
        } label: {
            Label("Description bearbeiten…", systemImage: "pencil")
        }

        Divider()

        Button(role: .destructive) {
            Task { await container.deleteTask(uuid: task.uuid) }
        } label: {
            Label("Löschen", systemImage: "trash")
        }
    }
}
