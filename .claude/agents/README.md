# Agent Team — vergissmeinnicht

Project-local subagents. Loaded automatically when Claude Code runs in the repo root (`.claude/agents/<name>.md`).

## Team

| Agent | Responsible for | Anchor files |
|-------|-----------------|--------------|
| `rust-ffi` | Rust core, UniFFI bindings, taskchampion integration | `rust/vergissmeinnicht-core/src/lib.rs`, `scripts/build-macos.sh` |
| `swift-ui` | SwiftUI views, ViewModels, drag & drop, editor sheets, xcodeproj maintenance | `app/Vergissmeinnicht/Sources/VergissmeinnichtApp/*.swift` |
| `localizer` | String catalog (`Localizable.xcstrings`), DE/EN translations, language override | `app/Vergissmeinnicht/Sources/VergissmeinnichtApp/Localizable.xcstrings` |
| `docs-translator` | GitHub-facing docs in English (`README.md`, `docs/`, `.claude/agents/*.md`) | `README.md`, `docs/*.md`, `.claude/agents/*.md` |
| `test-runner` | Verification: `cargo test`, `swift test`, `xcodebuild build` | — (Read/Run only) |

## Invocation pattern

From the main agent via the `Agent` tool with `subagent_type: "rust-ffi" | "swift-ui" | "localizer" | "docs-translator" | "test-runner"`.

Typical wave:
1. `rust-ffi` adds fields/methods, regenerates bindings.
2. `swift-ui` builds the UI against the new FFI shape, maintains xcodeproj.
3. `localizer` and `docs-translator` run in parallel (UI strings vs. repo docs — disjoint files).
4. `test-runner` runs as the final check.

## Language convention

- **Repo documentation that lands on GitHub is English** — owned by `docs-translator`. `README.de.md` is the single intentional German counterpart and is kept as a translation (English is canonical).
- **App source strings stay German keys**, English as the catalog translation — owned by `localizer`. Separate layer, no contradiction.
- **Commit messages are English** going forward; historical commits are not rewritten.
- Agent ↔ main-agent communication stays German per the global `~/.claude/CLAUDE.md`.

## Karpathy hookup

These agents complement — they do NOT replace — the global `karpathy-planner` (pre-task) and `karpathy-reviewer` (post-task). Both remain responsible for plan + review; the repo agents are pure execution roles with a narrow scope (Karpathy 3).
