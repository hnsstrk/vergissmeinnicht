import SwiftUI
import VergissmeinnichtKit

/// QuickCapture-Eingabe: Sheet-Pattern mit Titel-Feld, optionaler Notiz und
/// Metadaten-Buttons (Projekt, Tags, Due, Priorität, Wiederholung).
///
/// Schreibt Description, Project, Tags und Due über `AppContainer.addTask(...)` voll;
/// Priority und Recur werden nach der Anlage separat gesetzt.
struct QuickCaptureSheet: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var project: String = ""
    @State private var tags: [String] = []
    @State private var hasDue: Bool = false
    @State private var dueDate: Date = Date()
    @State private var priority: String = ""
    @State private var recur: String = ""

    @State private var showProjectInput: Bool = false
    @State private var newProjectInput: String = ""
    @State private var showTagInput: Bool = false
    @State private var newTagInput: String = ""

    @FocusState private var titleFocused: Bool

    private var availableProjects: [String] {
        Array(Set(container.tasks.filter { $0.status == .pending }.compactMap { $0.project }))
            .sorted(by: { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
    }
    private var availableTags: [String] {
        Array(Set(container.tasks.filter { $0.status == .pending }.flatMap { $0.tags }))
            .sorted(by: { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let priorityOptions: [(String, String)] = [
        ("",  "—"),
        ("H", "Hoch"),
        ("M", "Mittel"),
        ("L", "Niedrig"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleSection
            Divider()
            metadataSection
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            Divider()
            footer
        }
        .frame(width: 480)
        .task { titleFocused = true }
    }

    // MARK: - Title + Notes

    @ViewBuilder
    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Neue Aufgabe", text: $title)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($titleFocused)
                .onSubmit(save)
            TextField("Notizen (optional)", text: $notes, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2...4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Metadata buttons

    @ViewBuilder
    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                projectMenu
                tagMenu
            }
            HStack(spacing: 10) {
                dueControl
                priorityMenu
                recurMenu
            }
        }
    }

    @ViewBuilder
    private var projectMenu: some View {
        Menu {
            if !availableProjects.isEmpty {
                Picker(selection: $project) {
                    Text("(keins)").tag("")
                    Divider()
                    ForEach(availableProjects, id: \.self) { p in
                        Text(p).tag(p)
                    }
                } label: { EmptyView() }
                .pickerStyle(.inline)
            }
            Divider()
            Button("Neues Projekt …") {
                newProjectInput = ""
                showProjectInput = true
            }
        } label: {
            metadataChip(
                icon: "folder",
                title: project.isEmpty ? String(localized: "Projekt") : project,
                tint: project.isEmpty ? .secondary : .accentColor
            )
        }
        .sheet(isPresented: $showProjectInput) {
            inputSheet(
                title: "Neues Projekt",
                placeholder: "Projektname",
                text: $newProjectInput
            ) {
                let v = newProjectInput.trimmingCharacters(in: .whitespacesAndNewlines)
                if !v.isEmpty { project = v }
            }
        }
    }

    @ViewBuilder
    private var tagMenu: some View {
        Menu {
            if !availableTags.isEmpty {
                ForEach(availableTags, id: \.self) { tag in
                    Button {
                        toggleTag(tag)
                    } label: {
                        HStack {
                            if tags.contains(tag) {
                                Image(systemName: "checkmark")
                            }
                            Text(tag)
                        }
                    }
                }
                Divider()
            }
            Button("Neuer Tag …") {
                newTagInput = ""
                showTagInput = true
            }
        } label: {
            metadataChip(
                icon: "tag",
                title: tags.isEmpty ? String(localized: "Tags") : tags.joined(separator: ", "),
                tint: tags.isEmpty ? .secondary : .accentColor
            )
        }
        .sheet(isPresented: $showTagInput) {
            inputSheet(
                title: "Neuer Tag",
                placeholder: "Tag-Name (ohne +)",
                text: $newTagInput
            ) {
                let v = newTagInput.trimmingCharacters(in: .whitespacesAndNewlines)
                if !v.isEmpty, !tags.contains(v) { tags.append(v) }
            }
        }
    }

    @ViewBuilder
    private var dueControl: some View {
        HStack(spacing: 6) {
            Toggle("", isOn: $hasDue)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
            if hasDue {
                DatePicker("", selection: $dueDate, displayedComponents: [.date])
                    .labelsHidden()
                    .datePickerStyle(.compact)
            } else {
                Text("Fälligkeit")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: Capsule())
    }

    @ViewBuilder
    private var priorityMenu: some View {
        Menu {
            Picker(selection: $priority) {
                ForEach(Self.priorityOptions, id: \.0) { value, label in
                    Text(label).tag(value)
                }
            } label: { EmptyView() }
            .pickerStyle(.inline)
        } label: {
            metadataChip(
                icon: "exclamationmark.2",
                title: priority.isEmpty ? String(localized: "Priorität") : priorityLabel(priority),
                tint: priority.isEmpty ? .secondary : .accentColor
            )
        }
    }

    @ViewBuilder
    private var recurMenu: some View {
        Menu {
            Picker(selection: $recur) {
                ForEach(RecurParser.standardOptions, id: \.value) { opt in
                    Text(LocalizedStringKey(opt.labelKey)).tag(opt.value)
                }
            } label: { EmptyView() }
            .pickerStyle(.inline)
        } label: {
            metadataChip(
                icon: "arrow.triangle.2.circlepath",
                title: recur.isEmpty ? String(localized: "Wiederholung") : recur,
                tint: recur.isEmpty ? .secondary : .accentColor
            )
        }
    }

    @ViewBuilder
    private func metadataChip(icon: String, title: String, tint: Color) -> some View {
        Label(title, systemImage: icon)
            .font(.callout)
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tint.opacity(tint == .secondary ? 0.10 : 0.18), in: Capsule())
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        HStack {
            Spacer()
            Button("Abbrechen") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Hinzufügen") { save() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(trimmedTitle.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Input Sheet

    @ViewBuilder
    private func inputSheet(
        title: LocalizedStringKey,
        placeholder: LocalizedStringKey,
        text: Binding<String>,
        onCommit: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    onCommit()
                    closeInputSheets()
                }
            HStack {
                Spacer()
                Button("Abbrechen") { closeInputSheets() }
                    .keyboardShortcut(.cancelAction)
                Button("Übernehmen") {
                    onCommit()
                    closeInputSheets()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    // MARK: - Helpers

    private func toggleTag(_ tag: String) {
        if let idx = tags.firstIndex(of: tag) {
            tags.remove(at: idx)
        } else {
            tags.append(tag)
        }
    }

    private func priorityLabel(_ value: String) -> String {
        switch value {
        case "H": return String(localized: "Hoch")
        case "M": return String(localized: "Mittel")
        case "L": return String(localized: "Niedrig")
        default:  return value
        }
    }

    private func closeInputSheets() {
        showProjectInput = false
        showTagInput = false
    }

    private func save() {
        let desc = trimmedTitle
        guard !desc.isEmpty else { return }
        let projectVal = project.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyOrNil
        let dueVal: Int64? = hasDue ? Int64(endOfDay(dueDate).timeIntervalSince1970) : nil
        let priorityVal: String? = priority.isEmpty ? nil : priority
        let recurVal: String? = recur.isEmpty ? nil : recur
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            let newUuid: String?
            if projectVal != nil || !tags.isEmpty || dueVal != nil {
                newUuid = await container.addTask(
                    description: desc,
                    project: projectVal,
                    tags: tags,
                    due: dueVal
                )
            } else {
                newUuid = await container.addTask(description: desc)
            }
            // UUID kommt direkt aus dem FFI-Return — keine Description-Heuristik mehr.
            guard let uuid = newUuid else { return }
            if let p = priorityVal {
                _ = await container.setPriority(uuid: uuid, priority: p)
            }
            if let r = recurVal {
                _ = await container.setRecur(uuid: uuid, recur: r)
            }
            if !trimmedNotes.isEmpty {
                _ = await container.addAnnotation(uuid: uuid, annotation: trimmedNotes)
            }
            reset()
            dismiss()
        }
    }

    private func reset() {
        title = ""
        notes = ""
        project = ""
        tags = []
        hasDue = false
        dueDate = Date()
        priority = ""
        recur = ""
        titleFocused = true
    }

    private func endOfDay(_ date: Date) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let start = cal.startOfDay(for: date)
        return cal.date(byAdding: .day, value: 1, to: start)?.addingTimeInterval(-1) ?? date
    }
}

private extension String {
    var nonEmptyOrNil: String? { isEmpty ? nil : self }
}
