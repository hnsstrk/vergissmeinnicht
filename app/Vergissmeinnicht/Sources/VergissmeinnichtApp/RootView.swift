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

/// Inhalts-Modus des Hauptbereichs: die gewohnte Liste oder der Monats-Kalender
/// (#11). Eigener Modus statt Sidebar-Filter — die zentrale `SidebarFilter`-Logik
/// bleibt unberührt (Karpathy 3).
enum ContentMode: Equatable {
    case list
    /// Optionaler Fokus-Tag bestimmt den initial gezeigten Monat.
    case calendar(Date?)
}

struct RootView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.openWindow) private var openWindow
    @State private var viewModel = TaskListViewModel()
    @State private var contentMode: ContentMode = .list
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
    @AppStorage(AppSettingsKey.forecastConfigs) private var forecastConfigsRaw: String = "{}"

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
            switch contentMode {
            case .calendar(let focus):
                CalendarView(
                    tasks: container.tasks,
                    focusDate: focus,
                    onOpenDetail: openDetailWindow
                )
                .navigationTitle(Text("Kalender"))
            case .list:
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
                .safeAreaInset(edge: .top, spacing: 0) { forecastStrip }
                .safeAreaInset(edge: .bottom) { syncFooter }
                .navigationTitle(filterTitle)
                .searchable(text: $vm.searchQuery, prompt: Text("Suchen…"))
                .toolbar {
                    RootViewToolbar(
                        vm: vm,
                        showSaveSearchPopover: $showSaveSearchPopover,
                        savedSearchesRaw: $savedSearchesRaw,
                        defaultSortRaw: $defaultSortRaw,
                        sortAscending: $sortAscending,
                        onNewTask: { showQuickCapture = true },
                        onMarkDoneSelection: { handleMarkDoneSelection() },
                        onRequestDelete: { requestDelete(uuids: $0) }
                    )
                }
            }
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
                contentMode = .list
                viewModel.activeFilter = filter
            case .showCalendar(let focus):
                contentMode = .calendar(focus)
            }
        }
        .onChange(of: viewModel.activeFilter) { _, _ in
            // Sidebar-Auswahl führt immer zurück in den Listen-Modus (analog zu
            // den Berichten). Hinweis: Re-Klick auf dieselbe bereits aktive Zeile
            // ändert den Wert nicht und feuert daher nicht — der Kalender ist über
            // jede andere Zeile bzw. erneuten Menü-Aufruf verlassbar (Simplicity).
            if case .calendar = contentMode { contentMode = .list }
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

    // MARK: - Vorschau (Follow-up #11)

    /// Vorschau über der Liste: aus / kompakter Wochen-Streifen / tagesgruppierte
    /// Agenda — gesteuert über die PRO-PERSPEKTIVE-Konfiguration (`forecastConfigs`).
    /// Die Konfiguration der AKTIVEN Perspektive (`ForecastPerspective.init(for:)`)
    /// bestimmt Darstellung, Zeitraum, Kappung und KW; `display == .off` (oder eine
    /// Perspektive ohne Mapping, z. B. Abhängigkeits-Berichte) blendet die Vorschau
    /// aus — dann auch kein Trenner. Nur im Listen-Modus (im Kalender redundant).
    /// Der `Divider` setzt eine klare Grenze zur Liste.
    @ViewBuilder
    private var forecastStrip: some View {
        if let perspective = ForecastPerspective(for: viewModel.activeFilter) {
            let config = ForecastConfig.resolve(perspective, from: forecastConfigsRaw)
            if config.display != .off {
                VStack(spacing: 0) {
                    switch config.display {
                    case .off:
                        EmptyView()
                    case .compact:
                        ForecastStripView(
                            tasks: container.tasks,
                            range: config.range,
                            showCalendarWeeks: config.showCalendarWeeks
                        ) { day in
                            contentMode = .calendar(day)
                        }
                    case .agenda:
                        ForecastAgendaView(
                            tasks: container.tasks,
                            range: config.range,
                            maxPerDay: config.maxPerDay,
                            showCalendarWeeks: config.showCalendarWeeks,
                            onOpenDetail: openDetailWindow
                        )
                    }
                    Divider()
                }
                // Subtiler Schatten an der Unterkante: hebt die Vorschau als eigene
                // Schicht von der Liste ab, statt nahtlos überzugehen.
                .shadow(color: .black.opacity(0.12), radius: 3, x: 0, y: 1)
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

    /// Dispatcher für Aktionen über eine Mehrfach-Selektion (#19). Dünn:
    /// die Batch-Schleifen + Teilfehler-Report leben in `AppContainer` (#5).
    private var bulk: BulkActions { BulkActions(container: container) }

    private func handleMarkDoneSelection() {
        bulk.markDone(viewModel.selectedUuids)
    }

    private func requestDelete(uuids: Set<String>) {
        guard !uuids.isEmpty else { return }
        pendingDelete = uuids
    }

    private func performDelete() {
        let uuids = pendingDelete
        pendingDelete.removeAll()
        bulk.delete(uuids)
    }

    private func handleSnooze(_ uuid: String, _ wait: Int64?) {
        Task { await container.setWait(uuid: uuid, wait: wait) }
    }

    private func handleAssignProject(_ uuids: Set<String>, _ project: String?) {
        bulk.assignProject(uuids, project)
    }

    private func handleAddTag(_ uuids: Set<String>, _ tag: String) {
        bulk.addTag(uuids, tag)
    }

    private func handleSetPriority(_ uuids: Set<String>, _ priority: String?) {
        bulk.setPriority(uuids, priority)
    }

    private func handleSetDue(_ uuids: Set<String>, _ due: Int64?) {
        bulk.setDue(uuids, due)
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
