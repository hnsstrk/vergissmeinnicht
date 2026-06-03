import SwiftUI
import VergissmeinnichtKit

/// Read-Pfad-Root: Sidebar (Navigation) | TaskListView (Hauptbereich).
/// Die DetailView lebt in einem eigenständigen Fenster (`task-detail` WindowGroup),
/// das per Doppelklick auf eine Task-Zeile geöffnet wird.
///
/// Liest die Default-Settings (Standard-Filter, Standard-Sort, Bald-Fällig-Fenster)
/// aus `AppStorage` und propagiert sie in den `TaskListViewModel`.
/// Identifizierbares Ziel für das Rename-Sheet — sowohl Project- als auch Tag-Rename
/// nutzen denselben Sheet.
enum RenameTarget: Identifiable {
    case project(String)
    case tag(String)

    var id: String {
        switch self {
        case .project(let n): return "p:\(n)"
        case .tag(let n):     return "t:\(n)"
        }
    }
    var name: String {
        switch self {
        case .project(let n), .tag(let n): return n
        }
    }
    var titleKey: LocalizedStringKey {
        switch self {
        case .project: return "Projekt umbenennen"
        case .tag:     return "Tag umbenennen"
        }
    }
}

struct RootView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.openWindow) private var openWindow
    @State private var viewModel = TaskListViewModel()
    @State private var showQuickCapture = false
    @State private var pendingDelete: Set<String> = []
    @State private var renameTarget: RenameTarget?
    /// Während Drag&Drop gefüllt: alle UUIDs, die zur aktuellen Multi-Selection
    /// gehören. Wenn der Drag von einer selektierten Task startet, zieht sie die
    /// gesamte Selection mit; sonst nur sich selbst.
    @State private var dragSelection: Set<String> = []
    /// Zustand des „Suche sichern"-Popovers.
    @State private var showSaveSearchPopover = false

    @AppStorage(AppSettingsKey.defaultFilter) private var defaultFilterRaw: String = DefaultFilter.inbox.rawValue
    @AppStorage(AppSettingsKey.defaultSort)   private var defaultSortRaw: String = SortOrder.id.rawValue
    @AppStorage(AppSettingsKey.sortAscending) private var sortAscending: Bool = true
    @AppStorage(AppSettingsKey.dueSoonDays)   private var dueSoonDays: Int = 7
    @AppStorage(AppSettingsKey.notifications) private var notificationsEnabled: Bool = false
    @AppStorage(AppSettingsKey.hideCompleted) private var hideCompleted: Bool = false
    @AppStorage(AppSettingsKey.autoSyncMode)    private var autoSyncModeRaw: String = AutoSyncMode.manual.rawValue
    @AppStorage(AppSettingsKey.savedSearches)  private var savedSearchesRaw: String = "[]"

    var body: some View {
        @Bindable var vm = viewModel
        let projects = TaskListViewModel.projects(from: container.tasks)
        let tags = TaskListViewModel.tags(from: container.tasks)
        let visible = viewModel.visibleTasks(from: container.tasks)

        NavigationSplitView {
            SidebarView(
                tasks: container.tasks,
                activeFilter: $vm.activeFilter,
                searchQuery: $vm.searchQuery,
                projects: projects,
                tags: tags,
                dueSoonDays: dueSoonDays,
                dragSelection: dragSelection,
                onDropProject: handleDropProject,
                onDropTag: handleDropTag,
                onDropInbox: handleDropInbox,
                onRenameProject: { renameTarget = .project($0) },
                onClearProject: handleClearProject,
                onRenameTag: { renameTarget = .tag($0) },
                onClearTag: handleClearTag
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            TaskListView(
                tasks: visible,
                activeFilter: vm.activeFilter,
                projects: projects,
                tags: tags,
                selectedUuids: $vm.selectedUuids,
                dragSelection: $dragSelection,
                onOpenDetail: openDetailWindow,
                onMarkDone: handleMarkDone,
                onRequestDelete: requestDelete,
                onSnooze: handleSnooze,
                onAssignProject: handleAssignProject,
                onAddTag: handleAddTag,
                onSetPriority: handleSetPriority,
                onSetDue: handleSetDue
            )
            .safeAreaInset(edge: .bottom) { syncFooter }
            .navigationTitle(filterTitle)
            .searchable(text: $vm.searchQuery, prompt: Text("Suchen…"))
            .toolbar { detailToolbar(vm: vm) }
        }
        .frame(minWidth: 720, minHeight: 420)
        .sheet(isPresented: $showQuickCapture) {
            QuickCaptureSheet()
                .environment(container)
        }
        .sheet(item: $renameTarget) { target in
            RenameSheet(
                title: target.titleKey,
                oldName: target.name
            ) { newName in
                handleRename(target: target, newName: newName)
            }
        }
        .task {
            applyDefaults()
            let syncMode = AutoSyncMode(rawValue: autoSyncModeRaw) ?? .manual
            container.configureAutoSync(mode: syncMode)
            if notificationsEnabled {
                await NotificationService.shared.requestAuthorizationIfNeeded()
            }
            await container.refresh()
            await container.syncIfConfigured()
            if notificationsEnabled {
                await NotificationService.shared.notifyOverdueIfNeeded(tasks: container.tasks)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .vmCommand)) { notif in
            guard let cmd = notif.object as? AppCommand else { return }
            switch cmd {
            case .newTask:
                showQuickCapture = true
            case .markDoneSelection:
                handleMarkDoneSelection()
            case .deleteSelection:
                requestDelete(uuids: viewModel.selectedUuids)
            case .openDetail:
                if let uuid = viewModel.selectedUuid {
                    openDetailWindow(uuid)
                }
            case .showFilter(let filter):
                viewModel.activeFilter = filter
            }
        }
        .onChange(of: dueSoonDays) { _, newValue in
            viewModel.dueSoonDays = newValue
        }
        .onChange(of: hideCompleted) { _, newValue in
            viewModel.hideCompleted = newValue
        }
        .onChange(of: autoSyncModeRaw) { _, new in
            container.configureAutoSync(mode: AutoSyncMode(rawValue: new) ?? .manual)
        }
        .onChange(of: container.tasks) { _, newTasks in
            viewModel.selectedUuids = viewModel.selectedUuids.filter { uuid in
                newTasks.contains(where: { $0.uuid == uuid })
            }
        }
        .confirmationDialog(
            Text(deleteDialogTitle),
            isPresented: deleteDialogBinding,
            titleVisibility: .visible
        ) {
            Button("Löschen", role: .destructive) {
                performDelete()
            }
            Button("Abbrechen", role: .cancel) { pendingDelete.removeAll() }
        } message: {
            Text("Diese Aktion ist nicht umkehrbar.")
        }
        .overlay(alignment: .bottom) {
            if let error = container.lastError {
                ErrorBannerView(
                    message: error,
                    onRetry: { Task { await container.syncIfConfigured() } },
                    onDismiss: { container.clearError() }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: error) {
                    // Auto-Dismiss nach 6 s. Cancel automatisch, wenn ein neuer
                    // Fehler kommt (neue task-id triggert neuen Lauf).
                    try? await Task.sleep(nanoseconds: 6_000_000_000)
                    container.clearError()
                }
            }
        }
    }

    // MARK: - Toolbar

    /// Mail-Stil: Sort / Plus / Erledigt / Löschen / Sync zentral (principal),
    /// Bookmark rechts (primaryAction) — nur bei aktiver Suche sichtbar.
    @ToolbarContentBuilder
    private func detailToolbar(vm: TaskListViewModel) -> some ToolbarContent {
        ToolbarItemGroup(placement: .principal) {
            Menu {
                Picker(selection: Binding(get: { vm.sortOrder }, set: { vm.sortOrder = $0; defaultSortRaw = $0.rawValue })) {
                    ForEach(SortOrder.allCases) { order in
                        Text(order.label).tag(order)
                    }
                } label: { Text("Sortieren") }
                Divider()
                Picker(selection: Binding(get: { vm.sortAscending }, set: { vm.sortAscending = $0; sortAscending = $0 })) {
                    Text("Aufsteigend").tag(true)
                    Text("Absteigend").tag(false)
                } label: { Text("Richtung") }
            } label: {
                Label("Sortieren", systemImage: vm.sortAscending ? "arrow.up.arrow.down" : "arrow.up.arrow.down.circle")
            }
            .menuIndicator(.hidden)
            .help("Sortierung")

            Button {
                showQuickCapture = true
            } label: {
                Label("Neue Aufgabe", systemImage: "plus")
            }
            .help("Neue Aufgabe (Cmd+N)")

            Button {
                handleMarkDoneSelection()
            } label: {
                Label("Erledigt", systemImage: "checkmark.circle")
            }
            .disabled(vm.selectedUuids.isEmpty)
            .help("Ausgewählte Aufgabe(n) als erledigt markieren (Cmd+D)")

            Button {
                requestDelete(uuids: vm.selectedUuids)
            } label: {
                Label("Löschen", systemImage: "trash")
            }
            .disabled(vm.selectedUuids.isEmpty)
            .help("Ausgewählte Aufgabe(n) löschen (Cmd+⌫)")

            SyncStatusView()
        }
        if !vm.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showSaveSearchPopover = true
                } label: {
                    Label("Suche sichern", systemImage: "bookmark")
                }
                .help("Suche sichern (⇧⌘D)")
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .popover(isPresented: $showSaveSearchPopover) {
                    SaveSearchPopoverView(
                        query: vm.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines),
                        savedSearchesRaw: $savedSearchesRaw,
                        isPresented: $showSaveSearchPopover
                    )
                }
            }
        }
    }

    // MARK: - Sync-Footer

    /// Live tickender Auto-Sync-Countdown am unteren Rand der Aufgabenliste.
    /// Bewusst hier statt in der Toolbar: variabel breiter Text bricht das
    /// Icon-Raster, und ein macOS-Tooltip kann nicht sekündlich aktualisieren.
    /// `TimelineView` re-rendert nur diesen Footer, nicht die Liste.
    @ViewBuilder
    private var syncFooter: some View {
        if let nextSync = container.nextSyncDate, !container.isSyncing {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                HStack {
                    Spacer()
                    Text("Nächster Sync in \(syncCountdownString(to: nextSync))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.trailing, 20)
                .padding(.bottom, 12)
                .padding(.top, 6)
                .padding(.leading, 12)
            }
        }
    }

    /// Formatiert die verbleibende Zeit bis `date` als `m:ss`. Negativ → "0:00".
    private func syncCountdownString(to date: Date) -> String {
        let total = Int(max(0, date.timeIntervalSinceNow))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - Helpers

    private func applyDefaults() {
        viewModel.dueSoonDays = dueSoonDays
        viewModel.hideCompleted = hideCompleted
        if viewModel.activeFilter == .inbox,
           let f = DefaultFilter(rawValue: defaultFilterRaw) {
            viewModel.activeFilter = f.asSidebarFilter
        }
        if let s = SortOrder(rawValue: defaultSortRaw) {
            viewModel.sortOrder = s
        }
        viewModel.sortAscending = sortAscending
    }

    private func openDetailWindow(_ uuid: String) {
        openWindow(id: "task-detail", value: uuid)
    }

    private func handleMarkDone(_ uuid: String) {
        Task { await container.markDoneWithRecurrence(uuid: uuid) }
    }

    private func handleMarkDoneSelection() {
        let uuids = viewModel.selectedUuids
        Task {
            await container.withBatch {
                for uuid in uuids {
                    _ = await container.markDoneWithRecurrence(uuid: uuid)
                }
            }
        }
    }

    private func requestDelete(uuids: Set<String>) {
        guard !uuids.isEmpty else { return }
        pendingDelete = uuids
    }

    private func performDelete() {
        let uuids = pendingDelete
        pendingDelete.removeAll()
        Task {
            await container.withBatch {
                for uuid in uuids {
                    _ = await container.deleteTask(uuid: uuid)
                }
            }
        }
    }

    private func handleSnooze(_ uuid: String, _ wait: Int64?) {
        Task { await container.setWait(uuid: uuid, wait: wait) }
    }

    private func handleAssignProject(_ uuids: Set<String>, _ project: String?) {
        Task {
            await container.withBatch {
                for uuid in uuids {
                    _ = await container.setProject(uuid: uuid, project: project)
                }
            }
        }
    }

    private func handleAddTag(_ uuids: Set<String>, _ tag: String) {
        Task {
            await container.withBatch {
                for uuid in uuids {
                    _ = await container.addTag(uuid: uuid, tag: tag)
                }
            }
        }
    }

    private func handleSetPriority(_ uuids: Set<String>, _ priority: String?) {
        Task {
            await container.withBatch {
                for uuid in uuids {
                    _ = await container.setPriority(uuid: uuid, priority: priority)
                }
            }
        }
    }

    private func handleSetDue(_ uuids: Set<String>, _ due: Int64?) {
        Task {
            await container.withBatch {
                for uuid in uuids {
                    _ = await container.setDue(uuid: uuid, due: due)
                }
            }
        }
    }

    private func handleRename(target: RenameTarget, newName: String) {
        Task {
            switch target {
            case .project(let oldName):
                _ = await container.renameProject(from: oldName, to: newName)
                if viewModel.activeFilter == .project(oldName) {
                    viewModel.activeFilter = .project(newName)
                }
            case .tag(let oldName):
                _ = await container.renameTag(from: oldName, to: newName)
                if viewModel.activeFilter == .tag(oldName) {
                    viewModel.activeFilter = .tag(newName)
                }
            }
        }
    }

    private func handleClearProject(_ name: String) {
        Task {
            _ = await container.clearProject(name: name)
            if viewModel.activeFilter == .project(name) {
                viewModel.activeFilter = .inbox
            }
        }
    }

    private func handleClearTag(_ name: String) {
        Task {
            _ = await container.clearTag(name: name)
            if viewModel.activeFilter == .tag(name) {
                viewModel.activeFilter = .inbox
            }
        }
    }

    private func handleDropProject(_ uuid: String, _ project: String) {
        Task { await container.setProject(uuid: uuid, project: project) }
    }

    private func handleDropTag(_ uuid: String, _ tag: String) {
        Task { await container.addTag(uuid: uuid, tag: tag) }
    }

    private func handleDropInbox(_ uuid: String) {
        Task {
            guard let task = container.tasks.first(where: { $0.uuid == uuid }) else { return }
            _ = await container.setProject(uuid: uuid, project: nil)
            for tag in task.tags {
                _ = await container.removeTag(uuid: uuid, tag: tag)
            }
        }
    }

    private var deleteDialogBinding: Binding<Bool> {
        Binding(
            get: { !pendingDelete.isEmpty },
            set: { if !$0 { pendingDelete.removeAll() } }
        )
    }

    private var deleteDialogTitle: LocalizedStringKey {
        if pendingDelete.count <= 1 {
            return "Aufgabe wirklich löschen?"
        } else {
            // Plural via xcstrings-Substitution.
            return "\(pendingDelete.count) Aufgaben werden gelöscht. Vorgang ist nicht umkehrbar."
        }
    }

    private var filterTitle: LocalizedStringKey {
        switch viewModel.activeFilter {
        case .all:               return "Alle"
        case .today:             return "Heute"
        case .todo:              return "Zu erledigen"
        case .inbox:             return "Eingang"
        case .overdue:           return "Überfällig"
        case .dueSoon:           return "Bald fällig"
        case .upcoming:          return "Geplant"
        case .waiting:           return "Wartend"
        case .blocked:           return "Blockiert"
        case .blocking:          return "Blockierend"
        case .unblocked:         return "Nicht blockiert"
        case .project(let p):    return LocalizedStringKey(p)
        case .tag(let t):        return LocalizedStringKey(t)
        case .savedSearch(let id):
            let name = SavedSearch.decodeAll(from: savedSearchesRaw)
                .first(where: { $0.id == id })?.name
            return LocalizedStringKey(name ?? "Gespeicherte Suchen")
        }
    }
}

// MARK: - Suche sichern Popover

/// Kleines Popover zum Benennen und Speichern einer Suchanfrage.
/// Karpathy 2: eigener FocusState lebt hier, damit RootView schlank bleibt.
private struct SaveSearchPopoverView: View {
    let query: String
    @Binding var savedSearchesRaw: String
    @Binding var isPresented: Bool

    @State private var name: String = ""
    @State private var duplicateName: String? = nil
    @FocusState private var focused: Bool

    // `nonmutating set` korrekt: der Setter schreibt nur durch @Binding (referenzsemantisch).
    private var savedSearches: [SavedSearch] {
        get { SavedSearch.decodeAll(from: savedSearchesRaw) }
        nonmutating set { savedSearchesRaw = SavedSearch.encodeAll(newValue) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Suche sichern").font(.headline)
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
                .focused($focused)
                .onSubmit(commit)
            if let dup = duplicateName {
                Text("Diese Suche existiert bereits als \u{201E}\(dup)\u{201C}")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(width: 260, alignment: .leading)
            }
            HStack {
                Spacer()
                Button("Abbrechen") {
                    isPresented = false
                    duplicateName = nil
                }
                .keyboardShortcut(.cancelAction)
                Button("Sichern", action: commit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || duplicateName != nil
                    )
            }
        }
        .padding(20)
        .frame(minWidth: 300)
        .onAppear {
            name = query
            focused = true
            // Duplikat vorab erkennen: existiert dieselbe Query bereits, ist
            // Sichern direkt disabled und der Hinweis sichtbar.
            duplicateName = savedSearches.first(where: { $0.query == query })?.name
        }
    }

    private func commit() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let currentSearches = savedSearches
        if let existing = currentSearches.first(where: { $0.query == query }) {
            duplicateName = existing.name
            return
        }
        var searches = currentSearches
        searches.append(SavedSearch(id: UUID(), name: trimmed, query: query))
        savedSearches = searches
        isPresented = false
    }
}
