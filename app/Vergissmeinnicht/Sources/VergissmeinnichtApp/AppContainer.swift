import Foundation
import VergissmeinnichtKit

/// Beobachtbarer Wrapper um den FFI-`TaskStore`.
///
/// Hält die Replica im sandboxed App-Container offen
/// (`~/Library/Containers/de.hnsstrk.vergissmeinnicht/Data/Library/Application Support/vergissmeinnicht/replica/`)
/// und stellt UI-Code eine `pending`-Liste zur Verfügung. FFI-Calls laufen
/// auf einem detached Task, damit der MainActor frei bleibt.
@MainActor
@Observable
final class AppContainer {
    private(set) var pending: [TaskInfo] = []
    private(set) var lastError: String?
    private(set) var isSyncing: Bool = false
    private(set) var lastSyncDate: Date?

    private let store: TaskStore

    init() throws {
        let url = try Self.replicaURL()
        self.store = try TaskStore(dbPath: url.path)
    }

    /// Lädt die Pending-Liste aus dem Store. FFI-Aufruf läuft off-MainActor.
    func refresh() async {
        let store = self.store
        do {
            let pending = try await Task.detached(priority: .userInitiated) {
                try store.listPending()
            }.value
            self.pending = pending
            self.lastError = nil
        } catch {
            self.lastError = userMessage(for: error)
        }
    }

    /// Legt einen neuen Task an. Persistiert in dieser Welle nur die Description —
    /// Tags/Project/Due/Priority werden in `QuickCaptureSheet` als Vorschau angezeigt,
    /// aber nicht über die FFI gespeichert (FFI exportiert die Felder noch nicht).
    /// Rückgabe: `true` bei erfolgreicher Mutation, `false` falls die FFI geworfen hat
    /// (in dem Fall ist `lastError` gesetzt). UI nutzt das Resultat, um Sheets nur
    /// bei Erfolg zu schließen oder Eingaben zu leeren.
    @discardableResult
    func addTask(description: String) async -> Bool {
        await mutate { store in
            _ = try store.addTask(description: description)
        }
    }

    /// Markiert den Task als erledigt (entspricht `task done` in Taskwarrior).
    @discardableResult
    func markDone(uuid: String) async -> Bool {
        await mutate { store in
            try store.markDone(uuid: uuid)
        }
    }

    /// Ändert die Description eines bestehenden Tasks.
    @discardableResult
    func modifyDescription(uuid: String, newDescription: String) async -> Bool {
        await mutate { store in
            try store.modifyDescription(uuid: uuid, newDescription: newDescription)
        }
    }

    /// Löscht einen Task. Bewusst ohne Confirm-Dialog (Karpathy 2: Simplicity);
    /// kann später per `.alert` nachgerüstet werden.
    @discardableResult
    func deleteTask(uuid: String) async -> Bool {
        await mutate { store in
            try store.deleteTask(uuid: uuid)
        }
    }

    /// Hängt eine Annotation an einen Task an.
    @discardableResult
    func addAnnotation(uuid: String, annotation: String) async -> Bool {
        await mutate { store in
            try store.addAnnotation(uuid: uuid, annotation: annotation)
        }
    }

    /// Führt eine FFI-Mutation off-MainActor aus und refresht anschließend
    /// `pending`, damit die UI nicht auf veralteten Daten arbeitet.
    /// Rückgabe: `true` falls die Mutation ohne Fehler durchlief, `false` sonst.
    /// Bei Fehler wird `lastError` über `userMessage(for:)` gesetzt; ein
    /// erfolgreicher Refresh setzt `lastError` selbst zurück.
    private func mutate(_ operation: @Sendable @escaping (TaskStore) throws -> Void) async -> Bool {
        let store = self.store
        do {
            try await Task.detached(priority: .userInitiated) {
                try operation(store)
            }.value
        } catch {
            self.lastError = userMessage(for: error)
            return false
        }
        await refresh()
        return true
    }

    /// Mappt FFI-Fehler auf knappe deutsche User-Strings für `lastError`.
    /// Ohne diesen Mapping würde `String(describing:)` die technische
    /// Reflection-Repräsentation der `VmError`-Cases zeigen
    /// (`VmError.Storage(msg: "…")`), was in der UI unbrauchbar ist.
    private func userMessage(for error: Error) -> String {
        if let vm = error as? VmError {
            switch vm {
            case .Storage(let msg):    return "Speicherfehler: \(msg)"
            case .Conversion(let msg): return "Eingabefehler: \(msg)"
            case .NotFound:            return "Aufgabe nicht gefunden"
            case .Sync(let msg):       return "Sync-Fehler: \(msg)"
            case .Internal:            return "Interner Fehler"
            }
        }
        return error.localizedDescription
    }

    /// Synchronisiert die Replica mit dem Server. FFI-Call läuft off-MainActor.
    func sync(serverUrl: String, clientId: String, encryptionSecret: String) async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        let store = self.store
        do {
            try await Task.detached(priority: .userInitiated) {
                try store.sync(serverUrl: serverUrl, clientId: clientId, encryptionSecret: encryptionSecret)
            }.value
            await refresh()
            lastSyncDate = Date()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Liest Credentials aus dem Keychain und ruft `sync()` — no-op falls nicht konfiguriert.
    func syncIfConfigured() async {
        guard let serverUrl = KeychainStore.load(key: .serverUrl), !serverUrl.isEmpty,
              let clientId = KeychainStore.load(key: .clientId), !clientId.isEmpty,
              let secret = KeychainStore.load(key: .encryptionSecret), !secret.isEmpty
        else { return }
        await sync(serverUrl: serverUrl, clientId: clientId, encryptionSecret: secret)
    }

    /// Pfad zum Replica-Verzeichnis im App-Container. Im Sandbox liefert
    /// `applicationSupportDirectory` automatisch den Container-Pfad.
    private static func replicaURL() throws -> URL {
        let fm = FileManager.default
        let appSupport = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let replicaDir = appSupport
            .appendingPathComponent("vergissmeinnicht", isDirectory: true)
            .appendingPathComponent("replica", isDirectory: true)
        try fm.createDirectory(at: replicaDir, withIntermediateDirectories: true)
        return replicaDir
    }
}
