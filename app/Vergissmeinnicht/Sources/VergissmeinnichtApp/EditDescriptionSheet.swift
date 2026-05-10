import SwiftUI
import VergissmeinnichtKit

/// Modaler Sheet zum Bearbeiten der Description eines Tasks.
///
/// Wird aus dem Context-Menu der `TaskRowView` aufgerufen. Speichert über
/// `AppContainer.modifyDescription(uuid:newDescription:)`, das anschließend
/// `pending` neu lädt.
struct EditDescriptionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppContainer.self) private var container

    let task: TaskInfo

    @State private var newDescription: String = ""
    @FocusState private var focused: Bool

    private var trimmed: String {
        newDescription.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmed.isEmpty && trimmed != task.description
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Description bearbeiten")
                .font(.headline)

            TextField("Description", text: $newDescription)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit { if canSave { save() } }

            HStack {
                Spacer()
                Button("Abbrechen") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Speichern") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            newDescription = task.description
            focused = true
        }
    }

    private func save() {
        guard canSave else { return }
        let value = trimmed
        Task {
            // Sheet bleibt bei FFI-Fehler offen, damit der User den Wert nicht
            // verliert. Fehlertext kommt über `AppContainer.lastError` an die
            // RootView (Overlay).
            if await container.modifyDescription(uuid: task.uuid, newDescription: value) {
                dismiss()
            }
        }
    }
}
