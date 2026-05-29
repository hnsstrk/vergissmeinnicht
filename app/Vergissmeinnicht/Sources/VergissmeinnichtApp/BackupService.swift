import Foundation
import SQLite3

/// Verwaltet Backups der TaskChampion-Replica.
///
/// Backups werden als Single-File-SQLite-Snapshots via `sqlite3_backup_init` /
/// `VACUUM INTO` erzeugt — das ist konsistent auch wenn die Quell-Replica WAL
/// hat. Wir nutzen den Sandbox-eigenen Backup-Ordner
/// `~/Library/Containers/de.hnsstrk.vergissmeinnicht/Data/Library/Application Support/vergissmeinnicht/backups/`
/// damit Sandbox-Permissions passen. Rotation behält die letzten `maxRetained`
/// Backups; ältere werden gelöscht.
struct BackupService: Sendable {
    let replicaURL: URL
    let backupsURL: URL
    var maxRetained: Int = 10
    /// `FileManager.default` ist thread-safe; wir halten den Default-Manager
    /// nicht im Struct, sondern greifen pro Call auf `.default` zu — damit ist
    /// `BackupService` Sendable.

    init(
        replicaURL: URL? = nil,
        backupsURL: URL? = nil
    ) throws {
        let fm = FileManager.default
        if let replicaURL, let backupsURL {
            self.replicaURL = replicaURL
            self.backupsURL = backupsURL
        } else {
            let appSupport = try fm.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let base = appSupport.appendingPathComponent("vergissmeinnicht", isDirectory: true)
            self.replicaURL = base.appendingPathComponent("replica", isDirectory: true)
            self.backupsURL = base.appendingPathComponent("backups", isDirectory: true)
        }
        try fm.createDirectory(at: self.backupsURL, withIntermediateDirectories: true)
    }

    private var fileManager: FileManager { .default }

    /// Snapshot der aktuellen Replica nach `backups/<reason>-<timestamp>.sqlite3`.
    /// Nutzt die SQLite-C-API `sqlite3_open_v2` + `VACUUM INTO` — konsistent auch
    /// unter WAL, Sandbox-tauglich (kein Subprocess).
    /// Rückgabe: URL der Backup-Datei.
    @discardableResult
    func createBackup(reason: String = "manual", now: Date = Date()) throws -> URL {
        let timestamp = Self.timestampFormatter.string(from: now)
        let filename = "\(reason)-\(timestamp).sqlite3"
        let dest = backupsURL.appendingPathComponent(filename)
        let source = replicaURL.appendingPathComponent("taskchampion.sqlite3")
        guard fileManager.fileExists(atPath: source.path) else {
            throw BackupError.sourceMissing(source.path)
        }

        // Ziel-Datei darf nicht existieren — VACUUM INTO ist sonst Fehler.
        if fileManager.fileExists(atPath: dest.path) {
            try fileManager.removeItem(at: dest)
        }

        var db: OpaquePointer?
        let openResult = sqlite3_open_v2(source.path, &db, SQLITE_OPEN_READONLY, nil)
        guard openResult == SQLITE_OK, let db else {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            sqlite3_close(db)
            throw BackupError.sqliteFailed(Int(openResult), msg)
        }
        defer { sqlite3_close(db) }

        // Pfad-Escape: VACUUM INTO erwartet einen SQL-String-Literal. Einzelne `'`
        // im Pfad wären problematisch — wir nutzen das Container-Verzeichnis, das
        // keine Apostrophen enthält. Trotzdem defensiv escapen.
        let escapedPath = dest.path.replacingOccurrences(of: "'", with: "''")
        let sql = "VACUUM INTO '\(escapedPath)'"
        var errPtr: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &errPtr)
        if result != SQLITE_OK {
            let errMsg = errPtr.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(errPtr)
            throw BackupError.sqliteFailed(Int(result), errMsg)
        }

        try rotate()
        return dest
    }

    /// Listet alle vorhandenen Backup-Dateien, neueste zuerst.
    func listBackups() throws -> [URL] {
        let contents = try fileManager.contentsOfDirectory(
            at: backupsURL,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )
        return contents
            .filter { $0.pathExtension == "sqlite3" }
            .sorted { (a, b) in
                let aDate = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let bDate = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return aDate > bDate
            }
    }

    /// Stellt ein Backup als aktive Replica wieder her. Die alte Replica
    /// wird VOR dem Restore selbst nochmal gesichert (`pre-restore`), damit
    /// kein Daten-Round-Trip-Verlust entsteht.
    /// **Wichtig:** Caller muss App-Container schließen / neu initialisieren
    /// nach Restore — die offenen FFI-Handles haben veraltete Daten.
    func restore(from backup: URL) throws {
        // Sicherheits-Backup VOR dem Destruktiv-Step.
        _ = try? createBackup(reason: "pre-restore")

        let dest = replicaURL.appendingPathComponent("taskchampion.sqlite3")
        let wal  = replicaURL.appendingPathComponent("taskchampion.sqlite3-wal")
        let shm  = replicaURL.appendingPathComponent("taskchampion.sqlite3-shm")

        // Datenintegrität: zuerst die neue DB neben die alte kopieren. Erst wenn das
        // gelingt, werden die Live-Dateien (inkl. WAL/SHM) ersetzt. Schlägt das Kopieren
        // fehl, bleibt der bestehende Stand unangetastet — ein gescheiterter Restore
        // darf nie die vorhandene Replica vernichten.
        let staged = replicaURL.appendingPathComponent("taskchampion.sqlite3.restore-tmp")
        try? fileManager.removeItem(at: staged)
        try fileManager.copyItem(at: backup, to: staged)

        for url in [dest, wal, shm] {
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }
        do {
            try fileManager.moveItem(at: staged, to: dest)
        } catch {
            try? fileManager.removeItem(at: staged)
            throw error
        }
    }

    /// Behält die letzten `maxRetained`, löscht ältere.
    private func rotate() throws {
        let all = try listBackups()
        guard all.count > maxRetained else { return }
        for old in all.dropFirst(maxRetained) {
            try? fileManager.removeItem(at: old)
        }
    }

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()
}

enum BackupError: LocalizedError {
    case sourceMissing(String)
    case sqliteFailed(Int, String)

    var errorDescription: String? {
        switch self {
        case .sourceMissing(let path):
            return "Replica-Datei nicht gefunden: \(path)"
        case .sqliteFailed(let code, let msg):
            return "SQLite VACUUM INTO fehlgeschlagen (Code \(code)): \(msg)"
        }
    }
}
