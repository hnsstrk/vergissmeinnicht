import SwiftUI
import VergissmeinnichtKit

/// Haupt-Liste der Tasks im Detail-Pane des NavigationSplitView.
///
/// Selection nutzt das native macOS-`.contextMenu(forSelectionType:primaryAction:)`
/// API: Single-Click selektiert, Cmd-/Shift-Klick erweitert die Selection,
/// Doppelklick öffnet das Detail-Fenster, Rechtsklick zeigt das Aktions-Menü
/// für die aktuelle Selection (also auch Multi-Aktionen).
/// Tasks sind via `.draggable(uuid)` ziehbar — Drop-Ziele sind die Sidebar-Einträge.
struct TaskListView: View {
    let tasks: [TaskInfo]
    let activeFilter: SidebarFilter
    let projects: [String]
    let tags: [String]
    @Binding var selectedUuids: Set<String>
    @Binding var dragSelection: Set<String>
    var onOpenDetail: (String) -> Void
    var onMarkDone: (String) -> Void
    var onRequestDelete: (Set<String>) -> Void
    var onSnooze: (String, Int64?) -> Void
    var onAssignProject: (Set<String>, String?) -> Void
    var onAddTag: (Set<String>, String) -> Void
    var onSetPriority: (Set<String>, String?) -> Void
    var onSetDue: (Set<String>, Int64?) -> Void

    var body: some View {
        // Nur auf strukturelle Änderungen animieren (Anzahl + Status-Set), nicht
        // bei jedem Sync-Refresh die ganze Liste reanimieren — siehe UX-Audit U9.
        listBody
            .animation(.default, value: tasks.count)
            .animation(.default, value: completedCount)
    }

    private var completedCount: Int {
        tasks.lazy.filter { $0.status == .completed }.count
    }

    @ViewBuilder
    private var listBody: some View {
        List(tasks, id: \.uuid, selection: $selectedUuids) { task in
            TaskRowView(task: task)
                .draggable(task.uuid) {
                    dragPreview(for: task)
                        .onAppear {
                            if selectedUuids.contains(task.uuid), selectedUuids.count > 1 {
                                dragSelection = selectedUuids
                            } else {
                                dragSelection = [task.uuid]
                            }
                        }
                }
                .swipeActions(edge: .leading) {
                    if task.status == .pending {
                        Button {
                            onMarkDone(task.uuid)
                        } label: {
                            Label("Erledigt", systemImage: "checkmark.circle")
                        }
                        .tint(.green)
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        onRequestDelete([task.uuid])
                    } label: {
                        Label("Löschen", systemImage: "trash")
                    }
                }
        }
        .contextMenu(forSelectionType: String.self) { selection in
            contextMenuItems(for: selection)
        } primaryAction: { selection in
            if let uuid = selection.first {
                onOpenDetail(uuid)
            }
        }
        .overlay {
            if tasks.isEmpty {
                emptyState
            }
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func contextMenuItems(for selection: Set<String>) -> some View {
        if selection.isEmpty {
            EmptyView()
        } else {
            let pendingSelection = selection.filter { uuid in
                tasks.first { $0.uuid == uuid }?.status == .pending
            }
            if !pendingSelection.isEmpty {
                Button("Erledigt") {
                    for uuid in pendingSelection { onMarkDone(uuid) }
                }
            }
            if selection.count == 1, let uuid = selection.first {
                Button("Detail öffnen") { onOpenDetail(uuid) }
                if let task = tasks.first(where: { $0.uuid == uuid }), task.status == .pending {
                    Menu("Verschieben auf …") {
                        Button("Morgen")   { onSnooze(uuid, snoozeOffset(days: 1)) }
                        Button("+3 Tage")  { onSnooze(uuid, snoozeOffset(days: 3)) }
                        Button("+1 Woche") { onSnooze(uuid, snoozeOffset(days: 7)) }
                        if task.wait != nil {
                            Divider()
                            Button("Snooze aufheben") { onSnooze(uuid, nil) }
                        }
                    }
                }
            }
            if !selection.isEmpty {
                Menu("Projekt zuweisen …") {
                    Button("(keins)") { onAssignProject(selection, nil) }
                    Divider()
                    ForEach(projects, id: \.self) { p in
                        Button(p) { onAssignProject(selection, p) }
                    }
                }
                Menu("Tag hinzufügen …") {
                    ForEach(tags, id: \.self) { t in
                        Button(t) { onAddTag(selection, t) }
                    }
                }
                Menu("Priorität setzen") {
                    Button("Hoch (H)")    { onSetPriority(selection, "H") }
                    Button("Mittel (M)")  { onSetPriority(selection, "M") }
                    Button("Niedrig (L)") { onSetPriority(selection, "L") }
                    Divider()
                    Button("(keine)")     { onSetPriority(selection, nil) }
                }
                Menu("Fälligkeit setzen") {
                    Button("Heute")    { onSetDue(selection, dueOffset(days: 0)) }
                    Button("Morgen")   { onSetDue(selection, dueOffset(days: 1)) }
                    Button("+3 Tage")  { onSetDue(selection, dueOffset(days: 3)) }
                    Button("+1 Woche") { onSetDue(selection, dueOffset(days: 7)) }
                    Divider()
                    Button("(keine)")  { onSetDue(selection, nil) }
                }
            }
            Divider()
            Button("Löschen", role: .destructive) {
                onRequestDelete(selection)
            }
        }
    }

    // MARK: - Drag Preview

    @ViewBuilder
    private func dragPreview(for task: TaskInfo) -> some View {
        let isMulti = selectedUuids.contains(task.uuid) && selectedUuids.count > 1
        HStack(spacing: 6) {
            if isMulti {
                Text("\(selectedUuids.count)")
                    .font(.caption.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.tint, in: Capsule())
                    .foregroundStyle(.white)
            }
            Text(task.description)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
    }

    private func snoozeOffset(days: Int) -> Int64 {
        let now = Date()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let target = cal.date(byAdding: .day, value: days, to: cal.startOfDay(for: now)) ?? now
        return Int64(target.timeIntervalSince1970)
    }

    private func dueOffset(days: Int) -> Int64 {
        let now = Date()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let start = cal.date(byAdding: .day, value: days, to: cal.startOfDay(for: now)) ?? now
        let endOfDay = cal.date(byAdding: .day, value: 1, to: start)?.addingTimeInterval(-1) ?? start
        return Int64(endOfDay.timeIntervalSince1970)
    }

    // MARK: - Empty States

    @ViewBuilder
    private var emptyState: some View {
        let info = emptyStateInfo
        ContentUnavailableView(
            info.title,
            systemImage: info.systemImage,
            description: Text(info.description)
        )
    }

    private var emptyStateInfo: (title: LocalizedStringKey, systemImage: String, description: LocalizedStringKey) {
        switch activeFilter {
        case .inbox:
            return ("Eingang ist leer", "tray", "Alle Pending-Aufgaben haben Projekt oder Tag.")
        case .todo:
            return ("Alles erledigt!", "checkmark.circle", "Keine offenen Aufgaben.")
        case .overdue:
            return ("Nichts überfällig", "checkmark.shield", "Keine überfälligen Aufgaben.")
        case .dueSoon:
            return ("Nichts bald fällig", "clock", "Keine Aufgaben im Bald-fällig-Fenster.")
        case .all:
            return ("Keine Aufgaben", "tray", "Working Set ist leer.")
        case .today:
            return ("Heute ist frei", "star", "Keine fälligen Aufgaben für heute.")
        case .upcoming:
            return ("Nichts geplant", "calendar", "Keine zukünftig geplanten Aufgaben.")
        case .waiting:
            return ("Nichts wartend", "moon.zzz", "Keine wartenden Aufgaben.")
        case .project, .tag:
            return ("Keine Aufgaben", "tray", "Keine Tasks in der aktuellen Auswahl.")
        }
    }
}
