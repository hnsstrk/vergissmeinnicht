import SwiftUI
import VergissmeinnichtKit

/// Detail-Toolbar der Hauptliste, aus `RootView` extrahiert (#19).
///
/// Mail-Stil: Sort / Plus / Erledigt / Löschen / Sync zentral (principal),
/// Bookmark rechts (primaryAction) — nur bei aktiver Suche sichtbar.
///
/// Toolbar Icon Style (CLAUDE.md): jeder Eintrag ist ein einzelnes SF-Symbol in
/// einem Standard-`Button`/`Menu`, das Sort-`Menu` trägt `.menuIndicator(.hidden)`,
/// keine custom-gepaddeten HStacks. State (`showSaveSearchPopover`, Sortier-Bindings,
/// `savedSearchesRaw`) lebt weiter in `RootView` und wird hereingereicht; die
/// Aktionen kommen als Closures.
struct RootViewToolbar: ToolbarContent {
    @Bindable var vm: TaskListViewModel
    @Binding var showSaveSearchPopover: Bool
    @Binding var savedSearchesRaw: String
    /// Spiegeln die `@AppStorage`-Defaults in `RootView` (Sortier-Persistenz).
    @Binding var defaultSortRaw: String
    @Binding var sortAscending: Bool

    let onNewTask: () -> Void
    let onMarkDoneSelection: () -> Void
    let onRequestDelete: (Set<String>) -> Void

    @ToolbarContentBuilder
    var body: some ToolbarContent {
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
                onNewTask()
            } label: {
                Label("Neue Aufgabe", systemImage: "plus")
            }
            .help("Neue Aufgabe (Cmd+N)")

            Button {
                onMarkDoneSelection()
            } label: {
                Label("Erledigt", systemImage: "checkmark.circle")
            }
            .disabled(vm.selectedUuids.isEmpty)
            .help("Ausgewählte Aufgabe(n) als erledigt markieren (Cmd+D)")

            Button {
                onRequestDelete(vm.selectedUuids)
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
}

// MARK: - Suche sichern Popover

/// Kleines Popover zum Benennen und Speichern einer Suchanfrage.
/// Karpathy 2: eigener FocusState lebt hier, damit RootView schlank bleibt.
struct SaveSearchPopoverView: View {
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
