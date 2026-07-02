import SwiftUI
import VergissmeinnichtKit

/// Inhalt der Detailspalte rechts der Hauptliste (Mail-Stil-Lesebereich, #33).
///
/// Rendert abhängig vom Selektionszustand der Liste:
/// - keine Auswahl → Platzhalter mit Hinweis
/// - genau eine Aufgabe → die bekannte `DetailView` inline (gleicher Editor wie
///   im eigenständigen `task-detail`-Fenster; Doppelklick öffnet weiterhin das Fenster)
/// - Mehrfachauswahl → Bulk-Editor (macOS-„Multiple Values"-Konvention) + Liste + Bulk-Aktionen
///
/// Verschwindet eine selektierte Aufgabe aus dem Working Set (erledigt, gelöscht,
/// Sync), räumt `RootView` die Selektion bereits auf (`onChange(of: container.tasks)`)
/// — die Spalte fällt dann automatisch auf den Platzhalter zurück. Der
/// „nicht gefunden"-Zweig deckt nur das transiente Fenster dazwischen ab.
struct TaskInspectorView: View {
    @Environment(AppContainer.self) private var container
    let selectedUuids: Set<String>
    let onMarkDoneSelection: () -> Void
    let onRequestDelete: (Set<String>) -> Void
    let onAssignProject: (Set<String>, String?) -> Void
    let onReplaceTags: (Set<String>, [String]) -> Void
    let onSetDue: (Set<String>, Int64?) -> Void
    let onSetScheduled: (Set<String>, Int64?) -> Void
    let onSetPriority: (Set<String>, String?) -> Void

    // MARK: - Bulk-Editor-Zustand
    //
    // Wird nur (neu) aus den Tasks geladen, wenn sich die Selektion (Set der UUIDs)
    // ändert — analog `DetailView.loadedFromUuid`. Nach einem Commit ändern sich
    // `container.tasks`, das darf laufende Eingaben in anderen Feldern nicht
    // überschreiben (kein `onChange(of: container.tasks)` hier).
    @State private var bulkLoadedSelection: Set<String>?

    @State private var bulkProjectText: String = ""
    @State private var bulkProjectDirty = false
    @State private var bulkProjectPrompt: LocalizedStringKey = "(keins)"
    @FocusState private var bulkProjectFocused: Bool

    @State private var bulkTagsText: String = ""
    @State private var bulkTagsDirty = false
    @State private var bulkTagsPrompt: LocalizedStringKey = "kommagetrennt, z.B. arbeit, eilig"
    @FocusState private var bulkTagsFocused: Bool

    @State private var bulkDue: BulkDateField = .mixed
    @State private var bulkScheduled: BulkDateField = .mixed

    @State private var bulkPriority: String = ""
    @State private var bulkPriorityMixed = false

    private static let mixedPrioritySentinel = "__mixed__"
    private static let priorityOptions: [(String, LocalizedStringKey)] = [
        ("",  "—"),
        ("H", "Hoch (H)"),
        ("M", "Mittel (M)"),
        ("L", "Niedrig (L)"),
    ]

    /// UI-Zustand des Bulk-Editors für ein Datumsfeld (Fällig/Geplant ab). SwiftUIs
    /// `Toggle` kennt keinen Mixed-Zustand — deshalb eigener Fall statt Bool+Date.
    private enum BulkDateField: Equatable {
        case mixed
        case value(enabled: Bool, date: Date)
    }

    var body: some View {
        if selectedUuids.isEmpty {
            ContentUnavailableView(
                "Keine Auswahl",
                systemImage: "sidebar.trailing",
                description: Text("Wähle eine Aufgabe aus der Liste, um ihre Details hier zu sehen.")
            )
        } else if selectedUuids.count == 1 {
            if let task = selectedTasks.first {
                DetailView(task: task)
            } else {
                ContentUnavailableView(
                    "Task nicht gefunden",
                    systemImage: "questionmark.folder",
                    description: Text("Die Aufgabe wurde gelöscht oder ist nicht mehr Teil des Working Sets.")
                )
            }
        } else {
            multiSelectionSummary
        }
    }

    /// Aufgaben der Selektion in Listen-Reihenfolge (Reihenfolge von
    /// `container.tasks`, nicht die zufällige Set-Reihenfolge).
    private var selectedTasks: [TaskInfo] {
        container.tasks.filter { selectedUuids.contains($0.uuid) }
    }

    // MARK: - Mehrfachauswahl

    /// Kopf → Bulk-Editor-Karte → scrollbare Liste ALLER selektierten Aufgaben (beides
    /// in derselben ScrollView) → fixer Aktions-Footer. Anders als die frühere gekappte
    /// Vorschau (6 Titel, `lineLimit(1)`) soll der User die vollständige Auswahl lesen
    /// können, daher kein Kappen und kein Zeilenlimit auf dem Titel.
    @ViewBuilder
    private var multiSelectionSummary: some View {
        let tasks = selectedTasks
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text("\(tasks.count) Aufgaben ausgewählt")
                    .font(.headline)
            }
            .padding(.top, 20)
            .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    bulkEditCard
                    Text("Änderungen gelten für alle \(tasks.count) ausgewählten Aufgaben.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    LazyVStack(spacing: 8) {
                        ForEach(tasks, id: \.uuid) { task in
                            multiSelectionRow(task)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .onAppear { loadBulkEditState(from: tasks) }
            .onChange(of: selectedUuids) { _, _ in loadBulkEditState(from: tasks) }

            Divider()

            HStack(spacing: 12) {
                Button {
                    onMarkDoneSelection()
                } label: {
                    Label("Erledigt", systemImage: "checkmark.circle")
                }
                Button(role: .destructive) {
                    onRequestDelete(selectedUuids)
                } label: {
                    Label("Löschen", systemImage: "trash")
                }
                Spacer()
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Bulk-Editor-Karte: Projekt, Tags, Fällig, Geplant ab, Priorität — analog der
    /// Sektions-Optik in `DetailView` (Hintergrundkarte statt Divider). Titel bleibt
    /// bewusst außen vor: der Task-Titel ist pro Aufgabe individuell und nicht Teil der
    /// Massenbearbeitung. Wiederholung/Status/Notizen ebenfalls bewusst nicht enthalten
    /// — `recur` hängt an `due` und ist in Masse fehleranfällig (Karpathy 2).
    @ViewBuilder
    private var bulkEditCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent("Projekt") {
                TextField("", text: Binding(
                    get: { bulkProjectText },
                    set: { bulkProjectText = $0; bulkProjectDirty = true }
                ), prompt: Text(bulkProjectPrompt))
                    .textFieldStyle(.roundedBorder)
                    .focused($bulkProjectFocused)
                    .onSubmit { commitBulkProject() }
                    .onChange(of: bulkProjectFocused) { wasFocused, isFocused in
                        if wasFocused, !isFocused { commitBulkProject() }
                    }
            }
            LabeledContent("Tags") {
                TextField("", text: Binding(
                    get: { bulkTagsText },
                    set: { bulkTagsText = $0; bulkTagsDirty = true }
                ), prompt: Text(bulkTagsPrompt))
                    .textFieldStyle(.roundedBorder)
                    .focused($bulkTagsFocused)
                    .onSubmit { commitBulkTags() }
                    .onChange(of: bulkTagsFocused) { wasFocused, isFocused in
                        if wasFocused, !isFocused { commitBulkTags() }
                    }
            }
            bulkDateRow("Fällig", field: $bulkDue) { onSetDue(selectedUuids, $0) }
            bulkDateRow("Geplant ab", field: $bulkScheduled) { onSetScheduled(selectedUuids, $0) }
            LabeledContent("Priorität") {
                Picker("", selection: Binding(
                    get: { bulkPriority },
                    set: { newValue in
                        guard newValue != Self.mixedPrioritySentinel else { return }
                        bulkPriority = newValue
                        bulkPriorityMixed = false
                        onSetPriority(selectedUuids, newValue.isEmpty ? nil : newValue)
                    }
                )) {
                    if bulkPriorityMixed {
                        Text("Mehrere Werte")
                            .foregroundStyle(.secondary)
                            .tag(Self.mixedPrioritySentinel)
                    }
                    ForEach(Self.priorityOptions, id: \.0) { value, label in
                        Text(label).tag(value)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 200, alignment: .leading)
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    /// Zeile für ein Datumsfeld (Fällig/Geplant ab): uniform → Toggle + DatePicker,
    /// jede Änderung committet sofort. Gemischt → Menu mit „Für alle setzen …" (seeded
    /// mit jetzt) und „Bei allen entfernen", da `Toggle` keinen Mixed-Zustand kennt.
    @ViewBuilder
    private func bulkDateRow(
        _ label: LocalizedStringKey,
        field: Binding<BulkDateField>,
        onCommit: @escaping (Int64?) -> Void
    ) -> some View {
        LabeledContent(label) {
            switch field.wrappedValue {
            case .mixed:
                Menu {
                    Button("Für alle setzen …") {
                        let now = Date()
                        field.wrappedValue = .value(enabled: true, date: now)
                        onCommit(Int64(now.timeIntervalSince1970))
                    }
                    Button("Bei allen entfernen") {
                        field.wrappedValue = .value(enabled: false, date: Date())
                        onCommit(nil)
                    }
                } label: {
                    Text("Mehrere Werte")
                        .foregroundStyle(.secondary)
                }
            case .value(let enabled, let date):
                HStack {
                    Toggle("", isOn: Binding(
                        get: { enabled },
                        set: { newValue in
                            let newDate = newValue ? Date() : date
                            field.wrappedValue = .value(enabled: newValue, date: newDate)
                            onCommit(newValue ? Int64(newDate.timeIntervalSince1970) : nil)
                        }
                    ))
                    .labelsHidden()
                    DatePicker(
                        "",
                        selection: Binding(
                            get: { date },
                            set: { newDate in
                                field.wrappedValue = .value(enabled: enabled, date: newDate)
                                if enabled { onCommit(Int64(newDate.timeIntervalSince1970)) }
                            }
                        ),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                    .disabled(!enabled)
                }
            }
        }
    }

    /// Einzelne Zeile der Mehrfachauswahl-Liste: Working-Set-ID, voll umbrechender
    /// Titel, Meta-Zeile mit Projekt/Fälligkeit (überfällig rot). Hintergrund-Karte
    /// statt Divider — analog der Sektionen in `DetailView`.
    @ViewBuilder
    private func multiSelectionRow(_ task: TaskInfo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let workingSetId = task.workingSetId {
                    Text("#\(workingSetId)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(task.description)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if task.project != nil || task.due != nil {
                HStack(spacing: 8) {
                    if let project = task.project {
                        Text(project)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let due = task.due {
                        Text(formatDue(due))
                            .font(.caption)
                            .foregroundStyle(isOverdue(due) ? .red : .secondary)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Bulk-Editor: Laden/Commit

    /// Lädt den Bulk-Editor-Zustand aus der aktuellen Selektion — nur bei tatsächlich
    /// geänderter Selektion (siehe Kommentar bei `bulkLoadedSelection`).
    private func loadBulkEditState(from tasks: [TaskInfo]) {
        guard bulkLoadedSelection != selectedUuids else { return }
        let state = BulkEditState(tasks: tasks)

        switch state.project {
        case .uniform(let value):
            bulkProjectText = value ?? ""
            bulkProjectPrompt = value == nil ? "(keins)" : ""
        case .mixed:
            bulkProjectText = ""
            bulkProjectPrompt = "Mehrere Werte"
        }
        bulkProjectDirty = false

        switch state.tagSet {
        case .uniform(let value):
            bulkTagsText = (value ?? []).sorted().joined(separator: ", ")
            bulkTagsPrompt = "kommagetrennt, z.B. arbeit, eilig"
        case .mixed:
            bulkTagsText = ""
            bulkTagsPrompt = "Mehrere Werte"
        }
        bulkTagsDirty = false

        bulkDue = bulkDateField(from: state.due)
        bulkScheduled = bulkDateField(from: state.scheduled)

        switch state.priority {
        case .uniform(let value):
            bulkPriority = value ?? ""
            bulkPriorityMixed = false
        case .mixed:
            bulkPriority = Self.mixedPrioritySentinel
            bulkPriorityMixed = true
        }

        bulkLoadedSelection = selectedUuids
    }

    private func bulkDateField(from value: BulkFieldValue<Int64>) -> BulkDateField {
        switch value {
        case .mixed:
            return .mixed
        case .uniform(let timestamp):
            guard let timestamp else { return .value(enabled: false, date: Date()) }
            return .value(enabled: true, date: Date(timeIntervalSince1970: TimeInterval(timestamp)))
        }
    }

    /// Committet das Projekt-Feld nur, wenn der User tatsächlich editiert hat — sonst
    /// würde bloßes Durch-Tabben bei gemischtem Zustand das Projekt bei allen Tasks
    /// entfernen (leerer Text ist sonst nicht von „nicht editiert" zu unterscheiden).
    private func commitBulkProject() {
        guard bulkProjectDirty else { return }
        let trimmed = bulkProjectText.trimmingCharacters(in: .whitespacesAndNewlines)
        onAssignProject(selectedUuids, trimmed.isEmpty ? nil : trimmed)
        bulkProjectDirty = false
    }

    private func commitBulkTags() {
        guard bulkTagsDirty else { return }
        onReplaceTags(selectedUuids, parsedBulkTags)
        bulkTagsDirty = false
    }

    private var parsedBulkTags: [String] {
        bulkTagsText
            .split(whereSeparator: { $0 == "," || $0 == " " })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func formatDue(_ unixSeconds: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(unixSeconds))
        return date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: AppLanguage.currentFormattingLocale))
    }

    private func isOverdue(_ unixSeconds: Int64) -> Bool {
        Date(timeIntervalSince1970: TimeInterval(unixSeconds)) < .now
    }
}
