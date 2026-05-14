# Agent Team — vergissmeinnicht

Projekt-lokale Subagents. Werden automatisch geladen, wenn Claude Code im Repo-Root läuft (`.claude/agents/<name>.md`).

## Team

| Agent | Zuständig für | Anker-Dateien |
|-------|---------------|---------------|
| `rust-ffi` | Rust-Core, UniFFI-Bindings, taskchampion-Integration | `rust/vergissmeinnicht-core/src/lib.rs`, `scripts/build-macos.sh` |
| `swift-ui` | SwiftUI-Views, ViewModels, Drag&Drop, Editor-Sheets, xcodeproj-Pflege | `app/Vergissmeinnicht/Sources/VergissmeinnichtApp/*.swift` |
| `localizer` | String Catalog (`Localizable.xcstrings`), DE/EN-Übersetzungen, Sprach-Override | `app/Vergissmeinnicht/Sources/VergissmeinnichtApp/Localizable.xcstrings` |
| `test-runner` | Verifikation: `cargo test`, `swift test`, `xcodebuild build` | — (nur Read/Run) |

## Aufruf-Muster

Aus dem Hauptagent via `Agent`-Tool mit `subagent_type: "rust-ffi" | "swift-ui" | "test-runner"`.

Typische Welle:
1. `rust-ffi` ergänzt Felder/Methoden, regeneriert Bindings.
2. `swift-ui` baut UI gegen die neue FFI-Form, pflegt xcodeproj.
3. `test-runner` läuft als Schlusscheck.

## Karpathy-Anbindung

Diese drei Agenten ergänzen — sie ersetzen NICHT — die globalen `karpathy-planner` (pre-task) und `karpathy-reviewer` (post-task). Beide bleiben für Plan + Review zuständig; die drei Repo-Agenten sind reine Execution-Rollen mit engem Scope (Karpathy 3).
