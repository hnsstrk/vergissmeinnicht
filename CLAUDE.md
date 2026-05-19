# CLAUDE.md

Repo-specific instructions for Claude Code. Global rules live in `~/.claude/CLAUDE.md` and apply in addition.

## Project Architecture

Native macOS client for Taskwarrior 3.x. Three layers:

| Layer | Path | Language |
|-------|------|----------|
| Rust core / FFI | `rust/vergissmeinnicht-core/` | Rust + uniffi |
| Swift bindings (XCFramework) | `swift/VergissmeinnichtKit/` | Swift, generated |
| macOS app target | `app/Vergissmeinnicht/` | SwiftUI |

Full architecture, build toolchain, and failure modes: [`docs/building.md`](docs/building.md).

## Build Pipeline

**After an FFI change** (mandatory — otherwise Swift runs against stale bindings):
```bash
bash scripts/build-macos.sh
```
Regenerates the XCFramework + uniffi Swift wrapper.

**Local author install** (Rust + app + `/Applications/` + restart in one step):
```bash
bash scripts/install-local.sh
# Options:
#   --skip-rust    Swift-only changes, FFI unchanged
#   --no-restart   do not start the app after install
```

**CI** (`.github/workflows/ci.yml`): macOS-15 / Xcode 16.0 / Swift 6.0. **Locally Xcode 26.x / Swift 6.3 runs** — CI is the stricter one. Known pitfalls:
- Method-reference closures (e.g. `array.sorted(by: foo)`) are inferred as throwing under Swift 6.0 → use an explicit `{ a, b in foo(a, b) }`.
- `UNNotificationSettings` only became Sendable in later SDKs → `@preconcurrency import UserNotifications`.

## Mandatory Conventions

### Language

- **Commit messages: English.** All new commits use English messages. Historical commits are not rewritten (no `git rebase -i` / `filter-repo` on existing history).
- **Documentation that lands on GitHub: English.** This covers `README.md`, everything under `docs/`, and the agent definitions under `.claude/agents/`. `README.de.md` is the single intentional German counterpart and is kept as a translation (English is canonical).
- **App source strings: German keys.** New user-facing strings use `String(localized:)` / `LocalizedStringKey` with the German text as the key; English is the catalog translation. See the Localization section — this is intentionally separate from the repo-documentation language.
- **User communication, vault notes, and journal entries: German** (per the global `~/.claude/CLAUDE.md`). Unchanged.

### xcodeproj — new Swift files
New `.swift` files in the app target **must** be registered four times in `app/Vergissmeinnicht/Vergissmeinnicht.xcodeproj/project.pbxproj`: `PBXBuildFile`, `PBXFileReference`, `PBXGroup`, `PBXSourcesBuildPhase`. Same for `Assets.xcassets` & `Localizable.xcstrings` — see the v0.1.1 icon hotfix in the journal as a cautionary tale.

### Single Source of Truth
- `AppContainer` holds the task list — ViewModels hold only derived UI state.
- Filter/count logic is centralized in `SidebarFilter.matches(_:now:dueSoonDays:)` — sidebar badges and the main list use the same function.

### Sidebar Icon Style

System rows of the sidebar use **filled SF Symbols with color applied directly to the symbol** (`.foregroundStyle(<color>)`) — **no** colored background, **no** RoundedRectangle. Project and tag rows stay uncolored (folder/tag outline). Binding assignment:

| Row           | SF Symbol                       | Color       | Semantics |
|---------------|---------------------------------|-------------|-----------|
| Inbox         | `tray.fill`                     | `.blue`     | Universal inbox blue |
| Today         | `star.fill`                     | `.yellow`   | Actionable right now |
| To Do         | `list.bullet`                   | `.green`    | Everything actionable |
| Overdue       | `exclamationmark.circle.fill`   | `.red`      | Danger |
| Due Soon      | `clock.fill`                    | `.orange`   | Warning |
| Scheduled     | `calendar`                      | `.indigo`   | Future-related, cool |
| Waiting       | `moon.zzz.fill`                 | `.gray`     | Paused |
| All           | `tray.full.fill`                | `.purple`   | Meta view |

An earlier variant (white symbol on a colored square) was rejected: too heavy, visually collides with badges. Colored symbol without a background = lighter, faster to identify.

The colors are user-toggleable: `AppSettingsKey.sidebarColoredIcons` (Bool, default `true`). When off, `coloredIcon` falls back to `.secondary` so system rows match the monochrome project/tag rows. Single change point — `coloredRow` and `inboxRow` share `coloredIcon`.

### Toolbar Icon Style

Unified concept: **every toolbar entry is a single SF-Symbol glyph in a standard `Button`/`Menu` — no inline text in the button label, no custom padding, no visible menu indicator.** Result: identical round hover surface for all items. Consequences for future edits:
- The sort `Menu` carries `.menuIndicator(.hidden)` so it matches the plain icon buttons.
- `SyncStatusView` is a standard `Button` (no `.padding`/Capsule background). The pending counter is a layout-neutral `.overlay` badge on the icon; icon and spinner share a fixed `.frame(width: 16, height: 16)` so the glyph never jumps between idle/syncing/pending states.
- Do not reintroduce custom-padded HStacks inside toolbar button labels — that was the original cause of the circle-vs-pill-vs-oval inconsistency.

### Karpathy Principles
Code comments explicitly reference "Karpathy 2 (Simplicity)" and "Karpathy 3 (Surgical)" as justification. Keep the style — no speculative features, no adjacent refactorings.

### Localization
Source language **German**, EN as the translation in `app/Vergissmeinnicht/Resources/Localizable.xcstrings`. New user-facing strings via `String(localized:)` / `LocalizedStringKey`, then invoke the `localizer` subagent.

## Documentation Obligation

After every session that touches code or configuration:

### 1. Vault project folder

Path (resolve dynamically, do not hardcode — see the `obsidian-vault` skill):
```
$VAULT_PATH/Projekte/vergissmeinnicht/
```

- **[[Vergissmeinnicht Projektuebersicht]]** — architecture state, wave history, status. Update on architecture changes, new waves, completed roadmap items.
- **[[Vergissmeinnicht Backlog 2026-05-14]]** — tier-1 to tier-4 backlog with findings from the audits. Record completed items in the "Erledigt seit Backlog-Anlage" section, do not remove them from the tier tables (audit trail).

### 2. Daily journal log

Append an entry under `## Claude Code Protokoll` in today's daily — format and rules see the global rule `~/.claude/rules/journal-logging.md`. Mandatory content for this project:
- Changed files with concrete paths
- FFI changes named explicitly (taskchampion method + Swift call name)
- Build status (cargo / swift test / xcodebuild)
- Wiki link to `[[Vergissmeinnicht Projektuebersicht]]` and/or `[[Vergissmeinnicht Backlog 2026-05-14]]`

## Subagent Recipe

For multi-part sessions, dispatch in this order (see `~/.claude/agents/`):

1. `rust-ffi` — when FFI is touched. Verifies via `bash scripts/build-macos.sh` and a smoke build of the Swift target.
2. `swift-ui` — UI/ViewModel/AppContainer. Verifies via `xcodebuild build`.
3. `localizer` — DE/EN strings in Localizable.xcstrings (can run in parallel with 4 and 5).
4. `test-runner` — `cargo test` + `swift test` + `xcodebuild build`.
5. `docs-translator` — keeps GitHub-facing documentation in English (`README.md`, `docs/`, `.claude/agents/*.md`); can run in parallel with 3 and 4.

`karpathy-planner` before sessions with unclear scope, `karpathy-reviewer` before finalizing large changes.

## Sandbox / Paths

- The replica lives in the app container: `~/Library/Containers/de.hnsstrk.vergissmeinnicht/Data/Library/Application Support/vergissmeinnicht/replica/`
- Sync credentials only in the Keychain (`KeychainStore.swift`), not in UserDefaults
- No access to the CLI's `~/.task/` — data exchange exclusively via the user-configured taskchampion-sync-server
