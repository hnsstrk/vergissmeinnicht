import SwiftUI
import VergissmeinnichtKit

/// Kompakte Listen-Zeile: einzeilige Description.
///
/// Hover-/Selection-Highlight liefert die umgebende `List` automatisch — daher
/// hier bewusst keine eigene Background-Layer.
///
/// Welle 4 hängt das Context-Menu (`TaskRowActions`) für Done/Edit/Delete an.
/// Der Edit-Sheet wird per Row-State präsentiert, damit jede Zeile ihren
/// eigenen Sheet-Lifecycle hat.
struct TaskRowView: View {
    let task: TaskInfo

    @State private var isEditingDescription = false

    var body: some View {
        Text(task.description)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.vertical, 2)
            .contextMenu {
                TaskRowActions(task: task) {
                    isEditingDescription = true
                }
            }
            .sheet(isPresented: $isEditingDescription) {
                EditDescriptionSheet(task: task)
            }
    }
}
