import SwiftUI
import VergissmeinnichtKit

/// Read-Pfad-Root: `NavigationSplitView` mit Sidebar (FilterBar + TaskListView)
/// und Detail-Pane.
///
/// `AppContainer` liefert die rohe `pending`-Liste; das `TaskListViewModel`
/// hält UI-State (Search-Query, Selection) und liefert die gefilterte/sortierte
/// Sicht. Refresh-Button im Toolbar lädt explizit neu, `.task` lädt initial.
struct RootView: View {
    @Environment(AppContainer.self) private var container
    @State private var viewModel = TaskListViewModel()

    var body: some View {
        @Bindable var vm = viewModel
        let visible = viewModel.visibleTasks(from: container.pending)

        NavigationSplitView {
            VStack(spacing: 0) {
                FilterBar(searchQuery: $vm.searchQuery)
                Divider()
                TaskListView(tasks: visible, selectedUuid: $vm.selectedUuid)
            }
            .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 400)
            .toolbar {
                ToolbarItem {
                    Button {
                        Task { await container.refresh() }
                    } label: {
                        Label("Aktualisieren", systemImage: "arrow.clockwise")
                    }
                    .help("Pending-Liste neu laden")
                }
                ToolbarItem {
                    SyncStatusView()
                }
            }
        } detail: {
            DetailView(task: selectedTask)
        }
        .frame(minWidth: 640, minHeight: 360)
        .task {
            await container.refresh()
            await container.syncIfConfigured()
        }
        .onChange(of: container.pending) { _, newPending in
            // Stale-Selection bereinigen, falls die UUID nach einem Refresh
            // nicht mehr in der Liste enthalten ist.
            if let uuid = viewModel.selectedUuid,
               !newPending.contains(where: { $0.uuid == uuid }) {
                viewModel.selectedUuid = nil
            }
        }
        .overlay(alignment: .bottom) {
            if let error = container.lastError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                    .padding(8)
            }
        }
    }

    private var selectedTask: TaskInfo? {
        guard let uuid = viewModel.selectedUuid else { return nil }
        return container.pending.first { $0.uuid == uuid }
    }
}
