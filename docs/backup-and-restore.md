# Backup & Restore

## Standorte

| Element | Pfad |
|---------|------|
| Aktive Replica | `~/Library/Containers/de.hnsstrk.vergissmeinnicht/Data/Library/Application Support/vergissmeinnicht/replica/` (mit `taskchampion.sqlite3` + `-wal` + `-shm`) |
| Automatische Backups | `~/Library/Containers/de.hnsstrk.vergissmeinnicht/Data/Library/Application Support/vergissmeinnicht/backups/` |
| Backup-Dateinamen | `<reason>-<UTC-Timestamp>.sqlite3` (z.B. `pre-sync-20260514-180945.sqlite3`) |

## Automatik

- **Vor jedem Sync** (Auto-Sync beim Launch und manueller Klick auf den Sync-Button) wird ein Snapshot der Replica via SQLite-`VACUUM INTO` erzeugt.
- Rotation: maximal 10 Backups (älteste werden automatisch gelöscht).
- Reason-Codes:
  - `pre-sync` — Auto-Backup vor Sync
  - `manual` — User-getriggert aus Settings → Wartung
  - `pre-restore` — Sicherheits-Backup vor einem Restore-Vorgang

Backups werden mit SQLite-`VACUUM INTO` erzeugt — das ist auch unter aktivem WAL konsistent (online-backup-API).

## Manual über Settings

Settings → Wartung → **Datensicherung**:

- **Backup erstellen** — sofortiges Snapshot, Status-Meldung mit Dateinamen
- **Backups öffnen …** — öffnet das Backup-Verzeichnis im Finder (zum manuellen Sichern auf externe Medien)
- **Aus Backup wiederherstellen …** — öffnet Sheet mit allen Backups (Größe + Datum), nach Bestätigungs-Dialog wird die aktive Replica ersetzt

## Restore-Vorgang

1. Settings → Wartung → „Aus Backup wiederherstellen …"
2. Backup-Datei in der Liste wählen
3. „Wiederherstellen" → Confirm-Dialog → „Wiederherstellen" (destruktiv)
4. App-Neustart (die offenen FFI-Handles verweisen auf die alte Replica-Sicht)

**Vor dem destruktiven Schritt** wird die aktuelle Replica automatisch nochmal als `pre-restore`-Backup gesichert — falls die User-Wahl falsch war, lässt sich darüber wieder zurück.

## Off-App-Backup (empfohlen vor produktivem Einsatz)

```bash
REPLICA="$HOME/Library/Containers/de.hnsstrk.vergissmeinnicht/Data/Library/Application Support/vergissmeinnicht/replica"
DEST="$HOME/Backups/vergissmeinnicht-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$DEST"
cp -R "$REPLICA" "$DEST/replica"
```

## Notfall-Wiederherstellung von außen

Wenn die App nicht mehr startet (`InitErrorView`):

1. App komplett beenden.
2. Backup-Datei aus `…/vergissmeinnicht/backups/` wählen — z.B. die neueste `pre-sync-*.sqlite3`.
3. Im Replica-Ordner `taskchampion.sqlite3`, `-wal` und `-shm` löschen.
4. Backup-Datei nach `taskchampion.sqlite3` im Replica-Ordner kopieren.
5. App neu starten — sie sollte den `pre-restore`-Pfad jetzt nicht mehr brauchen.

## Snapshot aus Taskwarrior holen

Wenn die Replica ganz zerschossen ist, kann ein frischer Taskwarrior-Snapshot eingespielt werden:

```bash
REPLICA="$HOME/Library/Containers/de.hnsstrk.vergissmeinnicht/Data/Library/Application Support/vergissmeinnicht/replica"
rm -f "$REPLICA/taskchampion.sqlite3"*
sqlite3 "$HOME/.task/taskchampion.sqlite3" "VACUUM INTO '$REPLICA/taskchampion.sqlite3'"
sqlite3 "$REPLICA/taskchampion.sqlite3" "DELETE FROM sync_meta; DELETE FROM operations; VACUUM;"
```

Damit ist die App-Replica auf dem Stand der Taskwarrior-CLI. Beim nächsten Sync wird sie mit dem Server abgeglichen.

## Was nicht gesichert wird

- Sync-Credentials (`server_url`, `client_id`, `encryption_secret`) — die liegen im macOS-Keychain und werden separat von macOS Time Machine berücksichtigt.
- App-Settings (Sprache, Default-Filter, Bald-Fällig-Fenster) — `~/Library/Containers/de.hnsstrk.vergissmeinnicht/Data/Library/Preferences/de.hnsstrk.vergissmeinnicht.plist`. Sind nicht datenkritisch.
