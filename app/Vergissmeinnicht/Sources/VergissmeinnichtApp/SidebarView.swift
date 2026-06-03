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
    @Binding var searchQuery: String
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

    @AppStorage(AppSettingsKey.projectsExpanded)    private var projectsExpanded: Bool = true
    @AppStorage(AppSettingsKey.tagsExpanded)        private var tagsExpanded:     Bool = true
    @AppStorage(AppSettingsKey.sidebarColoredIcons) private var coloredIcons:    Bool = true
    @AppStorage(AppSettingsKey.savedSearches)       private var savedSearchesRaw: String = "[]"
    @AppStorage(AppSettingsKey.sidebarProjectHierarchy)  private var projectHierarchy: Bool = true
    @AppStorage(AppSettingsKey.sidebarCollapsedProjects) private var collapsedProjectsRaw: String = "[]"

    @State private var renamingSavedSearch: SavedSearch? = nil

    // Gespeicherte Suchen: Encode/Decode über SavedSearch-Helfer, ohne retroaktive Conformance.
    // `nonmutating set` korrekt: der Setter schreibt nur durch @AppStorage (referenzsemantisch).
    private var savedSearches: [SavedSearch] {
        get { SavedSearch.decodeAll(from: savedSearchesRaw) }
        nonmutating set { savedSearchesRaw = SavedSearch.encodeAll(newValue) }
    }

    private var sortedSavedSearches: [SavedSearch] {
        savedSearches.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // Eingeklappte Projekt-Pfade als JSON-String in @AppStorage — gleiches Muster wie
    // savedSearches (referenzsemantischer Setter über @AppStorage). Ein Pfad ist
    // standardmäßig AUSGEKLAPPT (Abwesenheit = offen), nur explizit eingeklappte
    // Pfade landen im Set. Über einen String statt mehrerer Bools, weil die Projekt-
    // Pfade dynamisch sind (Karpathy 2).
    private var collapsedProjects: Set<String> {
        get {
            guard let data = collapsedProjectsRaw.data(using: .utf8),
                  let arr = try? JSONDecoder().decode([String].self, from: data)
            else { return [] }
            return Set(arr)
        }
        nonmutating set {
            collapsedProjectsRaw = (try? String(
                data: JSONEncoder().encode(Array(newValue).sorted()), encoding: .utf8
            )) ?? "[]"
        }
    }

    private func collapsedBinding(_ path: String) -> Binding<Bool> {
        Binding(
            get: { collapsedProjects.contains(path) },
            set: { isCollapsed in
                var set = collapsedProjects
                if isCollapsed { set.insert(path) } else { set.remove(path) }
                collapsedProjects = set
            }
        )
    }

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

            if !sortedSavedSearches.isEmpty {
                Section {
                    ForEach(sortedSavedSearches) { entry in
                        savedSearchRow(entry)
                    }
                } header: {
                    Text("Gespeicherte Suchen")
                }
            }

            if !projects.isEmpty {
                Section(isExpanded: $projectsExpanded) {
                    if projectHierarchy {
                        ForEach(visibleProjectRows, id: \.path) { row in
                            projectTreeRow(row)
                        }
                    } else {
                        ForEach(projects, id: \.self) { project in
                            projectRow(project)
                        }
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
        .onChange(of: activeFilter) { oldValue, newValue in
            // Saved-Search-Wechsel synchronisiert searchQuery (Apple-Pattern, vgl.
            // Mail Smart Mailbox): aktivieren setzt die Query, Verlassen löscht sie.
            if case .savedSearch(let id) = newValue,
               let entry = savedSearches.first(where: { $0.id == id }) {
                searchQuery = entry.query
            } else if case .savedSearch = oldValue {
                searchQuery = ""
            }
        }
        .sheet(item: $renamingSavedSearch) { entry in
            RenameSheet(
                title: "Suche umbenennen",
                oldName: entry.name
            ) { newName in
                var searches = savedSearches
                if let idx = searches.firstIndex(where: { $0.id == entry.id }) {
                    searches[idx].name = newName
                    savedSearches = searches
                }
            }
        }
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

    /// Farbiges SF-Symbol ohne Hintergrund. Bei deaktivierter Farboption
    /// erscheinen System-Zeilen einfarbig wie Projekt-/Tag-Zeilen.
    @ViewBuilder
    private func coloredIcon(systemImage: String, color: Color) -> some View {
        Image(systemName: systemImage)
            .foregroundStyle(coloredIcons ? AnyShapeStyle(color) : AnyShapeStyle(.secondary))
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
            badge: projectBadge(project),
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

    /// Badge-Count für eine Projekt-Zeile. Single Source of Truth mit der Hauptliste:
    /// Präfix-Match über `SidebarFilter.projectMatches`, sodass eine Eltern-Zeile
    /// Aufgaben des Projekts UND seiner Subprojekte zählt (#10). Bleibt wie bisher
    /// auf `pending` begrenzt — `matches()` gatet `.project` bewusst NICHT auf Status,
    /// aber die Badge zeigt seit jeher nur offene Aufgaben (wie die Tag-Badge).
    private func projectBadge(_ path: String) -> Int {
        tasks.filter {
            $0.status == .pending && SidebarFilter.projectMatches($0.project, selected: path)
        }.count
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

    /// Saved-Search-Zeile als reguläre Sidebar-Selektion. Die Query-Synchronisation
    /// erledigt `applySavedSearchSelection`, damit die List-Selection eindeutig ist
    /// (kein Custom-Highlight, kein Doppel-Marker mit „Alle").
    @ViewBuilder
    private func savedSearchRow(_ entry: SavedSearch) -> some View {
        Label(entry.name, systemImage: "magnifyingglass")
            .tag(SidebarFilter.savedSearch(entry.id))
            .contextMenu {
                Button("Umbenennen …") { renamingSavedSearch = entry }
                Button("Löschen", role: .destructive) {
                    var searches = savedSearches
                    searches.removeAll { $0.id == entry.id }
                    savedSearches = searches
                    // Falls die gerade aktive Saved Search gelöscht wurde:
                    // sauber zurück auf Eingang, sonst zeigte die List eine
                    // Selektion auf einer nicht mehr existierenden ID.
                    if case .savedSearch(let activeId) = activeFilter, activeId == entry.id {
                        activeFilter = .inbox
                        searchQuery = ""
                    }
                }
            }
    }

    // MARK: - Projekt-Hierarchie (#10)

    /// Eine Zeile im gerenderten Projekt-Baum. `path` ist der volle Punkt-Pfad
    /// (z. B. `Arbeit.KundeA`) und dient als Filter-Wert UND Collapse-Key; `segment`
    /// ist nur das letzte Pfad-Element (Anzeige); `depth` steuert die Einrückung;
    /// `hasChildren` zeigt das Chevron. Der Baum ist ein reines Rendering der flachen,
    /// dotted Projekt-Namen — kein neues Datenmodell (Taskwarrior-treu).
    private struct ProjectTreeRow {
        let path: String
        let segment: String
        let depth: Int
        let hasChildren: Bool
    }

    /// Baut die flache, vorsortierte Liste sichtbarer Baum-Zeilen (Pre-Order).
    /// Synthetische Eltern (Pfade ohne eigenes `project:`-Task, aber mit Subprojekten)
    /// werden eingefügt und sind selektierbar — ihre Auswahl matcht per Präfix alle
    /// Nachfahren. Eingeklappte Knoten verbergen ihre Nachfahren in der Anzeige.
    private var visibleProjectRows: [ProjectTreeRow] {
        // 1. Alle Pfade sammeln: echte Projekte + alle Zwischen-Eltern.
        var allPaths = Set<String>()
        var childrenOf = [String: Set<String>]()   // Pfad → direkte Kind-Pfade
        for project in projects {
            let segments = project.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            var prefix = ""
            for (i, seg) in segments.enumerated() {
                prefix = i == 0 ? seg : prefix + "." + seg
                allPaths.insert(prefix)
                if i > 0 {
                    let parent = segments[0..<i].joined(separator: ".")
                    childrenOf[parent, default: []].insert(prefix)
                }
            }
        }

        // 2. Wurzeln = Pfade ohne "." (Top-Level), alphabetisch.
        let roots = allPaths
            .filter { !$0.contains(".") }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        // 3. Pre-Order-Traversierung; eingeklappte Knoten brechen den Abstieg ab.
        var result: [ProjectTreeRow] = []
        let collapsed = collapsedProjects
        func visit(_ path: String, depth: Int) {
            let kids = (childrenOf[path] ?? [])
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            let segment = path.split(separator: ".", omittingEmptySubsequences: false).map(String.init).last ?? path
            result.append(ProjectTreeRow(path: path, segment: segment, depth: depth, hasChildren: !kids.isEmpty))
            guard !collapsed.contains(path) else { return }
            for kid in kids { visit(kid, depth: depth + 1) }
        }
        for root in roots { visit(root, depth: 0) }
        return result
    }

    /// Eine Baum-Zeile: einrückendes Spacer + optionales Chevron (klappt nur ein/aus,
    /// ohne die Zeilen-Selektion zu stören) + selektierbares Drop-Target mit Ordner-
    /// Symbol. Eltern-Zeilen sind ebenso selektierbar wie Blätter (Präfix-Filter).
    @ViewBuilder
    private func projectTreeRow(_ row: ProjectTreeRow) -> some View {
        DropTargetRow(
            badge: projectBadge(row.path),
            filter: .project(row.path),
            onDrop: { uuids in
                for uuid in expandedDropUUIDs(uuids) { onDropProject(uuid, row.path) }
            }
        ) {
            HStack(spacing: 4) {
                if row.depth > 0 {
                    Spacer().frame(width: CGFloat(row.depth) * 14)
                }
                if row.hasChildren {
                    let collapsed = collapsedBinding(row.path)
                    Button {
                        collapsed.wrappedValue.toggle()
                    } label: {
                        Image(systemName: collapsed.wrappedValue ? "chevron.right" : "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 12)
                    }
                    .buttonStyle(.plain)
                } else {
                    Spacer().frame(width: 12)
                }
                Label(row.segment, systemImage: "folder")
            }
        }
        .contextMenu {
            Button("Umbenennen …") { onRenameProject(row.path) }
            Button("Aus allen Tasks entfernen", role: .destructive) {
                onClearProject(row.path)
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
