import SwiftUI
import VergissmeinnichtKit

/// Modaler Sheet zum Hinzufügen einer Annotation an einen Task.
///
/// Wird aus dem `DetailView` über den „+ Annotation hinzufügen"-Button geöffnet.
/// Speichert über `AppContainer.addAnnotation(uuid:annotation:)`, das anschließend
/// `pending` neu lädt.
///
/// Phase-2-FFI exportiert noch keine Annotation-Liste in `TaskInfo` — daher zeigt
/// der DetailView vorerst nur die Möglichkeit, neue Annotations hinzuzufügen,
/// nicht aber die existierenden anzuzeigen.
struct AnnotationEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppContainer.self) private var container

    let task: TaskInfo

    @State private var annotationText: String = ""
    @FocusState private var focused: Bool

    private var trimmed: String {
        annotationText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Annotation hinzufügen")
                .font(.headline)

            Text(task.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            TextEditor(text: $annotationText)
                .font(.body)
                .focused($focused)
                .frame(minHeight: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.secondary.opacity(0.3), lineWidth: 1)
                )

            HStack {
                Spacer()
                Button("Abbrechen") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Speichern") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmed.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480, height: 260)
        .onAppear { focused = true }
    }

    private func save() {
        let value = trimmed
        guard !value.isEmpty else { return }
        Task {
            // Sheet bleibt bei FFI-Fehler offen, damit der getippte Annotation-
            // Text nicht verloren geht. Fehlertext kommt über
            // `AppContainer.lastError` an die RootView (Overlay).
            if await container.addAnnotation(uuid: task.uuid, annotation: value) {
                dismiss()
            }
        }
    }
}
