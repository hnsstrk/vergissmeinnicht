import SwiftUI

/// Generisches Umbenennungs-Sheet für Tag- und Projekt-Bulk-Rename aus der Sidebar.
struct RenameSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: LocalizedStringKey
    let oldName: String
    var onCommit: (String) -> Void

    @State private var newName: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            TextField(oldName, text: $newName)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(commit)
            HStack {
                Spacer()
                Button("Abbrechen") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Speichern") { commit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            newName = oldName
            focused = true
        }
    }

    private func commit() {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onCommit(trimmed)
        dismiss()
    }
}
