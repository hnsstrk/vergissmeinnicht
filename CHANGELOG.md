# Changelog

All notable changes to Vergissmeinnicht are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project follows a loose [Semantic Versioning](https://semver.org/) scheme.
Releases before 0.2.4 are recorded only as Git tags and GitHub Releases.

## [0.3.0] - 2026-07-02

### Added
- Bulk editing in the detail column (#33 follow-up): with multiple tasks
  selected, the column shows an edit form for project, tags, due, scheduled,
  and priority following the macOS "Multiple Values" convention — a field
  whose value is identical across the selection shows that value, mixed
  fields stay empty with a grayed "Multiple Values" placeholder, and editing
  a field applies the new value to every selected task. The task title is
  deliberately not bulk-editable.

## [0.2.7] - 2026-07-02

### Added
- Mail-style detail column (#33): an optional third column to the right of the
  task list shows the selected task inline — same editor as the detail window.
  Toggle it via the toolbar button, *View ▸ Show Detail Column*, or ⌥⌘0 (also
  listed in the shortcut help, ⌘?); the state persists across launches. With no
  selection the column shows a hint; with multiple tasks selected it lists all
  selected tasks with full titles, project, and due date, plus bulk actions
  (mark done, delete). Double-click still opens the separate detail window;
  the two-column layout remains the default.

## [0.2.6] - 2026-06-12

### Added
- The agenda preview above the task list shows an explicit empty state when no
  task falls within the configured window ("Keine Aufgaben bis ‹Datum›"),
  including the next upcoming due/scheduled date beyond the window. Previously
  the preview collapsed invisibly and was indistinguishable from a defect.

### Fixed
- Dates across the app (forecast preview, calendar, task row chips, detail
  timestamps, backup list) now follow the language chosen in the settings.
  Previously an explicit language choice only switched the strings while the
  date order and punctuation kept following the macOS region, producing mixed
  output such as "28. June" in the English UI. With "System" nothing changes.
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
