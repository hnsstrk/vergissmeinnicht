import SwiftUI

/// Auswahl-Sheet: zeigt vorhandene Backups, User wählt eines und bestätigt Restore.
/// Vor dem destruktiven Schritt warnt ein Confirm-Dialog.
struct BackupRestoreSheet: View {
    @Environment(\.dismiss) private var dismiss
    let backupService: BackupService
    var onRestored: () -> Void

    @State private var backups: [URL] = []
    @State private var selected: URL?
    @State private var showConfirm: Bool = false
    @State private var errorMessage: String?

    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .medium
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Aus Backup wiederherstellen")
                .font(.headline)
            Text("Die aktuelle Replica wird durch das gewählte Backup ersetzt. Vor dem Restore wird die aktive Replica nochmal als `pre-restore`-Backup gesichert.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if backups.isEmpty {
                Text("Noch keine Backups vorhanden.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                List(backups, id: \.path, selection: $selected) { backup in
                    HStack {
                        Image(systemName: "externaldrive")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading) {
                            Text(backup.lastPathComponent)
                                .font(.system(.callout, design: .monospaced))
                            if let date = creationDate(of: backup) {
                                Text(Self.displayFormatter.string(from: date))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(byteCount(of: backup))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(backup)
                }
                .frame(minHeight: 220)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Schließen") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Wiederherstellen") {
                    showConfirm = true
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(selected == nil)
            }
        }
        .padding(20)
        .frame(width: 520, height: 420)
        .onAppear(perform: load)
        .confirmationDialog(
            Text("Replica wirklich ersetzen?"),
            isPresented: $showConfirm,
            titleVisibility: .visible
        ) {
            Button("Wiederherstellen", role: .destructive) { performRestore() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Die aktuelle Replica wird durch das gewählte Backup ersetzt. Bitte App-Neustart durchführen.")
        }
    }

    private func load() {
        do {
            backups = try backupService.listBackups()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func performRestore() {
        guard let selected else { return }
        do {
            try backupService.restore(from: selected)
            onRestored()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func creationDate(of url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.creationDateKey]).creationDate
    }

    private func byteCount(of url: URL) -> String {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}
