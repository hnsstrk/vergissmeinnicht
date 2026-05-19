import SwiftUI
import VergissmeinnichtKit

/// Klassische Navigations-Sidebar.
///
/// Reihenfolge: Eingang → Zu erledigen → Überfällig → Bald fällig → Alle (inkl. erledigt).
/// Dynamische Sektionen für Projekte und Tags werden aus dem Pending-Pool abgeleitet.
///
/// Drop-Verhalten (UUID-Strings):
/// - Drop auf Projekt-Zeile → `setProject` mit dem Projekt-Namen
/// - Drop auf Tag-Zeile → `addTag` mit dem Tag-Namen
/// - Drop auf Eingang → `setProject(nil)` und alle Tags entfernen
/// - Drop auf Alle/Zu erledigen/Überfällig/Bald fällig → ignoriert (kein semantisches Mapping)
struct SidebarView: View {
    let tasks: [TaskInfo]
    @Binding var activeFilter: SidebarFilter
    let projects: [String]
    let tags: [String]
    let dueSoonDays: Int
    let dragSelection: Set<String>                       // Multi-Drag-Erweiterung der gedropten UUIDs
    var onDropProject: (String, String) -> Void          // (uuid, project)
    var onDropTag: (String, String) -> Void              // (uuid, tag)
    var onDropInbox: (String) -> Void                    // uuid → clear project+tags
    var onRenameProject: (String) -> Void                // open rename sheet for project
    var onClearProject: (String) -> Void                 // remove project from all tasks
    var onRenameTag: (String) -> Void                    // open rename sheet for tag
    var onClearTag: (String) -> Void                     // remove tag from all tasks

    @AppStorage(AppSettingsKey.projectsExpanded) private var projectsExpanded: Bool = true
    @AppStorage(AppSettingsKey.tagsExpanded)     private var tagsExpanded:     Bool = true

    var body: some View {
        List(selection: selectionBinding) {
            Section {
                inboxRow
                coloredRow(.today,   label: "Heute",        systemImage: "star.fill",                   color: .yellow,  count: todayCount)
                coloredRow(.todo,    label: "Zu erledigen", systemImage: "list.bullet",                 color: .green,   count: todoCount)
                coloredRow(.overdue, label: "Überfällig",   systemImage: "exclamationmark.circle.fill", color: .red,     count: overdueCount)
                coloredRow(.dueSoon, label: "Bald fällig",  systemImage: "clock.fill",                  color: .orange,  count: dueSoonCount)
                if upcomingCount > 0 {
                    coloredRow(.upcoming, label: "Geplant",  systemImage: "calendar",                   color: .indigo,  count: upcomingCount)
                }
                if waitingCount > 0 {
                    coloredRow(.waiting, label: "Wartend",   systemImage: "moon.zzz.fill",              color: .gray,    count: waitingCount)
                }
                coloredRow(.all,     label: "Alle",          systemImage: "tray.full.fill",             color: .purple,  count: tasks.count)
            }

            if !projects.isEmpty {
                Section(isExpanded: $projectsExpanded) {
                    ForEach(projects, id: \.self) { project in
                        projectRow(project)
                    }
                } header: {
                    Text("Projekte")
                }
            }

            if !tags.isEmpty {
                Section(isExpanded: $tagsExpanded) {
                    ForEach(tags, id: \.self) { tag in
                        tagRow(tag)
                    }
                } header: {
                    Text("Tags")
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Rows

    /// Zeigt eine Sidebar-Zeile mit farbigem Symbol (ohne Hintergrund).
    @ViewBuilder
    private func coloredRow(_ filter: SidebarFilter, label: LocalizedStringKey, systemImage: String, color: Color, count: Int) -> some View {
        Label {
            Text(label)
        } icon: {
            coloredIcon(systemImage: systemImage, color: color)
        }
        .badge(count)
        .tag(filter)
    }

    /// Farbiges SF-Symbol ohne Hintergrund.
    @ViewBuilder
    private func coloredIcon(systemImage: String, color: Color) -> some View {
        Image(systemName: systemImage)
            .foregroundStyle(color)
    }

    @ViewBuilder
    private var inboxRow: some View {
        DropTargetRow(
            badge: inboxCount,
            filter: .inbox,
            onDrop: { uuids in
                for uuid in expandedDropUUIDs(uuids) { onDropInbox(uuid) }
            }
        ) {
            Label {
                Text("Eingang")
            } icon: {
                coloredIcon(systemImage: "tray.fill", color: .blue)
            }
        }
    }

    @ViewBuilder
    private func projectRow(_ project: String) -> some View {
        DropTargetRow(
            badge: tasks.filter { $0.status == .pending && $0.project == project }.count,
            filter: .project(project),
            onDrop: { uuids in
                for uuid in expandedDropUUIDs(uuids) { onDropProject(uuid, project) }
            }
        ) {
            Label(project, systemImage: "folder")
        }
        .contextMenu {
            Button("Umbenennen …") { onRenameProject(project) }
            Button("Aus allen Tasks entfernen", role: .destructive) {
                onClearProject(project)
            }
        }
    }

    @ViewBuilder
    private func tagRow(_ tag: String) -> some View {
        DropTargetRow(
            badge: tasks.filter { $0.status == .pending && $0.tags.contains(tag) }.count,
            filter: .tag(tag),
            onDrop: { uuids in
                for uuid in expandedDropUUIDs(uuids) { onDropTag(uuid, tag) }
            }
        ) {
            Label(tag, systemImage: "tag")
        }
        .contextMenu {
            Button("Umbenennen …") { onRenameTag(tag) }
            Button("Aus allen Tasks entfernen", role: .destructive) {
                onClearTag(tag)
            }
        }
    }

    /// Erweitert die per Drag&Drop angelieferten UUIDs um die `dragSelection`, falls
    /// der Drag ursprünglich von einer Selection mit mehreren Tasks ausging.
    /// Fallback: nur die übergebenen UUIDs.
    private func expandedDropUUIDs(_ dropped: [String]) -> [String] {
        guard let first = dropped.first, dragSelection.contains(first), dragSelection.count > 1 else {
            return dropped
        }
        return Array(dragSelection)
    }

    // MARK: - Counts

    /// Single Source of Truth: alle Counts gehen über `SidebarFilter.matches` —
    /// damit driften Sidebar-Badge und sichtbare Liste nicht mehr auseinander
    /// (Code-Audit-Finding W2).
    private func count(_ filter: SidebarFilter) -> Int {
        let now = Date()
        return tasks.filter { filter.matches($0, now: now, dueSoonDays: dueSoonDays) }.count
    }

    private var todoCount:     Int { count(.todo) }
    private var todayCount:    Int { count(.today) }
    private var inboxCount:    Int { count(.inbox) }
    private var overdueCount:  Int { count(.overdue) }
    private var dueSoonCount:  Int { count(.dueSoon) }
    private var upcomingCount: Int { count(.upcoming) }
    private var waitingCount:  Int { count(.waiting) }

    // MARK: - Selection

    private var selectionBinding: Binding<SidebarFilter?> {
        Binding(
            get: { activeFilter },
            set: { activeFilter = $0 ?? .inbox }
        )
    }
}

/// Sidebar-Zeile mit Drop-Target und visuellem Highlight während des Drags.
/// Wird für Eingang, Projekte und Tags wiederverwendet.
private struct DropTargetRow<LabelContent: View>: View {
    let badge: Int
    let filter: SidebarFilter
    let onDrop: ([String]) -> Void
    @ViewBuilder let labelContent: () -> LabelContent

    @State private var isTargeted: Bool = false

    var body: some View {
        labelContent()
            .badge(badge)
            .tag(filter)
            .listRowBackground(
                isTargeted ? Color.accentColor.opacity(0.18) : Color.clear
            )
            .dropDestination(for: String.self) { (uuids: [String], _: CGPoint) in
                onDrop(uuids)
                return !uuids.isEmpty
            } isTargeted: { targeted in
                isTargeted = targeted
            }
    }
}
