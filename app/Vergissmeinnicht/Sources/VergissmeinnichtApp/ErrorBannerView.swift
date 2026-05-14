import SwiftUI

/// Banner für Fehler-Meldungen am unteren Rand des Hauptfensters.
///
/// Auto-Dismiss nach 6 Sekunden (cancelbar wenn neuer Fehler kommt).
/// Close-Button per Klick. „Erneut versuchen" wird nur eingeblendet, wenn der
/// Retry-Callback gesetzt ist (typisch bei Sync-Fehlern).
struct ErrorBannerView: View {
    let message: String
    var onRetry: (() -> Void)?
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if let onRetry {
                Button("Erneut versuchen") { onRetry() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Schließen")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.orange.opacity(0.4), lineWidth: 1)
        )
        .padding(12)
    }
}
