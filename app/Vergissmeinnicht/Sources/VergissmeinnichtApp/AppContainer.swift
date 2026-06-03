import Foundation
import VergissmeinnichtKit

/// Beobachtbarer Wrapper um den FFI-`TaskStore`.
///
/// Hält die Replica im sandboxed App-Container offen
/// (`~/Library/Containers/de.hnsstrk.vergissmeinnicht/Data/Library/Application Support/vergissmeinnicht/replica/`)
/// und stellt UI-Code eine `tasks`-Liste mit allen Pending- und Completed-Tasks
/// zur Verfügung. Sidebar/ViewModel filtern clientseitig nach Status. FFI-Calls
/// laufen auf einem detached Task, damit der MainActor frei bleibt.
@MainActor
@Observable
final class AppContainer {
    /// Alle Tasks (Pending + Completed). Deleted bleiben ausgeschlossen.
    private(set) var tasks: [TaskInfo] = []
    /// Backwards-Compat-Alias für UI-Code, der nur die Pending-Sicht braucht.
    var pending: [TaskInfo] { tasks.filter { $0.status == .pending } }
    private(set) var lastError: String?

    /// Letzten Fehler verwerfen (vom Banner-Close-Button oder Auto-Dismiss).
    func clearError() {
        lastError = nil
    }
    private(set) var isSyncing: Bool = false
    private(set) var lastSyncDate: Date?
    /// Anzahl lokaler Operationen, die noch nicht synchronisiert wurden.
    private(set) var localChanges: UInt64 = 0
    /// Nächster geplanter Auto-Sync-Zeitpunkt (nil wenn kein Timer aktiv).
    private(set) var nextSyncDate: Date?

    private let store: TaskStore
    let backupService: BackupService

    /// Aktuell aktiver Auto-Sync-Modus — vom View gesetzt via `configureAutoSync`.
    private var currentSyncMode: AutoSyncMode = .manual
    /// Task-Referenz für den laufenden Auto-Sync-Timer. Wird bei Neukonfiguration gecancelt.
    private var autoSyncTask: Task<Void, Never>?

    init() throws {
        let url = try Self.replicaURL()
        self.store = try TaskStore(dbPath: url.path)
        self.backupService = try BackupService(replicaURL: url, backupsURL: nil)

        // Sanity-Check: kann der Store die Replica lesen? Beim Listing eines
        // leeren Working-Sets ist die Operation Read-only; ein Fehler hier weist
        // auf eine kaputte Replica-Datei oder Permissions-Problem hin. Wir
        // logen den Fehler nur — die UI bekommt ihn beim ersten `refresh`.
        do {
            _ = try self.store.listTasks(includeCompleted: false)
        } catch {
            #if DEBUG
            print("⚠️ Vergissmeinnicht: Sanity-Check listTasks() failed: \(error)")
            #endif
        }
    }

    /// Monoton steigender Token, der überlappende `refresh()`-Läufe ordnet. Nur das
    /// zuletzt gestartete `refresh()` darf `tasks` publizieren — sonst könnte ein
    /// langsamerer, früher gestarteter Lauf einen neueren Stand überschreiben
    /// (last-completer-wins statt last-issued-wins).
    private var refreshGeneration = 0
    /// Gleicher Schutz wie `refreshGeneration`, aber für den `localChanges`-Counter:
    /// `refreshLocalChanges()` läuft ebenfalls über einen detached Read und kann
    /// überlappen — nur der zuletzt gestartete Lauf darf publizieren.
    private var localChangesGeneration = 0

    /// Lädt die volle Task-Liste (Pending + Completed) aus dem Store.
    func refresh() async {
        refreshGeneration += 1
        let token = refreshGeneration
        let store = self.store
        do {
            let all = try await Task.detached(priority: .userInitiated) {
                try store.listTasks(includeCompleted: true)
            }.value
            // Nur publizieren, wenn inzwischen kein neuerer Refresh gestartet wurde.
            guard token == refreshGeneration else { return }
            self.tasks = all
            self.lastError = nil
        } catch {
            self.lastError = userMessage(for: error)
        }
        await refreshLocalChanges()
    }

    /// Legt einen neuen Task an. Gibt die UUID des angelegten Tasks zurück
    /// (oder `nil` bei FFI-Fehler — `lastError` ist dann gesetzt).
    @discardableResult
    func addTask(description: String) async -> String? {
        await mutateReturning { store in
            try store.addTask(description: description)
        }
    }

    /// Legt einen neuen Task mit Metadaten an: project (raw), User-Tags, due (Unix-Sekunden).
    /// Gibt die UUID des angelegten Tasks zurück.
    @discardableResult
    func addTask(description: String, project: String?, tags: [String], due: Int64?) async -> String? {
        await mutateReturning { store in
            try store.addTaskFull(
                description: description,
                project: project,
                tags: tags,
                due: due
            )
        }
    }

    /// Reparatur-Lauf für Legacy-Tasks: Tasks, deren Description noch `+tag` / `project:foo`
    /// / `due:bar` als Text enthält und die selbst noch keine Properties haben, werden
    /// nachgezogen — Description wird auf den reinen Text zurückgeschnitten und Metadaten
    /// als Properties gesetzt.
    ///
    /// Rückgabe: Anzahl der reparierten Tasks (0 ist normal, wenn nichts zu tun ist).
    /// Tasks, die bereits Metadaten haben, bleiben unangetastet — Karpathy 3.
    @discardableResult
    func repairLegacyTasks() async -> Int {
        let store = self.store
        let snapshot = self.pending
        var repaired = 0
        for task in snapshot {
            let preview = QuickCaptureParser.parse(task.description)
            // Nur reparieren, wenn (a) die Description tatsächlich Metadaten-Text enthält
            // und (b) die FFI-Properties dieser Task noch leer sind. Damit umgehen wir,
            // dass ein bereits korrekt getaggter Task mit "+foo" in der Description-Prosa
            // versehentlich umgeschrieben wird.
            guard preview.hasMetadata,
                  task.project == nil,
                  task.tags.isEmpty,
                  task.due == nil
            else { continue }

            let newDescription = preview.description.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !newDescription.isEmpty else { continue }
            let dueTs = preview.due.flatMap { DueDateParser.parse($0) }

            do {
                try await Task.detached(priority: .userInitiated) { [preview] in
                    try store.updateTaskMetadata(
                        uuid: task.uuid,
                        description: newDescription,
                        project: preview.project,
                        tags: preview.tags,
                        due: dueTs
                    )
                }.value
                repaired += 1
            } catch {
                self.lastError = userMessage(for: error)
                break
            }
        }
        if repaired > 0 {
            await refresh()
        }
        return repaired
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

    /// Entfernt die Annotation mit gegebenem Entry-Zeitstempel (Unix-Sekunden).
    @discardableResult
    func removeAnnotation(uuid: String, entry: Int64) async -> Bool {
        await mutate { store in
            try store.removeAnnotation(uuid: uuid, entry: entry)
        }
    }

    /// Setzt das Projekt; `nil` oder leerer String entfernen es.
    @discardableResult
    func setProject(uuid: String, project: String?) async -> Bool {
        await mutate { store in
            try store.setProject(uuid: uuid, project: project)
        }
    }

    /// Setzt die Fälligkeit (Unix-Sekunden); `nil` entfernt sie.
    @discardableResult
    func setDue(uuid: String, due: Int64?) async -> Bool {
        await mutate { store in
            try store.setDue(uuid: uuid, due: due)
        }
    }

    /// Setzt die Priorität (`H`/`M`/`L` oder Custom); `nil` oder leerer String entfernen sie.
    @discardableResult
    func setPriority(uuid: String, priority: String?) async -> Bool {
        await mutate { store in
            try store.setPriority(uuid: uuid, priority: priority)
        }
    }

    /// Fügt einen Tag hinzu (idempotent).
    @discardableResult
    func addTag(uuid: String, tag: String) async -> Bool {
        await mutate { store in
            try store.addTag(uuid: uuid, tag: tag)
        }
    }

    /// Entfernt einen Tag (idempotent).
    @discardableResult
    func removeTag(uuid: String, tag: String) async -> Bool {
        await mutate { store in
            try store.removeTag(uuid: uuid, tag: tag)
        }
    }

    /// Fügt eine Abhängigkeit hinzu: `uuid` hängt fortan von `dependsOn` ab
    /// (native Taskwarrior `depends`). Idempotent.
    @discardableResult
    func addDependency(uuid: String, dependsOn: String) async -> Bool {
        await mutate { store in
            try store.addDependency(uuid: uuid, dependsOnUuid: dependsOn)
        }
    }

    /// Entfernt eine Abhängigkeit (idempotent).
    @discardableResult
    func removeDependency(uuid: String, dependsOn: String) async -> Bool {
        await mutate { store in
            try store.removeDependency(uuid: uuid, dependsOnUuid: dependsOn)
        }
    }

    /// Reaktiviert einen erledigten Task (Status zurück auf Pending).
    @discardableResult
    func reactivate(uuid: String) async -> Bool {
        await mutate { store in
            try store.reactivate(uuid: uuid)
        }
    }

    /// Setzt das Wait-Property (Snooze) auf einen Unix-Timestamp; `nil` entfernt es.
    @discardableResult
    func setWait(uuid: String, wait: Int64?) async -> Bool {
        await mutate { store in
            try store.setWait(uuid: uuid, wait: wait)
        }
    }

    /// Setzt das Recur-Property; `nil` oder leerer String entfernen es.
    @discardableResult
    func setRecur(uuid: String, recur: String?) async -> Bool {
        await mutate { store in
            try store.setRecur(uuid: uuid, recur: recur)
        }
    }

    /// Setzt das Scheduled-Property (Start-Datum, Unix-Sekunden). `nil` entfernt es.
    @discardableResult
    func setScheduled(uuid: String, scheduled: Int64?) async -> Bool {
        await mutate { store in
            try store.setScheduled(uuid: uuid, scheduled: scheduled)
        }
    }

    /// Benennt ein Projekt global um — alle geladenen Tasks (Pending + Completed) mit
    /// `project == oldName` bekommen `newName`. Leerer newName entspricht "löschen".
    @discardableResult
    func renameProject(from oldName: String, to newName: String) async -> Int {
        let target = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = self.tasks.filter { $0.project == oldName }
        var count = 0
        // Als Batch: ein einziger Refresh am Ende statt N (Karpathy 2). `setProject`
        // unterdrückt dank `withBatch` seine per-Op-Refreshes.
        await withBatch {
            for task in candidates {
                let ok = await setProject(uuid: task.uuid, project: target.isEmpty ? nil : target)
                if ok { count += 1 }
            }
        }
        // Teilfehler sichtbar machen: schlugen einzelne Tasks fehl, hinterließe das einen
        // halb-umbenannten Stand. NACH `withBatch` setzen, sonst räumt dessen
        // abschließender Refresh `lastError` wieder ab.
        if count < candidates.count {
            self.lastError = String(localized: "Projekt nur teilweise umbenannt (\(count) von \(candidates.count)).")
        }
        return count
    }

    /// Entfernt das Projekt aus allen Tasks (set_project = nil).
    @discardableResult
    func clearProject(name: String) async -> Int {
        return await renameProject(from: name, to: "")
    }

    /// Benennt einen Tag global um — alle geladenen Tasks (Pending + Completed) mit
    /// `oldName` bekommen `newName` hinzugefügt und verlieren `oldName` (sofern das
    /// Entfernen gelingt). Leerer newName entspricht "nur entfernen".
    @discardableResult
    func renameTag(from oldName: String, to newName: String) async -> Int {
        let target = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = self.tasks.filter { $0.tags.contains(oldName) }
        var count = 0
        // Als Batch: ein Refresh am Ende statt zwei pro Task (Karpathy 2).
        await withBatch {
            for task in candidates {
                // Datenintegrität: den alten Tag nur entfernen, wenn der neue zuvor
                // erfolgreich gesetzt wurde — sonst bliebe der Task ohne beide Tags zurück.
                if !target.isEmpty {
                    guard await addTag(uuid: task.uuid, tag: target) else { continue }
                }
                let ok = await removeTag(uuid: task.uuid, tag: oldName)
                if ok { count += 1 }
            }
        }
        // NACH `withBatch` setzen (siehe `renameProject`).
        if count < candidates.count {
            self.lastError = String(localized: "Tag nur teilweise umbenannt (\(count) von \(candidates.count)).")
        }
        return count
    }

    /// Entfernt einen Tag aus allen Tasks.
    @discardableResult
    func clearTag(name: String) async -> Int {
        return await renameTag(from: name, to: "")
    }

    /// Markiert einen Task als erledigt. Hat der Task ein `recur`-Property und
    /// ein `due`-Datum, wird zusätzlich in **derselben Operations-Batch** (atomar)
    /// eine neue Pending-Instanz mit `due_neu = due_alt + intervall(recur)` angelegt.
    @discardableResult
    func markDoneWithRecurrence(uuid: String, calendar: Calendar = .current) async -> Bool {
        guard let task = self.tasks.first(where: { $0.uuid == uuid }) else { return false }
        let newDue: Int64? = {
            guard let raw = task.recur, !raw.isEmpty,
                  let delta = RecurParser.components(from: raw),
                  let oldDue = task.due
            else { return nil }
            let oldDate = Date(timeIntervalSince1970: TimeInterval(oldDue))
            guard let newDate = calendar.date(byAdding: delta, to: oldDate) else { return nil }
            return Int64(newDate.timeIntervalSince1970)
        }()

        let store = self.store
        do {
            _ = try await Task.detached(priority: .userInitiated) { [task] in
                try store.markDoneWithFollowup(
                    uuid: uuid,
                    newDue: newDue,
                    recur: task.recur,
                    priority: task.priority,
                    project: task.project,
                    tags: task.tags,
                    description: task.description
                )
            }.value
            if !isBatching {
                await refresh()
            }
            return true
        } catch {
            self.lastError = userMessage(for: error)
            return false
        }
    }

    /// Aktualisiert mehrere Metadaten-Felder eines Tasks atomar — vom Detail-Editor genutzt.
    @discardableResult
    func updateMetadata(
        uuid: String,
        description: String,
        project: String?,
        tags: [String],
        due: Int64?
    ) async -> Bool {
        await mutate { store in
            try store.updateTaskMetadata(
                uuid: uuid,
                description: description,
                project: project,
                tags: tags,
                due: due
            )
        }
    }

    /// Verschachtelungs-Tiefe laufender Batches. Solange `> 0`, überspringen einzelne
    /// Mutationen ihren per-Op-`refresh()` (und den Immediate-Sync) — der äußerste
    /// `withBatch`-Aufruf refresht genau einmal am Ende. Ein Zähler statt eines Bool,
    /// damit überlappende/verschachtelte `withBatch`-Aufrufe die Unterdrückung nicht
    /// vorzeitig aufheben. Verhindert N Re-Renders und N FFI-`listTasks` bei
    /// Mehrfach-Selektionen.
    private var batchDepth = 0
    private var isBatching: Bool { batchDepth > 0 }

    /// Führt mehrere Mutationen als Batch aus: per-Op-Refresh wird unterdrückt, danach
    /// folgt ein einziger Refresh (plus Immediate-Sync, falls aktiv). Vom RootView für
    /// Aktionen über eine Mehrfach-Selektion genutzt. Reentrant: erst wenn der äußerste
    /// Batch endet (`batchDepth == 0`), wird refresht.
    func withBatch(_ body: () async -> Void) async {
        batchDepth += 1
        await body()
        batchDepth -= 1
        guard batchDepth == 0 else { return }
        await refresh()
        if currentSyncMode == .immediate {
            Task { await syncIfConfigured() }
        }
    }

    /// Führt eine FFI-Mutation off-MainActor aus und refresht anschließend.
    /// Rückgabe: `true` falls Erfolg.
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
        guard !isBatching else { return true }
        await refresh()
        if currentSyncMode == .immediate {
            Task { await syncIfConfigured() }
        }
        return true
    }

    /// Wie `mutate`, aber gibt den Rückgabewert der Operation durch (z.B. die UUID
    /// einer neu angelegten Task). Bei Fehler: `nil` und `lastError` gesetzt.
    private func mutateReturning<T: Sendable>(
        _ operation: @Sendable @escaping (TaskStore) throws -> T
    ) async -> T? {
        let store = self.store
        let result: T
        do {
            result = try await Task.detached(priority: .userInitiated) {
                try operation(store)
            }.value
        } catch {
            self.lastError = userMessage(for: error)
            return nil
        }
        guard !isBatching else { return result }
        await refresh()
        if currentSyncMode == .immediate {
            Task { await syncIfConfigured() }
        }
        return result
    }

    /// Mappt FFI-Fehler auf knappe User-Strings für `lastError`.
    /// Ohne diesen Mapping würde `String(describing:)` die technische
    /// Reflection-Repräsentation der `VmError`-Cases zeigen
    /// (`VmError.Storage(msg: "…")`), was in der UI unbrauchbar ist.
    private func userMessage(for error: Error) -> String {
        if let vm = error as? VmError {
            switch vm {
            case .Storage(let msg):    return String(localized: "Speicherfehler: \(msg)")
            case .Conversion(let msg): return String(localized: "Eingabefehler: \(msg)")
            case .NotFound:            return String(localized: "Aufgabe nicht gefunden")
            case .Sync(let msg):       return String(localized: "Sync-Fehler: \(msg)")
            case .Internal:            return String(localized: "Interner Fehler")
            }
        }
        return error.localizedDescription
    }

    /// Synchronisiert die Replica mit dem Server. **Vor jedem Sync** wird ein
    /// automatisches Backup angelegt (rotierend, Default 10 Stand) — damit ein
    /// kaputter Sync nicht zu Datenverlust führt. FFI-Call läuft off-MainActor.
    func sync(serverUrl: String, clientId: String, encryptionSecret: String) async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        // Pre-Sync-Backup. Fehler beim Backup soll Sync nicht blockieren —
        // wir kommunizieren ihn nur in lastError.
        let backupService = self.backupService
        do {
            _ = try await Task.detached(priority: .userInitiated) {
                try backupService.createBackup(reason: "pre-sync")
            }.value
        } catch {
            self.lastError = String(localized: "Backup vor Sync fehlgeschlagen: \(error.localizedDescription)")
            // Weiter mit Sync — Backup ist Komfort, kein Pflicht-Gate.
        }

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

    /// Liest Credentials aus dem Keychain und ruft `sync()`. Falls keine Credentials
    /// konfiguriert sind, fällt die Methode auf einen lokalen `refresh()` zurück —
    /// damit ist der Sync-Button in der Toolbar auch ohne Server-Konfiguration
    /// sinnvoll und bringt die UI auf den aktuellen Replica-Stand.
    func syncIfConfigured() async {
        guard let serverUrl = KeychainStore.load(key: .serverUrl), !serverUrl.isEmpty,
              let clientId = KeychainStore.load(key: .clientId), !clientId.isEmpty,
              let secret = KeychainStore.load(key: .encryptionSecret), !secret.isEmpty
        else {
            await refresh()
            return
        }
        await sync(serverUrl: serverUrl, clientId: clientId, encryptionSecret: secret)
    }

    /// Liest die Anzahl der noch nicht synchronisierten lokalen Operationen vom Store.
    /// Non-blocking: Fehler werden stumm als 0 behandelt.
    func refreshLocalChanges() async {
        localChangesGeneration += 1
        let token = localChangesGeneration
        let store = self.store
        let count: UInt64
        do {
            count = try await Task.detached(priority: .utility) {
                try store.numLocalOperations()
            }.value
        } catch {
            count = 0
        }
        // Nur publizieren, wenn kein neuerer Lauf zwischenzeitlich gestartet wurde.
        guard token == localChangesGeneration else { return }
        self.localChanges = count
    }

    /// Konfiguriert den Auto-Sync-Scheduler. Cancelt den bisherigen Timer und startet
    /// einen neuen, falls der Modus ein Intervall hat.
    func configureAutoSync(mode: AutoSyncMode) {
        currentSyncMode = mode
        autoSyncTask?.cancel()
        autoSyncTask = nil
        nextSyncDate = nil

        guard let interval = mode.interval else { return }

        let next = Date().addingTimeInterval(interval)
        nextSyncDate = next

        autoSyncTask = Task { [weak self] in
            var scheduledNext = next
            while !Task.isCancelled {
                let delay = max(0, scheduledNext.timeIntervalSinceNow)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else { break }
                await self?.syncIfConfigured()
                scheduledNext = Date().addingTimeInterval(interval)
                self?.nextSyncDate = scheduledNext
            }
        }
    }

    /// Pfad zum Replica-Verzeichnis im App-Container. Im Sandbox liefert
    /// `applicationSupportDirectory` automatisch den Container-Pfad.
    /// Rationale (Container-Hierarchie): siehe docs/architecture.md.
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
