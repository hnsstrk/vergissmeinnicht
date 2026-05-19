import SwiftUI

/// Kompakte Toolbar-Einheit für Sync-Status und -Trigger.
///
/// Zeigt (von links nach rechts):
///  - Fehler-Icon (rot), falls `lastError` gesetzt
///  - Countdown bis zum nächsten Auto-Sync (bei aktiven Timer-Modi)
///  - Sync-Button (Spinner während laufendem Sync); bei lokalen, noch nicht
///    synchronisierten Änderungen rechts vom Symbol ein Zähler, der sich die
///    Hintergrund-Capsule mit dem Sync-Symbol teilt
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

            // Sync-Button / Spinner. Der Lokale-Änderungen-Zähler sitzt rechts
            // vom Sync-Symbol und teilt sich dessen Hintergrund-Capsule —
            // sonst klebt er am Papierkorb-Button und liest sich wie eine
            // Papierkorb-Anzahl (Karpathy 3: nur diese Layout-Korrektur,
            // Fehler-/Countdown-Teile bleiben unangetastet).
            if container.isSyncing {
                ProgressView()
                    .controlSize(.small)
                    .help(String(localized: "Synchronisiere …"))
            } else if container.localChanges > 0 {
                // Mit anstehenden Änderungen: Zähler rechts vom Sync-Symbol,
                // beide in einer gemeinsamen orangen Capsule.
                let pending = container.localChanges
                Button {
                    Task { await container.syncIfConfigured() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text(verbatim: "\(pending)")
                            .font(.caption2.monospacedDigit())
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.18), in: Capsule())
                    .foregroundStyle(.orange)
                }
                .accessibilityLabel(Text("Sync"))
                .help(String(localized: "\(pending) lokale Änderung(en) — jetzt synchronisieren"))
            } else {
                // Ohne Änderungen: unveränderter Original-Sync-Button —
                // Standard-Toolbar-Optik, gleiche Darstellung wie +/✓/Papierkorb.
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
