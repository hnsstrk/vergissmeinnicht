import SwiftUI

/// Kompakte Toolbar-Einheit für Sync-Status und -Trigger.
///
/// Zeigt (von links nach rechts):
///  - Fehler-Icon (rot, nicht-interaktiv), falls `lastError` gesetzt
///  - Sync-Button: Standard-Button ohne Custom-Padding/Capsule — identische runde
///    Hover-Fläche wie plus/checkmark/trash in der Toolbar (Karpathy 3: keine
///    adjazenten Geometrie-Eingriffe). Bei nicht-synchronisierten Änderungen ein
///    kleiner Indikator-Punkt am Icon (kein Zähler — `num_local_operations`
///    zählt rohe CRDT-Operationen, nicht User-Aktionen; die Zahl wäre
///    irreführend). Layout-neutral, kein Glyph-Springen beim Zustandswechsel.
/// Die Auto-Sync-Restzeit ist bewusst KEIN eigenes Toolbar-Element: ein
/// variabel breiter Text fügt sich nicht ins gleichmäßige Icon-Raster der
/// Toolbar ein (wiederkehrendes Spacing-Problem). Sie lebt im live tickenden
/// Status-Footer der Aufgabenliste (`RootView.syncFooter`) — Tooltips können
/// auf macOS nicht sekündlich aktualisieren.
struct SyncStatusView: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        HStack(spacing: 6) {
            // Fehler-Indikator (nicht-interaktiv, kein Button-Verhalten)
            if let error = container.lastError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .help(String(localized: "Sync-Fehler: \(error)"))
            }

            // Sync-Steuerung. Karpathy 3: Standard-Button, kein Custom-Padding, keine
            // Capsule-Background — identische Hover-Fläche wie plus/checkmark/trash.
            // Das Image bleibt in JEDEM Zustand im Layout (nur während des Syncs
            // ausgeblendet) und definiert die feste 16×16-Box; der Spinner liegt
            // als ZStack-Overlay darüber und ändert die Box nicht. Ohne das
            // bricht ein View-Tausch Image↔ProgressView die Toolbar-Reihe auf
            // (ProgressView misst sich anders, Identitätswechsel → Reflow).
            let pending = container.localChanges
            Button {
                Task { await container.syncIfConfigured() }
            } label: {
                Label {
                    Text("Sync")
                } icon: {
                    ZStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .opacity(container.isSyncing ? 0 : 1)
                        if container.isSyncing {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    .frame(width: 16, height: 16)
                    .overlay(alignment: .topTrailing) {
                        if !container.isSyncing && pending > 0 {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 6, height: 6)
                                .offset(x: 4, y: -4)
                        }
                    }
                }
            }
            .disabled(container.isSyncing)
            .help(syncHelp)
        }
    }

    /// Tooltip-Text des Sync-Buttons. Die Auto-Sync-Restzeit gehört bewusst
    /// NICHT hierher (macOS-Tooltips können nicht live ticken) — sie lebt im
    /// Status-Footer der Aufgabenliste.
    private var syncHelp: String {
        if container.isSyncing {
            return String(localized: "Synchronisiere …")
        }
        if container.localChanges > 0 {
            return String(localized: "Nicht synchronisierte Änderungen — jetzt synchronisieren")
        }
        return String(localized: "Jetzt synchronisieren")
    }
}
