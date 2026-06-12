# Changelog

All notable changes to Vergissmeinnicht are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project follows a loose [Semantic Versioning](https://semver.org/) scheme.
Releases before 0.2.4 are recorded only as Git tags and GitHub Releases.

## [Unreleased]

### Fixed
- App bundles are ad-hoc code-signed again, so the app-sandbox entitlement is
  embedded. Release zips and locally installed builds were previously produced
  with code signing disabled and ran *without* the sandbox, reading and writing
  `~/Library/Application Support/vergissmeinnicht/` and
  `~/Library/Preferences/` instead of the documented container paths (#30).
  If you used an earlier release zip and the app starts with stale or missing
  tasks after updating, copy your replica into the container (or re-sync from
  your sync server):
  ```sh
  mkdir -p ~/Library/Containers/de.hnsstrk.vergissmeinnicht/Data/Library/Application\ Support/vergissmeinnicht
  cp -R ~/Library/Application\ Support/vergissmeinnicht/replica \
    ~/Library/Containers/de.hnsstrk.vergissmeinnicht/Data/Library/Application\ Support/vergissmeinnicht/
  ```

## [0.2.5] - 2026-06-10

### Fixed
- The pending-changes dot on the sync toolbar button no longer shows when no
  sync server is configured. Without credentials every operation stays
  "unsynced" forever, so the dot was permanently on and carried no
  information (#29).
- Removing sync credentials from the Keychain no longer fails silently — a
  failed delete now surfaces as an error.
- The app test target was missing its generated Info.plist, which broke
  `xcodebuild test` entirely.

### Added
- The sync server URL is validated up front (scheme + host) and rejected with
  a clear error message instead of failing deep inside the sync stack.
- New unit tests: sidebar filter semantics (app target) and
  timestamp/UUID/URL helpers (Rust core).
- CI hardening: a `cargo clippy -D warnings` gate and a RustSec `cargo audit`
  dependency-audit job; the release workflow now runs the Rust and Swift test
  suites before building.

### Changed
- Refreshed README screenshots: fully English demo dataset, plus a new
  month-calendar screenshot.

## [0.2.4] - 2026-06-04

### Added
- **Calendar month view** (View ▸ Calendar, ⇧⌘K): tasks rendered on a monthly grid — `scheduled`→`due` spans as multi-day bars ("duration"), due dates as markers, recurrences as repeated markers, with a per-day agenda popover. Mirrors Taskwarrior's own `task calendar`.
- **Forecast above the task list**, configurable **per sidebar perspective** in a dedicated Settings tab "Vorschau": display mode (off / compact / agenda), range (3 days up to 4 weeks), tasks-per-day cap, and ISO calendar-week (KW) labels. Compact mode is an ISO-week-aligned mini-month grid; agenda groups by day with project subtitles. Forecast height is dynamic.
- **Task dependencies** (`depends`): editable in the detail view, plus **Blocked / Blocking / Unblocked** reports in the menu (native Taskwarrior `+BLOCKED`/`+BLOCKING`/`+UNBLOCKED`).
- **Dotted project hierarchy** in the sidebar as a collapsible tree, with prefix-match filtering (`project:Parent` includes subprojects) and a Settings toggle.
- **App-target test suite** (parsers, view-model filters, AppContainer integration, calendar bucketing) wired into CI.
- **Architecture docs** (`docs/architecture.md`): container hierarchy, `u32` working-set ID, replica lifecycle.

### Changed
- **Today** now also includes due-less tasks `scheduled` for today.
- **Batch operations** report partial failures ("N of M failed") for all multi-selection actions, not just rename.
- Internal: RootView refactored (bulk actions and toolbar extracted into their own types).

### Not planned
- System-wide global hotkey and manual `sort_order` reordering were declined as out of scope — they are not native Taskwarrior concepts. Ordering in Taskwarrior is driven by urgency.

[0.2.5]: https://github.com/hnsstrk/vergissmeinnicht/compare/v0.2.4...v0.2.5
[0.2.4]: https://github.com/hnsstrk/vergissmeinnicht/compare/v0.2.3...v0.2.4
