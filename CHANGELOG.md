# Changelog

All notable changes to Vergissmeinnicht are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project follows a loose [Semantic Versioning](https://semver.org/) scheme.
Releases before 0.2.4 are recorded only as Git tags and GitHub Releases.

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

[0.2.4]: https://github.com/hnsstrk/vergissmeinnicht/compare/v0.2.3...v0.2.4
