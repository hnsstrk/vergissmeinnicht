import SwiftUI
import VergissmeinnichtKit

/// Editierbare Detail-Ansicht eines Tasks. Wird im eigenständigen `task-detail`-Fenster
/// gerendert; alle Mutationen laufen über `AppContainer`.
///
/// Felder:
/// - Description, Project, Tags, Due (Datum + Uhrzeit), Priority — editierbar
/// - Annotations — Liste mit Add/Remove, Anzeige in chronologischer Reihenfolge
/// - UUID, Working-Set-ID, Status, Angelegt — read-only Anzeige
///
/// "Speichern" schreibt Description/Project/Tags/Due atomar via `update_task_metadata`.
/// Priority wird separat via `set_priority` geschrieben (nicht Teil der bestehenden
/// atomar-Methode). Annotation-Add läuft sofort, kein separater Save.
struct DetailView: View {
    let task: TaskInfo?

    @Environment(AppContainer.self) private var container
    @Environment(\.undoManager) private var undoManager

    // Editierbarer Zustand
    @State private var description: String = ""
    @State private var project: String = ""
    @State private var tagsText: String = ""
    @State private var hasDue: Bool = false
    @State private var dueDate: Date = Date()
    @State private var priority: String = ""
    @State private var recur: String = ""
    @State private var hasScheduled: Bool = false
    @State private var scheduledDate: Date = Date()

    // Annotation-Sheet
    @State private var isAddingAnnotation = false
    // Abhängigkeits-Picker
    @State private var isPickingDependency = false

    // Lade-Marker, damit wir nicht jeden Re-Render den State überschreiben.
    @State private var loadedFromUuid: String?

    private static let priorityOptions: [(String, LocalizedStringKey)] = [
        ("",  "—"),
        ("H", "Hoch (H)"),
        ("M", "Mittel (M)"),
        ("L", "Niedrig (L)"),
    ]

    var body: some View {
        if let task {
            content(task: task)
                .onAppear { syncState(from: task) }
                .onChange(of: task.uuid) { _, _ in syncState(from: task) }
        } else {
            ContentUnavailableView(
                "Keine Auswahl",
                systemImage: "checkmark.circle",
                description: Text("Wähle einen Task aus der Liste.")
            )
        }
    }

    // MARK: - Layout

    @ViewBuilder
    private func content(task: TaskInfo) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header(task: task)
                Divider()
                editor(task: task)
                Divider()
                dependenciesSection(task: task)
                Divider()
                annotationsSection(task: task)
                Divider()
                readOnlyMeta(task: task)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if task.status == .pending {
                    Button {
                        Task { await container.markDoneWithRecurrence(uuid: task.uuid) }
                    } label: {
                        Label("Erledigt", systemImage: "checkmark.circle")
                    }
                } else {
                    Button {
                        Task { await container.reactivate(uuid: task.uuid) }
                    } label: {
                        Label("Reaktivieren", systemImage: "arrow.uturn.backward.circle")
                    }
                }
                Button {
                    Task { await save(task: task) }
                } label: {
                    Label("Speichern", systemImage: "square.and.arrow.down")
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!hasChanges(task: task))
            }
        }
        .sheet(isPresented: $isAddingAnnotation) {
            AnnotationEditor(task: task)
                .environment(container)
        }
    }

    @ViewBuilder
    private func header(task: TaskInfo) -> some View {
        HStack(alignment: .firstTextBaseline) {
            if let id = task.workingSetId {
                Text("#\(id)")
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            statusBadge(task.status)
            Spacer()
        }
    }

    @ViewBuilder
    private func editor(task _: TaskInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent("Titel") {
                TextField("Titel", text: $description)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("Projekt") {
                TextField("(keins)", text: $project)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("Tags") {
                TextField("kommagetrennt, z.B. arbeit, eilig", text: $tagsText)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("Fällig") {
                HStack {
                    Toggle("", isOn: $hasDue)
                        .labelsHidden()
                    DatePicker(
                        "",
                        selection: $dueDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                    .disabled(!hasDue)
                }
            }
            LabeledContent("Geplant ab") {
                HStack {
                    Toggle("", isOn: $hasScheduled)
                        .labelsHidden()
                    DatePicker(
                        "",
                        selection: $scheduledDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                    .disabled(!hasScheduled)
                }
            }
            LabeledContent("Priorität") {
                Picker("", selection: $priority) {
                    ForEach(Self.priorityOptions, id: \.0) { value, label in
                        Text(label).tag(value)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 200, alignment: .leading)
            }
            LabeledContent("Wiederholung") {
                Picker("", selection: $recur) {
                    ForEach(RecurParser.standardOptions, id: \.value) { opt in
                        Text(LocalizedStringKey(opt.labelKey)).tag(opt.value)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 200, alignment: .leading)
            }
        }
    }

    /// Abhängigkeiten-Editor (native Taskwarrior `depends`). Wie der Annotation-Editor
    /// schreibt jede Änderung sofort (kein Save) — Abhängigkeiten sind UUIDs, die der
    /// Nutzer nicht tippen kann, daher Add via Such-Picker / Remove via Button. Beide Aktionen
    /// sind per ⌘Z widerrufbar.
    @ViewBuilder
    private func dependenciesSection(task: TaskInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Hängt ab von")
                    .font(.title3.bold())
                Spacer()
                Button {
                    isPickingDependency = true
                } label: {
                    Label("Abhängigkeit hinzufügen", systemImage: "plus.circle")
                }
                .buttonStyle(.borderless)
                .popover(isPresented: $isPickingDependency, arrowEdge: .bottom) {
                    DependencyPickerPopover(task: task, tasks: container.tasks) { candidate in
                        isPickingDependency = false
                        Task {
                            await container.addDependencies(
                                uuids: [task.uuid], dependsOn: candidate.uuid, undoManager: undoManager
                            )
                        }
                    }
                }
            }

            if task.depends.isEmpty {
                Text("Hängt von keiner Aufgabe ab.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(task.depends, id: \.self) { depUuid in
                        dependencyRow(taskUuid: task.uuid, dependsOn: depUuid)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func dependencyRow(taskUuid: String, dependsOn depUuid: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            // Verwaiste/nicht (mehr) geladene UUIDs (laut taskchampion möglich) zeigen wir
            // als Rohstring statt zu crashen oder leer zu bleiben (Karpathy 3, robuster Fallback).
            if let dep = container.tasks.first(where: { $0.uuid == depUuid }) {
                if dep.status != .pending {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .help("Erledigt — blockiert nicht mehr")
                }
                Text(dep.workingSetId.map { "#\($0) \(dep.description)" } ?? dep.description)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(depUuid)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button {
                Task {
                    await container.removeDependencies(uuids: [taskUuid], dependsOn: depUuid, undoManager: undoManager)
                }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Abhängigkeit entfernen")
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func annotationsSection(task: TaskInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Notizen")
                    .font(.title3.bold())
                Spacer()
                Button {
                    isAddingAnnotation = true
                } label: {
                    Label("Notiz hinzufügen", systemImage: "plus.bubble")
                }
                .buttonStyle(.borderless)
            }

            if task.annotations.isEmpty {
                Text("Noch keine Notizen.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(sortedAnnotations(task.annotations), id: \.entry) { ann in
                        annotationRow(taskUuid: task.uuid, annotation: ann)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func annotationRow(taskUuid: String, annotation: AnnotationInfo) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(formatTimestamp(annotation.entry))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
            Text(markdown(annotation.description))
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                Task { await container.removeAnnotation(uuid: taskUuid, entry: annotation.entry) }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Annotation entfernen")
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func readOnlyMeta(task: TaskInfo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent("UUID") {
                Text(task.uuid)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if task.status == .pending {
                LabeledContent("Dringlichkeit") {
                    Text(Urgency.score(task, now: Date()).formatted(.number.precision(.fractionLength(1)).locale(AppLanguage.currentFormattingLocale)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help("Taskwarrior-Standardkoeffizienten")
                }
            }
            if let entry = task.entry {
                LabeledContent("Angelegt") {
                    Text(formatTimestamp(entry))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func statusBadge(_ status: TaskStatus) -> some View {
        let (label, color) = statusInfo(status)
        Text(label)
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    // MARK: - Save / Diff

    private func syncState(from task: TaskInfo) {
        guard loadedFromUuid != task.uuid else { return }
        description = task.description
        project = task.project ?? ""
        tagsText = task.tags.joined(separator: ", ")
        if let due = task.due {
            hasDue = true
            dueDate = Date(timeIntervalSince1970: TimeInterval(due))
        } else {
            hasDue = false
            dueDate = Date()
        }
        priority = task.priority ?? ""
        recur = task.recur ?? ""
        if let sched = task.scheduled {
            hasScheduled = true
            scheduledDate = Date(timeIntervalSince1970: TimeInterval(sched))
        } else {
            hasScheduled = false
            scheduledDate = Date()
        }
        loadedFromUuid = task.uuid
    }

    private func hasChanges(task: TaskInfo) -> Bool {
        let newDesc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let newProject = projectValue
        let newTags = parsedTags
        let newDue: Int64? = hasDue ? Int64(dueDate.timeIntervalSince1970) : nil
        let newPriority: String? = priority.isEmpty ? nil : priority
        let newRecur: String? = recur.isEmpty ? nil : recur
        let newScheduled: Int64? = hasScheduled ? Int64(scheduledDate.timeIntervalSince1970) : nil
        return newDesc != task.description
            || newProject != task.project
            || newTags != task.tags
            || newDue != task.due
            || newPriority != task.priority
            || newRecur != task.recur
            || newScheduled != task.scheduled
    }

    private func save(task: TaskInfo) async {
        let newDesc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newDesc.isEmpty else { return }
        let newDue: Int64? = hasDue ? Int64(dueDate.timeIntervalSince1970) : nil
        // Alle Teil-Writes verfolgen: `loadedFromUuid` darf nur dann zurückgesetzt
        // werden, wenn jede Mutation erfolgreich war. Sonst würde der nächste Render
        // die noch nicht persistierten Editor-Felder still aus der Quelle überschreiben
        // und der Nutzer verlöre seine Eingabe ohne sichtbaren Hinweis.
        var allSucceeded = await container.updateMetadata(
            uuid: task.uuid,
            description: newDesc,
            project: projectValue,
            tags: parsedTags,
            due: newDue
        )
        // Priority + Recur laufen separat (nicht Teil der Atomar-Methode).
        let newPriority: String? = priority.isEmpty ? nil : priority
        if newPriority != task.priority {
            allSucceeded = await container.setPriority(uuid: task.uuid, priority: newPriority) && allSucceeded
        }
        let newRecur: String? = recur.isEmpty ? nil : recur
        if newRecur != task.recur {
            allSucceeded = await container.setRecur(uuid: task.uuid, recur: newRecur) && allSucceeded
        }
        let newScheduled: Int64? = hasScheduled ? Int64(scheduledDate.timeIntervalSince1970) : nil
        if newScheduled != task.scheduled {
            allSucceeded = await container.setScheduled(uuid: task.uuid, scheduled: newScheduled) && allSucceeded
        }
        // Nur bei vollständigem Erfolg neu aus der Quelle laden; bei Teilfehler bleiben
        // die Editor-Felder erhalten, der Fehler erscheint im Banner (RootView).
        if allSucceeded {
            loadedFromUuid = nil
        }
    }

    private var projectValue: String? {
        let trimmed = project.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var parsedTags: [String] {
        tagsText
            .split(whereSeparator: { $0 == "," || $0 == " " })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Parsed Markdown mit Apple Foundation; bei Fehlern (z.B. wirklich purer Plaintext)
    /// fällt das Ergebnis auf den Rohstring zurück, damit die UI nicht leer bleibt.
    private func markdown(_ text: String) -> AttributedString {
        if let attr = try? AttributedString(markdown: text,
                                            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return attr
        }
        return AttributedString(text)
    }

    private func sortedAnnotations(_ annotations: [AnnotationInfo]) -> [AnnotationInfo] {
        annotations.sorted(by: { $0.entry < $1.entry })
    }

    private func formatTimestamp(_ unixSeconds: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(unixSeconds))
        return date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: AppLanguage.currentFormattingLocale))
    }

    private func statusInfo(_ status: TaskStatus) -> (LocalizedStringKey, Color) {
        switch status {
        case .pending:   return ("Ausstehend",    .blue)
        case .completed: return ("Erledigt",      .green)
        case .deleted:   return ("Gelöscht",      .red)
        case .recurring: return ("Wiederkehrend", .purple)
        }
    }
}

// MARK: - Abhängigkeits-Picker

/// Popover mit Suchfeld und höchstens 12 Treffern. ↑/↓ verschieben die Markierung,
/// ↩ oder Klick übernimmt den Treffer (der Aufrufer schließt das Popover), Esc schließt.
private struct DependencyPickerPopover: View {
    let task: TaskInfo
    let tasks: [TaskInfo]
    let onPick: (TaskInfo) -> Void

    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var searchFocused: Bool

    private var results: [TaskInfo] {
        DependencyCandidates.filter(query: query, task: task, tasks: tasks)
    }

    var body: some View {
        let results = results
        VStack(alignment: .leading, spacing: 8) {
            TextField("Aufgabe suchen …", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .onSubmit {
                    if results.indices.contains(highlighted) { onPick(results[highlighted]) }
                }
                .onKeyPress(.downArrow) {
                    highlighted = min(highlighted + 1, max(results.count - 1, 0))
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    highlighted = max(highlighted - 1, 0)
                    return .handled
                }
            if results.isEmpty {
                Text("Keine passende Aufgabe.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.element.uuid) { index, candidate in
                        row(candidate, isHighlighted: index == highlighted)
                            .onTapGesture { onPick(candidate) }
                    }
                }
            }
        }
        .padding(10)
        .frame(width: 340)
        .onAppear { searchFocused = true }
        .onChange(of: query) { _, _ in highlighted = 0 }
    }

    private func row(_ candidate: TaskInfo, isHighlighted: Bool) -> some View {
        HStack(spacing: 6) {
            Text(label(candidate))
                .lineLimit(1)
                .truncationMode(.tail)
            if let project = candidate.project {
                Text(project)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isHighlighted ? Color.accentColor.opacity(0.2) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
    }

    private func label(_ candidate: TaskInfo) -> String {
        if let id = candidate.workingSetId { return "#\(id) \(candidate.description)" }
        return candidate.description
    }
}
