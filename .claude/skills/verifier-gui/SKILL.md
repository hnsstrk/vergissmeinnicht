---
name: verifier-gui
description: >-
  Drive and screenshot the running Vergissmeinnicht macOS app to verify UI
  changes end-to-end. Use after building the app when a change needs visual or
  interactive verification (new views, toolbar items, selection states,
  dialogs) — launches the Debug build, selects sidebar/list rows via the
  accessibility API, sends keyboard shortcuts, and captures window-scoped
  screenshots.
---

# GUI verification for Vergissmeinnicht

Proven recipe for observing UI changes in the running app. All commands assume
the repo root as working directory.

## Build & launch

```bash
xcodebuild -project app/Vergissmeinnicht/Vergissmeinnicht.xcodeproj \
  -scheme Vergissmeinnicht -configuration Debug \
  -derivedDataPath app/Vergissmeinnicht/build build
open app/Vergissmeinnicht/build/Build/Products/Debug/Vergissmeinnicht.app
```

The Debug build uses the same sandbox container as the installed app (real
user data). Read-only interactions and cancelled dialogs are fine; never
confirm destructive dialogs and never leave test tasks behind. Quit the app
when done (`osascript -e 'tell application "Vergissmeinnicht" to quit'`) if it
was not running before.

## Screenshots — window-scoped only

**Never use full-screen `screencapture -x` without `-l`** — it captures
whatever else is on screen (password managers, mail). Get the window ID via
CoreGraphics (System Events' `AXWindowNumber` is not readable):

```bash
cat > /tmp/winid.swift <<'EOF'
import CoreGraphics
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
for w in list where (w["kCGWindowOwnerName"] as? String) == "Vergissmeinnicht" {
    print(w["kCGWindowNumber"] as! Int)
}
EOF
WID=$(swift /tmp/winid.swift | head -1)
screencapture -x -o -l "$WID" shot.png
```

The window ID changes on every relaunch — re-resolve it after restarting.

## Driving the UI (accessibility API)

Raise and resize first (window may sit on a secondary display):

```applescript
tell application "Vergissmeinnicht" to activate
tell application "System Events" to tell process "Vergissmeinnicht"
    set size of window 1 to {1500, 850}
end tell
```

Known accessibility paths (verified; one extra `splitter group` level appears
when the detail column / inspector is visible):

- Sidebar rows: `outline 1 of scroll area 1 of group 1 of splitter group 1 of
  group 1 of window 1` — select via `set selected of row N ... to true`
  (clicking the row's static text does NOT change selection).
- Task list: `outline 1 of scroll area 2 of group 1 of splitter group 1 of
  group 2 of splitter group 1 of group 1 of window 1` (scroll area 1 is the
  forecast strip when present).
- Multi-selection: setting `AXSelectedRows` does not work on SwiftUI lists.
  Instead focus the list (`set focused of tbl to true`) and send
  `key code 125 using {shift down}` (⇧↓) repeatedly.
- Keyboard shortcuts: `keystroke "0" using {option down, command down}`
  (⌥⌘0 toggles the detail column).
- Buttons inside the inspector are often not addressable by name — click by
  coordinates relative to the window position (`position of window 1` +
  offsets read from a fresh screenshot).
- Confirmation dialogs block app quit; dismiss with `key code 53` (Escape).

## Verifying persistence

`@AppStorage` values live in the standard defaults domain:

```bash
defaults read de.hnsstrk.vergissmeinnicht showDetailColumn
```

Quit and relaunch the app to verify a setting survives a restart.
