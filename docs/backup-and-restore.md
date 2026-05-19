# Backup & Restore

## Locations

| Element | Path |
|---------|------|
| Active replica | `~/Library/Containers/de.hnsstrk.vergissmeinnicht/Data/Library/Application Support/vergissmeinnicht/replica/` (with `taskchampion.sqlite3` + `-wal` + `-shm`) |
| Automatic backups | `~/Library/Containers/de.hnsstrk.vergissmeinnicht/Data/Library/Application Support/vergissmeinnicht/backups/` |
| Backup file names | `<reason>-<UTC-Timestamp>.sqlite3` (e.g. `pre-sync-20260514-180945.sqlite3`) |

## Automation

- **Before every sync** (auto-sync on launch and a manual click on the sync button) a snapshot of the replica is created via SQLite `VACUUM INTO`.
- Rotation: at most 10 backups (oldest are deleted automatically).
- Reason codes:
  - `pre-sync` — auto backup before sync
  - `manual` — user-triggered from Settings → Maintenance
  - `pre-restore` — safety backup before a restore operation

Backups are created with SQLite `VACUUM INTO` — this is consistent even under an active WAL (online backup API).

## Manually via Settings

Settings → Maintenance → **Backup**:

- **Create backup** — immediate snapshot, status message with file name
- **Show backups…** — opens the backup directory in Finder (for manual archiving to external media)
- **Restore from backup…** — opens a sheet with all backups (size + date); after a confirmation dialog the active replica is replaced

## Restore operation

1. Settings → Maintenance → "Restore from backup…"
2. Select the backup file in the list
3. "Restore" → confirm dialog → "Restore" (destructive)
4. App restart (the open FFI handles point to the old replica view)

**Before the destructive step**, the current replica is automatically backed up again as a `pre-restore` backup — if the user choice was wrong, you can roll back via it.

## Off-app backup (recommended before production use)

```bash
REPLICA="$HOME/Library/Containers/de.hnsstrk.vergissmeinnicht/Data/Library/Application Support/vergissmeinnicht/replica"
DEST="$HOME/Backups/vergissmeinnicht-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$DEST"
cp -R "$REPLICA" "$DEST/replica"
```

## Emergency restore from outside

If the app no longer starts (`InitErrorView`):

1. Quit the app completely.
2. Pick a backup file from `…/vergissmeinnicht/backups/` — e.g. the newest `pre-sync-*.sqlite3`.
3. In the replica folder, delete `taskchampion.sqlite3`, `-wal` and `-shm`.
4. Copy the backup file to `taskchampion.sqlite3` in the replica folder.
5. Restart the app — it should no longer need the `pre-restore` path now.

## Pull a snapshot from Taskwarrior

If the replica is completely broken, a fresh Taskwarrior snapshot can be loaded in:

```bash
REPLICA="$HOME/Library/Containers/de.hnsstrk.vergissmeinnicht/Data/Library/Application Support/vergissmeinnicht/replica"
rm -f "$REPLICA/taskchampion.sqlite3"*
sqlite3 "$HOME/.task/taskchampion.sqlite3" "VACUUM INTO '$REPLICA/taskchampion.sqlite3'"
sqlite3 "$REPLICA/taskchampion.sqlite3" "DELETE FROM sync_meta; DELETE FROM operations; VACUUM;"
```

This brings the app replica to the state of the Taskwarrior CLI. On the next sync it is reconciled with the server.

## What is not backed up

- Sync credentials (`server_url`, `client_id`, `encryption_secret`) — these are stored in the macOS Keychain and are handled separately by macOS Time Machine.
- App settings (language, default filter, due-soon window) — `~/Library/Containers/de.hnsstrk.vergissmeinnicht/Data/Library/Preferences/de.hnsstrk.vergissmeinnicht.plist`. Not data-critical.
