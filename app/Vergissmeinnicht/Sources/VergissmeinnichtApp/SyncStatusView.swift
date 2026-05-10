import SwiftUI

/// Kompakte Toolbar-Einheit für Sync-Status und -Trigger.
///
/// Zeigt das letzte Sync-Datum als Relative-Date, einen Fehler-Indikator
/// und den Sync-Button. Wird in der Sidebar-Toolbar von `RootView` eingeblendet.
struct SyncStatusView: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        HStack(spacing: 6) {
            if let error = container.lastError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .help("Sync-Fehler: \(error)")
            }
            if let date = container.lastSyncDate {
                Text(date, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button {
                Task { await container.syncIfConfigured() }
            } label: {
                Label("Sync", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(container.isSyncing)
            .help("Jetzt synchronisieren")
        }
    }
}
