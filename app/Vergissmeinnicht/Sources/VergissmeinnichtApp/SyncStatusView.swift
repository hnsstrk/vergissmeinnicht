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

            // Sync-Steuerung. JEDER Zustand nutzt dieselbe gepolsterte
            // HStack-Box (Padding 7/3) — das Sync-Symbol sitzt immer an
            // derselben Position, springt also nicht, wenn Zähler/Spinner
            // erscheinen oder verschwinden. Nur Capsule-Füllung, Zähler und
            // Spinner-vs-Symbol wechseln; der Zähler wächst nach rechts.
            // Kein `.buttonStyle(.plain)` (Toolbar-Spacing bleibt), kein
            // `.tint` (kein Blau im Leer-Zustand) — die beiden früheren
            // Fixes bleiben (Karpathy 3: nur die Spacing-Konstanz).
            let pending = container.localChanges
            if container.isSyncing {
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.small)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .help(String(localized: "Synchronisiere …"))
            } else {
                Button {
                    Task { await container.syncIfConfigured() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        if pending > 0 {
                            Text(verbatim: "\(pending)")
                                .font(.caption2.monospacedDigit())
                        }
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background {
                        if pending > 0 {
                            Capsule().fill(Color.orange.opacity(0.18))
                        }
                    }
                    .foregroundStyle(pending > 0 ? AnyShapeStyle(.orange) : AnyShapeStyle(.primary))
                }
                .accessibilityLabel(Text("Sync"))
                .help(pending > 0
                      ? String(localized: "\(pending) lokale Änderung(en) — jetzt synchronisieren")
                      : String(localized: "Jetzt synchronisieren"))
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
