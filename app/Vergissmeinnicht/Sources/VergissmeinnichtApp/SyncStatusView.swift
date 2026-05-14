import SwiftUI

/// Kompakte Toolbar-Einheit für Sync-Status und -Trigger.
///
/// Zeigt (von links nach rechts):
///  - Fehler-Icon (rot), falls `lastError` gesetzt
///  - Badge mit Anzahl lokaler, noch nicht synchronisierter Änderungen
///  - Countdown bis zum nächsten Auto-Sync (bei aktiven Timer-Modi)
///  - Sync-Button (Spinner während laufendem Sync)
struct SyncStatusView: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        HStack(spacing: 6) {
            // Fehler-Indikator
            if let error = container.lastError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .help(String(localized: "Sync-Fehler: \(error)"))
            }

            // Lokale-Änderungen-Badge
            if container.localChanges > 0 {
                Text(verbatim: "\(container.localChanges)")
                    .font(.caption2.monospacedDigit())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.18), in: Capsule())
                    .foregroundStyle(.orange)
                    .help(String(localized: "\(container.localChanges) lokale Änderung(en) noch nicht synchronisiert"))
            }

            // Countdown bis zum nächsten Auto-Sync
            if let nextSync = container.nextSyncDate {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    HStack(spacing: 3) {
                        Image(systemName: "timer")
                            .font(.caption2)
                        Text(verbatim: countdownString(to: nextSync))
                            .font(.caption2.monospacedDigit())
                    }
                    .foregroundStyle(.secondary)
                }
            }

            // Sync-Button / Spinner
            if container.isSyncing {
                ProgressView()
                    .controlSize(.small)
                    .help(String(localized: "Synchronisiere …"))
            } else {
                Button {
                    Task { await container.syncIfConfigured() }
                } label: {
                    Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                }
                .help(String(localized: "Jetzt synchronisieren"))
            }
        }
    }

    /// Formatiert die verbleibende Zeit bis `date` als `mm:ss`. Negative Werte → "0:00".
    private func countdownString(to date: Date) -> String {
        let remaining = max(0, date.timeIntervalSinceNow)
        let totalSeconds = Int(remaining)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
