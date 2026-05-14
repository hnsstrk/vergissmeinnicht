# Vergissmeinnicht

Nativer macOS-Client für [Taskwarrior](https://taskwarrior.org) 3.x, basierend
auf [TaskChampion](https://github.com/GothenburgBitFactory/taskchampion).
SwiftUI-Frontend, Rust-Core via UniFFI, sandboxed, App-Store-tauglich.

🇬🇧 [English version](README.md)

![Vergissmeinnicht — Heute-Ansicht im Dark Mode](docs/screenshots/main.png)

## Features

- **Sidebar-Perspektiven** — Eingang · Zu erledigen · Heute · Überfällig · Bald
  fällig · Wartend · Geplant · Alle · pro Projekt · pro Tag. Mit Counts und
  Drop-Targets.
- **Quick Capture** (⌘N) — Eingabe-Sheet mit Titel, Notizen, Projekt,
  Tags, Fälligkeit, Priorität, Wiederholung. Alternativ Token-Syntax (`+tag
  project:foo due:tomorrow`).
- **Detail-Editor** in eigenem Fenster — Titel, Projekt, Tags, Fälligkeit,
  Geplant ab, Priorität, Wiederholung, Notizen (mit Markdown-Rendering).
- **Multi-Selection** mit Bulk-Erledigt / Löschen / Projekt / Tag / Priorität /
  Fälligkeit über Kontextmenü, mit nativem `contextMenu(forSelectionType:)`.
- **Drag & Drop** Tasks auf Projekte, Tags oder Eingang (löscht Projekt + Tags).
- **Wiederkehrende Aufgaben** — daily / weekly / monthly / yearly + `Nd / Nw /
  Nm / Ny`. Erledigen einer Recurring-Task erzeugt atomar die nächste Instanz.
- **Snooze / Wait** — Aufgaben verschieben; sie erscheinen unter „Wartend"
  statt Heute zu verstopfen.
- **Tag- und Projekt-Management** — Rechtsklick in der Sidebar zum Umbenennen
  oder vollständigen Entfernen aus allen Tasks.
- **Notifications** — opt-in Zusammenfassungs-Notification beim Launch bei
  überfälligen Aufgaben.
- **Lokalisierung** — Deutsch (Quelle) und Englisch, mit Override-Schalter.
- **Sync** gegen einen beliebigen [taskchampion-sync-server](https://github.com/GothenburgBitFactory/taskchampion-sync-server).
  Credentials im macOS-Keychain.
- **Automatische Backups** — `VACUUM INTO`-Snapshot vor jedem Sync, rotierend
  die letzten 10. Manuelles Backup und Restore aus den Einstellungen. Siehe
  [`docs/backup-and-restore.md`](docs/backup-and-restore.md).

## Architektur

```
┌─────────────────────────────────────────────┐
│  SwiftUI-App (Hauptfenster + MenuBarExtra)  │
│  Sidebar · TaskList · Detail · Settings     │
└──────────────────┬──────────────────────────┘
                   │  UniFFI-generierter Swift-Wrapper
┌──────────────────▼──────────────────────────┐
│  VergissmeinnichtKit (SwiftPM)              │
│  Binary-Target: VergissmeinnichtCoreFFI     │
└──────────────────┬──────────────────────────┘
                   │  C-ABI
┌──────────────────▼──────────────────────────┐
│  vergissmeinnicht-core (Rust)               │
│  taskchampion 3.0.1 · tokio · uniffi 0.29   │
│  Replica = SQLite im App-Sandbox-Container  │
└──────────────────┬──────────────────────────┘
                   │  HTTPS
┌──────────────────▼──────────────────────────┐
│  taskchampion-sync-server (selbst gehostet) │
└─────────────────────────────────────────────┘
```

Die App läuft sandboxed. Die Replica liegt unter
`~/Library/Containers/de.hnsstrk.vergissmeinnicht/Data/Library/Application Support/`.
Kein direkter Zugriff auf `~/.task/` — Datenaustausch ausschließlich über den
Sync-Server.

## Voraussetzungen

- macOS 14 Sonoma oder neuer (arm64; Intel-Support steht im Backlog)
- Xcode 16 mit Swift-6-Toolchain
- Rust-Toolchain (Homebrew funktioniert; `rustup` empfohlen)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — nur wenn das Xcode-Projekt
  aus `app/Vergissmeinnicht/project.yml` neu erzeugt werden soll. Das
  eingecheckte `Vergissmeinnicht.xcodeproj` wird inzwischen manuell gepflegt.

## Build

```sh
# 1. Rust-Core bauen, Swift-Bindings generieren, xcframework erzeugen
./scripts/build-macos.sh

# 2. App in Xcode öffnen
open app/Vergissmeinnicht/Vergissmeinnicht.xcodeproj

# 3. Oder über die CLI bauen
xcodebuild -project app/Vergissmeinnicht/Vergissmeinnicht.xcodeproj \
           -scheme Vergissmeinnicht \
           build
```

Tests ausführen:

```sh
# Rust
cargo test --manifest-path rust/Cargo.toml

# Swift-Package (FFI-Roundtrips, Metadaten, Write-Ops, Sync)
swift test --package-path swift/VergissmeinnichtKit
```

## Sync-Setup

1. Eigenen [taskchampion-sync-server](https://github.com/GothenburgBitFactory/taskchampion-sync-server)
   betreiben (oder einen bestehenden nutzen).
2. In der App **Einstellungen → Sync-Server** öffnen, URL, Client-ID und
   Encryption-Secret eintragen. Werte werden im Keychain gespeichert
   (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`).
3. **Test-Sync** klicken. Fertig.

Die App und die `task`-CLI auf anderen Maschinen gleichen sich über den
Sync-Server ab. TaskChampion löst Konflikte CRDT-artig über das Operation-Log.

## Repo-Aufbau

```
.
├── app/Vergissmeinnicht/   SwiftUI-App, xcodeproj, Resources, Entitlements
├── rust/                   Cargo-Workspace
│   └── vergissmeinnicht-core/   Rust-Core, UniFFI-Exports
├── swift/VergissmeinnichtKit/   SwiftPM-Package um das xcframework
├── scripts/build-macos.sh  cargo + uniffi-bindgen + xcframework-Build
└── docs/                   Architektur-Notizen, Backup-Recovery, Changelogs
```

## Hooks: bewusst out-of-scope

Taskwarrior-Hooks sind ein Feature der `task`-CLI, nicht der TaskChampion-Lib,
die diese App nutzt. Äquivalente (Reminder, Validierung, Auto-Tagging) sind
nativ in Swift umgesetzt — kein Subprocess-Bedarf, sandbox-konform.

## Danksagung

- [Taskwarrior](https://taskwarrior.org) und das GothenburgBitFactory-Team für
  [TaskChampion](https://github.com/GothenburgBitFactory/taskchampion) und den
  Sync-Server.
- Design-Notiz: ,
  , .

## Lizenz

[MIT](LICENSE).
