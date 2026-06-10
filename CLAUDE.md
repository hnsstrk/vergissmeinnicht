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

## Product Design Principle: Taskwarrior-faithful GUI

Vergissmeinnicht is a **GUI for Taskwarrior**, not a reimplementation. Taskwarrior itself is CLI-only; the value we add is presentation and ergonomics.

- **Allowed:** GUI-specific elements the CLI does not have — visual perspectives, the sidebar, inline editors, drag-and-drop, hierarchy rendering, and additional access channels (AppIntents, hotkeys).
- **Not allowed:** anything that **contradicts** Taskwarrior's concepts/data model, or that would feel **foreign or wrong** to a Taskwarrior user. Do not invent a parallel concept when a native Taskwarrior mechanism already expresses the need.
- **Prefer surfacing native mechanisms** (`scheduled`, `depends`, dotted project hierarchy, urgency, tags, annotations) over inventing fields/UDAs. Decisions already taken under this principle: no invented "today flag" → `scheduled` (#1); no `parent_uuid` subtasks → `depends` + projects (#3); no `sort_order`/manual reorder → urgency (#4); no separate `area` field → dotted project hierarchy (#10).
- **Decision test** for any new feature: (1) Does it map cleanly onto Taskwarrior data? (2) Does the written result still read correctly in the Taskwarrior CLI? (3) Would it confuse or mislead someone who knows Taskwarrior? If 1+2 are yes and 3 is no, it fits. A new *rendering* of native data (e.g. a collapsible tree over dotted project names) is fine; a new *concept* the CLI cannot represent is not.

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

### Issue Tracking & Backlog

The **GitHub Issues** of this repo (`hnsstrk/vergissmeinnicht`) are the single source of truth for the backlog. Every bug, feature request, task, or audit finding is filed as a GitHub issue — **in English** — with a label (`bug` / `enhancement` / `documentation`). Create them with `gh issue create`.

- Do **not** keep a parallel backlog in the vault or in markdown files. The vault holds architecture/wave documentation only.
- Audit findings (e.g. multi-agent reviews) are filed as individual issues — one per finding — after verification against current code; skip items the code already satisfies.
- Close issues when the work lands and reference the issue number in the commit/PR.

### Releases & Changelog
- **`CHANGELOG.md`** (Keep a Changelog format) is the curated, human-written source of release notes — one `## [x.y.z]` section per release, user-facing wording (not raw commits). Add/update the section **before** tagging. `release.yml` **enforces** this with a guard step that fails fast if the tag has no matching `## [<version>]` section.
- **Release notes are generated from the changelog, never hand-written per release.** `.github/workflows/release.yml` extracts the matching `## [<version>]` section from `CHANGELOG.md` and uses it as the GitHub Release body, appending the install/quarantine footer from `.github/release-footer.md` (with `__TAG__` substituted for the tag). Do **not** reintroduce a hard-coded release body — that produced identical notes for every release.
- **Release flow:** bump `MARKETING_VERSION` (two places in `project.pbxproj`) → update `CHANGELOG.md` → push `main`, wait for CI green → push an annotated tag `vX.Y.Z` (triggers `release.yml`) → watch the release run to green. Tags are `v`-prefixed (e.g. `v0.2.4`).

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

### Coding Guidelines

Distilled from the patterns already in the codebase — new code follows them; deviations need a stated reason.

**Error handling**
- Rust: no `unwrap()`/`expect()`/`panic!` outside `#[cfg(test)]`. Fallible conversions return a `VmError` variant (`Storage`, `Conversion`, `NotFound`, `Sync`, `Internal`) with a message that names the offending value (e.g. `"invalid tag {tag_str:?}"`). Validate inputs at the FFI boundary, early — do not let bad input fail deep inside taskchampion.
- The one sanctioned exception: `lock_replica()` recovers a poisoned mutex (`unwrap_or_else(|e| e.into_inner())`) — rationale in `docs/architecture.md`; do not copy this pattern elsewhere.
- Swift: no force unwrap (`!`), no `try!`, no `as!`, no `fatalError` in app code. UI-visible failures land in `AppContainer.lastError`; silently swallowed errors (e.g. an ignored OSStatus) are bugs.

**Concurrency**
- `AppContainer`, services, and views are `@MainActor`; mutations run on `Task.detached(priority: .userInitiated)` and hop back to the MainActor to publish.
- Multi-task operations go through `withBatch` (one final refresh, partial-failure reporting) — never loop raw single mutations with per-op refreshes.
- Rust side: current-thread Tokio runtime + one `Mutex<AppReplica>`; all replica access goes through `lock_replica()`.

**Testing**
- New logic ships with tests: Rust helpers get `#[cfg(test)]` unit tests in `lib.rs`; Swift logic gets tests in `VergissmeinnichtTests` (app) or `VergissmeinnichtKitTests` (FFI roundtrips). Pure functions (parsers, filters, formatters) are the priority — UI snapshots are not expected.
- Gates that must stay green: `cargo clippy --all-targets -- -D warnings`, `cargo test`, `swift test`, `xcodebuild test`. CI enforces clippy and runs `cargo audit` (RustSec) — do not introduce new warnings.

**Versioning**
- `MARKETING_VERSION` (pbxproj) and the Cargo workspace version stay in sync — bump both on release.

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

(The backlog is tracked in GitHub Issues, not in the vault — see *Issue Tracking & Backlog* above.)

### 2. Daily journal log

Append an entry under `## Claude Code Protokoll` in today's daily — format and rules see the global rule `~/.claude/rules/journal-logging.md`. Mandatory content for this project:
- Changed files with concrete paths
- FFI changes named explicitly (taskchampion method + Swift call name)
- Build status (cargo / swift test / xcodebuild)
- Wiki link to `[[Vergissmeinnicht Projektuebersicht]]`; reference any GitHub issues touched by number (e.g. `#12`)

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
