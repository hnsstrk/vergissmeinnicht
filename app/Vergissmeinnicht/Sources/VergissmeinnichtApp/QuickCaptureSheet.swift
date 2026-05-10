import SwiftUI

/// QuickCapture-Eingabe für die `MenuBarExtra`.
///
/// Ein `TextField` mit Auto-Focus, parsed Taskwarrior-Syntax (siehe
/// `QuickCaptureParser`) und persistiert in Welle 4 ausschließlich die
/// `description`. Erkannte Tags/Project/Due/Priority werden als Vorschau
/// angezeigt, aber **nicht** an die FFI weitergegeben — die FFI exportiert
/// die Felder noch nicht.
///
/// Nach erfolgreichem Add: `input` wird geleert und `dismiss()` aufgerufen.
/// Im MenuBarExtra-Popover-Kontext ist `dismiss()` ein No-Op (Apple-Bug);
/// dort bleibt das Sheet offen für Folge-Eingaben. Im modalen `.sheet`-
/// Kontext (Hauptfenster, Toolbar-Button "+") schließt sich das Sheet.
struct QuickCaptureSheet: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss
    @State private var input: String = ""
    @FocusState private var focused: Bool

    private var preview: QuickCapturePreview {
        QuickCaptureParser.parse(input)
    }

    private var trimmedDescription: String {
        preview.description.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Neue Task")
                .font(.headline)

            TextField(
                "Description +tag project:foo due:tomorrow priority:H",
                text: $input
            )
            .textFieldStyle(.roundedBorder)
            .focused($focused)
            .onSubmit(save)

            if preview.hasMetadata {
                metadataPreview
            }

            Text("Hinweis: In dieser Welle wird nur die Description gespeichert. Tags, Project, Due und Priority werden geparst, aber noch nicht persistiert (FFI exportiert die Felder noch nicht).\n\nUnterstützte Syntax: `+tag`, `project:`, `due:`, `priority:`. `#tag` oder `!1` werden NICHT erkannt. Leerzeichen in der Description mit `\\ ` escapen (z. B. `meeting\\ notes +work`).")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Hinzufügen") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedDescription.isEmpty)
            }

            if let error = container.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .padding(16)
        .frame(width: 360)
        .task {
            // .task läuft nach onAppear und macht das Auto-Focus in der
            // MenuBarExtra-Popover-Window zuverlässiger als .onAppear.
            focused = true
        }
    }

    @ViewBuilder
    private var metadataPreview: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Erkannt:")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            if !preview.tags.isEmpty {
                Text("Tags: " + preview.tags.map { "+\($0)" }.joined(separator: " "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let project = preview.project {
                Text("Project: \(project)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let due = preview.due {
                Text("Due: \(due)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let priority = preview.priority {
                Text("Priority: \(priority)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        // TODO(FFI-Erweiterung): sobald addTask Tags/Project/Due/Priority akzeptiert,
        // hier auch persistieren statt nur in der Vorschau anzuzeigen.
    }

    private func save() {
        let description = trimmedDescription
        guard !description.isEmpty else { return }
        Task {
            // Eingabe nur leeren, wenn die Mutation tatsächlich durchlief —
            // sonst geht der Inhalt bei einem FFI-Fehler verloren.
            if await container.addTask(description: description) {
                input = ""
                focused = true
                dismiss()
            }
        }
    }
}
