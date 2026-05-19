# CLAUDE.md

Repo-spezifische Anweisungen für Claude Code. Globale Regeln stehen in `~/.claude/CLAUDE.md` und gelten zusätzlich.

## Projekt-Architektur

Nativer macOS-Client für Taskwarrior 3.x. Drei Schichten:

| Schicht | Pfad | Sprache |
|---------|------|---------|
| Rust-Core / FFI | `rust/vergissmeinnicht-core/` | Rust + uniffi |
| Swift-Bindings (XCFramework) | `swift/VergissmeinnichtKit/` | Swift, generiert |
| macOS-App-Target | `app/Vergissmeinnicht/` | SwiftUI |

Vollständige Architektur, Build-Toolchain und Failure-Modes: [`docs/building.md`](docs/building.md).

## Build-Pipeline

**Nach FFI-Änderung** (Pflicht — sonst läuft Swift mit veralteten Bindings):
```bash
bash scripts/build-macos.sh
```
Regeneriert XCFramework + uniffi-Swift-Wrapper.

**Lokaler Author-Install** (Rust + App + `/Applications/` + Restart in einem Schritt):
```bash
bash scripts/install-local.sh
# Optionen:
#   --skip-rust    nur Swift-Änderungen, FFI unverändert
#   --no-restart   App nach Install nicht starten
```

**CI** (`.github/workflows/ci.yml`): macOS-15 / Xcode 16.0 / Swift 6.0. **Lokal läuft Xcode 26.x / Swift 6.3** — strikter ist CI. Bekannte Stolperfallen:
- Method-Reference-Closures (z. B. `array.sorted(by: foo)`) werden in Swift 6.0 als throwing inferiert → explizit `{ a, b in foo(a, b) }`.
- `UNNotificationSettings` ist erst ab späteren SDKs Sendable → `@preconcurrency import UserNotifications`.

## Pflicht-Konventionen

### xcodeproj — neue Swift-Dateien
Neue `.swift`-Dateien im App-Target **müssen** in `app/Vergissmeinnicht/Vergissmeinnicht.xcodeproj/project.pbxproj` viermal registriert werden: `PBXBuildFile`, `PBXFileReference`, `PBXGroup`, `PBXSourcesBuildPhase`. Auch `Assets.xcassets` & `Localizable.xcstrings` — siehe v0.1.1-Icon-Hotfix im Journal als Warnung.

### Single Source of Truth
- `AppContainer` hält die Task-Liste — ViewModels nur abgeleiteter UI-State.
- Filter-/Count-Logik zentral in `SidebarFilter.matches(_:now:dueSoonDays:)` — Sidebar-Badges und Hauptliste nutzen dieselbe Funktion.

### Sidebar-Icon-Stil

System-Zeilen der Sidebar nutzen **gefüllte SF-Symbols mit Farbe direkt am Symbol** (`.foregroundStyle(<color>)`) — **kein** farbiger Hintergrund, **kein** RoundedRectangle. Projekt- und Tag-Zeilen bleiben uncolored (Folder/Tag-Outline). Verbindliche Zuordnung:

| Zeile         | SF-Symbol                       | Farbe       | Semantik |
|---------------|---------------------------------|-------------|----------|
| Eingang       | `tray.fill`                     | `.blue`     | Universelles Inbox-Blau |
| Heute         | `star.fill`                     | `.yellow`   | Jetzt aktionsrelevant |
| Zu erledigen  | `list.bullet`                   | `.green`    | Alles Actionable |
| Überfällig    | `exclamationmark.circle.fill`   | `.red`      | Gefahr |
| Bald fällig   | `clock.fill`                    | `.orange`   | Warnung |
| Geplant       | `calendar`                      | `.indigo`   | Zukunfts-bezogen, kühl |
| Wartend       | `moon.zzz.fill`                 | `.gray`     | Pausiert |
| Alle          | `tray.full.fill`                | `.purple`   | Meta-Sicht |

Eine frühere Variante (weißes Symbol auf farbigem Quadrat) wurde verworfen: zu schwer, kollidiert visuell mit Badges. Farbiges Symbol ohne Hintergrund = leichter, schneller identifizierbar.

### Karpathy-Prinzipien
Code-Comments referenzieren explizit „Karpathy 2 (Simplicity)" und „Karpathy 3 (Surgical)" als Begründung. Den Stil beibehalten — keine spekulativen Features, keine adjazenten Refactorings.

### Lokalisierung
Quellsprache **Deutsch**, EN als Übersetzung in `app/Vergissmeinnicht/Resources/Localizable.xcstrings`. Neue User-facing Strings via `String(localized:)` / `LocalizedStringKey`, dann den `localizer`-Subagent aufrufen.

## Dokumentations-Pflicht

Nach jeder Session, die Code oder Konfiguration berührt:

### 1. Vault-Projektordner

Pfad (dynamisch resolven, nicht hardcoden — siehe Skill `obsidian-vault`):
```
$VAULT_PATH/Projekte/vergissmeinnicht/
```

- **[[Vergissmeinnicht Projektuebersicht]]** — Architektur-Stand, Welle-Historie, Status. Aktualisieren bei Architektur-Änderungen, neuen Wellen, abgeschlossenen Roadmap-Punkten.
- **[[Vergissmeinnicht Backlog 2026-05-14]]** — Tier-1- bis Tier-4-Backlog mit Findings aus den Audits. Erledigte Punkte in der Sektion „Erledigt seit Backlog-Anlage" eintragen, nicht aus den Tier-Tabellen entfernen (Audit-Trail).

### 2. Daily-Journal-Protokoll

Im heutigen Daily unter `## Claude Code Protokoll` einen Eintrag anhängen — Format und Regeln siehe globale Rule `~/.claude/rules/journal-logging.md`. Pflicht-Inhalt für dieses Projekt:
- Geänderte Dateien mit konkreten Pfaden
- FFI-Änderungen explizit benennen (taskchampion-Methode + Swift-Aufrufname)
- Build-Status (cargo / swift test / xcodebuild)
- Wiki-Link zu `[[Vergissmeinnicht Projektuebersicht]]` und/oder `[[Vergissmeinnicht Backlog 2026-05-14]]`

## Subagent-Rezept

Für mehrteilige Sessions in dieser Reihenfolge dispatchen (siehe `~/.claude/agents/`):

1. `rust-ffi` — wenn FFI berührt wird. Verifiziert via `bash scripts/build-macos.sh` und Smoke-Build des Swift-Targets.
2. `swift-ui` — UI/ViewModel/AppContainer. Verifiziert via `xcodebuild build`.
3. `localizer` — DE/EN-Strings in Localizable.xcstrings (kann parallel zu 4 laufen).
4. `test-runner` — `cargo test` + `swift test` + `xcodebuild build`.

`karpathy-planner` vor Sessions mit unklarem Scope, `karpathy-reviewer` vor Finalisierung großer Änderungen.

## Sandbox / Pfade

- Replica liegt im App-Container: `~/Library/Containers/de.hnsstrk.vergissmeinnicht/Data/Library/Application Support/vergissmeinnicht/replica/`
- Sync-Credentials nur im Keychain (`KeychainStore.swift`), nicht in UserDefaults
- Kein Zugriff auf `~/.task/` der CLI — Datenaustausch ausschließlich über den User-konfigurierten taskchampion-sync-server
