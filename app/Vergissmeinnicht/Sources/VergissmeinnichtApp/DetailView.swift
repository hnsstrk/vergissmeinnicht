import SwiftUI
import VergissmeinnichtKit

/// Detail-Pane des `NavigationSplitView`.
///
/// Phase-2-FFI exportiert nur `uuid` + `description` — entsprechend zeigen wir nur
/// diese beiden Felder. Weitere Felder (Urgency, Due, Project, Tags, Annotations)
/// folgen, sobald die FFI sie liefert.
///
/// Welle 4 ergänzt den „+ Annotation hinzufügen"-Button. Existierende Annotations
/// können noch nicht angezeigt werden — die FFI liefert keine Annotation-Liste.
struct DetailView: View {
    let task: TaskInfo?

    @State private var isAddingAnnotation = false

    var body: some View {
        if let task {
            VStack(alignment: .leading, spacing: 16) {
                Text(task.description)
                    .font(.title2)
                    .textSelection(.enabled)

                LabeledContent("UUID") {
                    Text(task.uuid)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Button {
                    isAddingAnnotation = true
                } label: {
                    Label("Annotation hinzufügen", systemImage: "plus.bubble")
                }
                .buttonStyle(.borderless)

                Spacer()
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .sheet(isPresented: $isAddingAnnotation) {
                AnnotationEditor(task: task)
            }
        } else {
            ContentUnavailableView(
                "Keine Auswahl",
                systemImage: "checkmark.circle",
                description: Text("Wähle einen Task aus der Liste.")
            )
        }
    }
}
