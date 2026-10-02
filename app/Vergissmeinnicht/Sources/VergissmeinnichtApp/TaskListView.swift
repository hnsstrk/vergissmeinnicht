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
    /// Gesamter Task-Pool (auch erledigte/ausgefilterte) — der Abhängigkeitsbaum braucht
    /// ihn für Ziele außerhalb der sichtbaren Liste.
    let allTasks: [TaskInfo]
    /// Abhängigkeiten als Baum statt flacher Liste (`AppSettingsKey.dependencyTree`).
    let dependencyTree: Bool
    /// Zeilen zeigen den Dringlichkeits-Chip (nur bei Sortierung nach Dringlichkeit).
    let showUrgency: Bool
    @Binding var collapsedTreeNodes: Set<String>
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
    /// Drop auf eine Task-Zeile: gezogene UUIDs hängen danach von der Ziel-UUID ab.
    var onDropDependency: ([String], String) -> Void

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
        if dependencyTree {
            listChrome(treeList)
        } else {
            listChrome(flatList)
        }
    }

    /// Kontextmenü, Doppelklick-Aktion und Leerzustand — für Flach- und Baumliste gleich.
    private func listChrome<L: View>(_ list: L) -> some View {
        list
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

    private var flatList: some View {
        List(tasks, id: \.uuid, selection: $selectedUuids) { task in
            decoratedRow(task)
        }
    }

    /// Zeile mit Drag-Quelle und Swipe-Aktionen — gemeinsam für Flach- und Baumliste.
    @ViewBuilder
    private func decoratedRow(_ task: TaskInfo, treeSlotWidth: CGFloat? = nil) -> some View {
        DependencyDropRow(
            target: task, allTasks: allTasks, dragSelection: dragSelection,
            onDrop: { dropped in onDropDependency(expandedDropUUIDs(dropped), task.uuid) }
        ) {
            TaskRowView(task: task, showUrgency: showUrgency, treeSlotWidth: treeSlotWidth)
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

    // MARK: - Abhängigkeitsbaum

    private var treeList: some View {
        let rows = DependencyTree.rows(visible: tasks, all: allTasks, collapsed: collapsedTreeNodes)
        var lookup: [String: TaskInfo] = [:]
        for t in allTasks { lookup[t.uuid] = t }
        for t in tasks { lookup[t.uuid] = t }
        // ID-Slot: Breite der längsten sichtbaren `#ID` (7 pt je Zeichen, mindestens Symbolbreite).
        let longestId = rows.compactMap { lookup[$0.taskUuid]?.workingSetId }.map { "#\($0)".count }.max() ?? 0
        let slotWidth = max(CGFloat(longestId) * 7, 16)
        var mainIndex: [String: Int] = [:]
        for (i, r) in rows.enumerated() where r.kind == .task { mainIndex[r.taskUuid] = i }
        return ScrollViewReader { proxy in
            List(selection: $selectedUuids) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    treeRow(
                        row, info: lookup[row.taskUuid], lookup: lookup, proxy: proxy,
                        mainBelow: mainIndex[row.taskUuid].map { $0 > index } ?? false,
                        slotWidth: slotWidth
                    )
                }
            }
            .onKeyPress(.rightArrow) { handleRightArrow(rows, proxy: proxy) }
            .onKeyPress(.leftArrow) { handleLeftArrow(rows, proxy: proxy) }
        }
    }

    @ViewBuilder
    private func treeRow(
        _ row: DependencyTreeRow, info: TaskInfo?, lookup: [String: TaskInfo], proxy: ScrollViewProxy,
        mainBelow: Bool, slotWidth: CGFloat
    ) -> some View {
        if let info {
            switch row.kind {
            case .task:
                TreeRowFrame(row: row, help: treeHelp(row, lookup: lookup), onToggle: { toggleCollapse(row) }) {
                    decoratedRow(info, treeSlotWidth: slotWidth)
                }
                .tag(row.taskUuid)
            case .reference:
                TreeRowFrame(row: row, help: treeHelp(row, lookup: lookup), onToggle: {}) {
                    treeNote(
                        slotWidth: slotWidth, icon: "arrow.turn.down.right", tint: .secondary,
                        text: mainBelow
                            ? String(localized: "\(taskLabel(info)) — siehe unten")
                            : String(localized: "\(taskLabel(info)) — siehe oben")
                    )
                }
                .selectionDisabled()
                .onTapGesture(count: 2) { revealMainRow(of: row.taskUuid, proxy: proxy) }
            case .cycle:
                TreeRowFrame(row: row, help: treeHelp(row, lookup: lookup), onToggle: {}) {
                    treeNote(
                        slotWidth: slotWidth, icon: "exclamationmark.triangle.fill", tint: .orange,
                        text: String(localized: "Zyklus: hängt von \(cycleLabel(lookup[row.parentUuid ?? ""] ?? info)) ab")
                    )
                }
                .selectionDisabled()
            case .outside:
                TreeRowFrame(row: row, help: treeHelp(row, lookup: lookup), onToggle: { toggleCollapse(row) }) {
                    treeNote(
                        slotWidth: slotWidth, icon: "eye.slash", tint: .secondary,
                        text: String(localized: "\(taskLabel(info)) — nicht in dieser Ansicht")
                    )
                }
                .selectionDisabled()
                .onTapGesture(count: 2) { onOpenDetail(row.taskUuid) }
            case .completed:
                TreeRowFrame(row: row, help: treeHelp(row, lookup: lookup), onToggle: { toggleCollapse(row) }) {
                    TaskRowView(task: info, showUrgency: showUrgency, treeSlotWidth: slotWidth).opacity(0.55)
                }
                .selectionDisabled()
                .onTapGesture(count: 2) { onOpenDetail(row.taskUuid) }
            }
        }
    }

    /// Tooltip der Baumzeile: Kinder werden frei, wenn ihre Elternzeile erledigt ist;
    /// Geist-Zeilen sagen, warum sie so aussehen.
    private func treeHelp(_ row: DependencyTreeRow, lookup: [String: TaskInfo]) -> String {
        switch row.kind {
        case .outside: return String(localized: "Voraussetzung außerhalb dieser Ansicht")
        case .completed: return String(localized: "Erledigte Voraussetzung")
        case .task, .reference, .cycle:
            guard let parent = row.parentUuid.flatMap({ lookup[$0] }) else { return "" }
            return String(localized: "Wird frei, wenn \(cycleLabel(parent)) erledigt ist")
        }
    }

    /// Hinweiszeile im Raster der Baumzeilen: Symbol im ID-Slot, Text bündig mit den Titeln.
    private func treeNote(slotWidth: CGFloat, icon: String, tint: Color, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(tint)
                .frame(width: slotWidth, alignment: .leading)
            Text(text)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func taskLabel(_ task: TaskInfo) -> String {
        if let id = task.workingSetId { return "#\(id) \(task.description)" }
        return task.description
    }

    private func cycleLabel(_ task: TaskInfo) -> String {
        if let id = task.workingSetId { return "#\(id)" }
        return task.description
    }

    /// Klappt einen Knoten auf oder zu. Beim Zuklappen wandert die Selektion zur
    /// Elternzeile, falls ein jetzt verborgener Nachfahre selektiert war; Geist-Zeilen
    /// sind nicht selektierbar, dann entfallen nur die verborgenen Nachfahren.
    private func toggleCollapse(_ row: DependencyTreeRow) {
        if collapsedTreeNodes.contains(row.id) {
            collapsedTreeNodes.remove(row.id)
            return
        }
        collapsedTreeNodes.insert(row.id)
        let prefix = row.id + "/"
        let full = DependencyTree.rows(visible: tasks, all: allTasks, collapsed: [])
        let hidden = Set(full.filter { $0.kind == .task && $0.id.hasPrefix(prefix) }.map { $0.taskUuid })
        if !selectedUuids.isDisjoint(with: hidden) {
            if row.kind == .task {
                selectedUuids = [row.taskUuid]
            } else {
                selectedUuids.subtract(hidden)
            }
        }
    }

    /// Hauptzeile des aktuell einzeln selektierten Tasks (nur wenn sie sichtbar ist).
    private func singleSelectedRow(_ rows: [DependencyTreeRow]) -> DependencyTreeRow? {
        guard selectedUuids.count == 1, let uuid = selectedUuids.first else { return nil }
        return rows.first { $0.kind == .task && $0.taskUuid == uuid }
    }

    private func select(_ row: DependencyTreeRow, proxy: ScrollViewProxy) {
        selectedUuids = [row.taskUuid]
        proxy.scrollTo(row.id)
    }

    /// → klappt auf bzw. springt zum ersten Kind, einem abhängigen Task (Finder-Verhalten).
    private func handleRightArrow(_ rows: [DependencyTreeRow], proxy: ScrollViewProxy) -> KeyPress.Result {
        guard let row = singleSelectedRow(rows), row.hasChildren else { return .ignored }
        if collapsedTreeNodes.contains(row.id) {
            collapsedTreeNodes.remove(row.id)
            return .handled
        }
        guard let start = rows.firstIndex(where: { $0.id == row.id }) else { return .ignored }
        var i = start + 1
        while i < rows.count, rows[i].depth > row.depth {
            if rows[i].depth == row.depth + 1, rows[i].kind == .task {
                select(rows[i], proxy: proxy)
                return .handled
            }
            i += 1
        }
        return .handled
    }

    /// ← klappt zu bzw. springt zur Elternzeile, der Voraussetzung (Finder-Verhalten).
    private func handleLeftArrow(_ rows: [DependencyTreeRow], proxy: ScrollViewProxy) -> KeyPress.Result {
        guard let row = singleSelectedRow(rows) else { return .ignored }
        if row.hasChildren, !collapsedTreeNodes.contains(row.id) {
            toggleCollapse(row)
            return .handled
        }
        // Nächste selektierbare Vorfahrenzeile (Geist-Zeilen überspringen).
        var parentId = row.parentId
        while let id = parentId, let parent = rows.first(where: { $0.id == id }) {
            if parent.kind == .task {
                select(parent, proxy: proxy)
                return .handled
            }
            parentId = parent.parentId
        }
        return .ignored
    }

    /// Doppelklick auf eine Verweiszeile: Hauptzeile selektieren (verdeckende Vorfahren
    /// aufklappen) und hinscrollen.
    private func revealMainRow(of uuid: String, proxy: ScrollViewProxy) {
        let full = DependencyTree.rows(visible: tasks, all: allTasks, collapsed: [])
        guard let main = full.first(where: { $0.kind == .task && $0.taskUuid == uuid }) else { return }
        var prefix = ""
        for component in main.id.split(separator: "/").dropLast() {
            prefix = prefix.isEmpty ? String(component) : prefix + "/" + component
            collapsedTreeNodes.remove(prefix)
        }
        selectedUuids = [uuid]
        Task { @MainActor in
            withAnimation { proxy.scrollTo(main.id, anchor: .center) }
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

    /// Erweitert die gezogenen UUIDs um die `dragSelection`, falls der Drag von einer
    /// Mehrfach-Selektion ausging (wie in der Sidebar).
    private func expandedDropUUIDs(_ dropped: [String]) -> [String] {
        guard let first = dropped.first, dragSelection.contains(first), dragSelection.count > 1 else {
            return dropped
        }
        return Array(dragSelection)
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

    // Karpathy 3/C1: endOfDay-Berechnung liegt zentral in DueDateParser.endOfDay(for:).
    private func dueOffset(days: Int) -> Int64 {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let target = cal.date(byAdding: .day, value: days, to: cal.startOfDay(for: Date())) ?? Date()
        return Int64(DueDateParser.endOfDay(for: target).timeIntervalSince1970)
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
        case .blocked:
            return ("Nichts blockiert", "lock.open", "Keine Aufgabe wartet auf eine andere.")
        case .blocking:
            return ("Nichts blockierend", "lock.open", "Keine Aufgabe blockiert eine andere.")
        case .unblocked:
            return ("Nichts frei", "checkmark.circle", "Keine sofort machbaren Aufgaben.")
        case .project, .tag:
            return ("Keine Aufgaben", "tray", "Keine Tasks in der aktuellen Auswahl.")
        case .savedSearch:
            return ("Keine Treffer", "magnifyingglass", "Diese gespeicherte Suche liefert aktuell keine Treffer.")
        }
    }
}

// MARK: - Baum-Zeile

/// Maße des Baum-Rasters (Zeilen und ID-Slot).
enum TreeLayout {
    /// Einrückung je Ebene = Breite der Klapp-Icon-Spalte.
    static let indent: CGFloat = 20
    /// Breite des Gruppen-Balkens.
    static let barWidth: CGFloat = 2
    /// Abstand des runden Balkenendes zur Unterkante der letzten Nachfahrenzeile.
    static let barEndInset: CGFloat = 6
    /// Mittelsegmente ragen oben/unten über die Zelle, falls die List Abstand lässt.
    static let barOverlap: CGFloat = 1
    /// Farbe von Balken und Klapp-Icon.
    static var accent: Color { Color.accentColor.opacity(0.6) }
}

/// Rahmen einer Baum-Zeile: feste Einrückung (`depth × 20 pt`), feste Klapp-Icon-Spalte
/// (auch leer) und „+N"-Zähler. Die Gruppen-Balken der Vorfahren liegen im
/// `listRowBackground`, der die ganze Zelle füllt — so laufen sie ohne Lücke durch.
/// Der horizontale Versatz zwischen Zellen- und Inhaltskoordinaten (Zeileneinzug plus
/// List-Rand) wird je Zeile in globalen Koordinaten gemessen, nicht geraten.
private struct TreeRowFrame<Content: View>: View {
    let row: DependencyTreeRow
    var help: String = ""
    let onToggle: () -> Void
    @ViewBuilder let content: Content

    @State private var contentMinX: CGFloat = 0
    @State private var backgroundMinX: CGFloat = 0

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Color.clear.frame(width: CGFloat(row.depth) * TreeLayout.indent, height: 1)
            toggleColumn
            content
            if row.hiddenCount > 0 {
                Text("+\(row.hiddenCount)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minX } action: { contentMinX = $0 }
        .help(help)
        .listRowInsets(EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 6))
        .listRowSeparator(.hidden)
        .listRowBackground(
            TreeBarsShape(bars: row.bars, originX: contentMinX - backgroundMinX)
                .fill(TreeLayout.accent)
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minX } action: { backgroundMinX = $0 }
        )
    }

    /// Klapp-Icon in fester Spalte auf Höhe der ersten Zeile; das Symbol bleibt
    /// dasselbe und dreht sich beim Aufklappen um 90°.
    @ViewBuilder
    private var toggleColumn: some View {
        Group {
            if row.hasChildren {
                Button(action: onToggle) {
                    Image(systemName: "chevron.right.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, TreeLayout.accent)
                        .font(.system(size: 14))
                        .rotationEffect(.degrees(row.hiddenCount > 0 ? 0 : 90))
                        .animation(.snappy(duration: 0.2), value: row.hiddenCount > 0)
                        .frame(width: TreeLayout.indent, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: TreeLayout.indent, height: 20)
            }
        }
    }
}

/// Zeichnet je Vorfahren-Ebene einen Balken mittig unter dessen Klapp-Icon. Er beginnt
/// an der Oberkante der ersten Kindzeile, endet rund `barEndInset` vor der Unterkante
/// der letzten Nachfahrenzeile und läuft dazwischen über die volle Zellenhöhe.
/// `originX` ist die x-Position des Inhaltsbeginns in Zellenkoordinaten.
private struct TreeBarsShape: Shape {
    let bars: [TreeBar]
    let originX: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = TreeLayout.barWidth
        for (level, bar) in bars.enumerated() {
            let x = originX + CGFloat(level) * TreeLayout.indent + (TreeLayout.indent - w) / 2
            let top = rect.minY - (bar.isStart ? 0 : TreeLayout.barOverlap)
            let bottom = bar.isEnd ? rect.maxY - TreeLayout.barEndInset : rect.maxY + TreeLayout.barOverlap
            guard bottom > top else { continue }
            let r = w / 2
            path.addRoundedRect(
                in: CGRect(x: x, y: top, width: w, height: bottom - top),
                cornerRadii: RectangleCornerRadii(
                    topLeading: 0, bottomLeading: bar.isEnd ? r : 0,
                    bottomTrailing: bar.isEnd ? r : 0, topTrailing: 0
                )
            )
        }
        return path
    }
}

// MARK: - Drop-Ziel Abhängigkeit

/// Drop-Ziel auf einer Hauptzeile: gezogene Tasks hängen danach von `target` ab.
/// Während des Drags Akzent-Hintergrund plus Hinweis, was passieren würde — oder
/// „Nicht möglich: Zyklus", wenn kein gezogener Task gültig wäre.
private struct DependencyDropRow<Content: View>: View {
    let target: TaskInfo
    let allTasks: [TaskInfo]
    let dragSelection: Set<String>
    let onDrop: ([String]) -> Void
    @ViewBuilder let content: Content

    @State private var isTargeted = false

    /// Gezogene Tasks, die tatsächlich neu von `target` abhängen würden.
    private var validDragged: [TaskInfo] {
        allTasks.filter { task in
            dragSelection.contains(task.uuid)
                && !task.depends.contains(target.uuid)
                && !DependencyGraph.wouldCreateCycle(task: task.uuid, dependsOn: target.uuid, tasks: allTasks)
        }
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(isTargeted && !validDragged.isEmpty ? Color.accentColor.opacity(0.18) : Color.clear)
            .overlay(alignment: .trailing) {
                if isTargeted { hint }
            }
            .dropDestination(for: String.self) { (uuids: [String], _: CGPoint) in
                onDrop(uuids)
                return !uuids.isEmpty
            } isTargeted: { targeted in
                isTargeted = targeted
            }
    }

    @ViewBuilder
    private var hint: some View {
        let valid = validDragged
        Group {
            if valid.isEmpty {
                Text("Nicht möglich: Zyklus")
            } else if valid.count == 1 {
                Text("„\(valid[0].description)“ hängt dann von „\(target.description)“ ab")
            } else {
                Text("\(valid.count) Aufgaben hängen dann von „\(target.description)“ ab")
            }
        }
        .font(.caption)
        .lineLimit(1)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.regularMaterial, in: Capsule())
        .padding(.trailing, 4)
        .allowsHitTesting(false)
    }
}
