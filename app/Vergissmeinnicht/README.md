# Vergissmeinnicht — App-Target

SwiftUI-App-Skelett. Konsumiert das lokale `VergissmeinnichtKit`-SwiftPM-Package
(`../../swift/VergissmeinnichtKit/`).

## Build

```sh
cd app/Vergissmeinnicht
xcodegen           # erzeugt Vergissmeinnicht.xcodeproj aus project.yml
open Vergissmeinnicht.xcodeproj
```

CLI-Build:

```sh
xcodebuild -project Vergissmeinnicht.xcodeproj \
           -scheme Vergissmeinnicht \
           build
```

## Architektur (Welle 2 — Skelett)

- `Sources/VergissmeinnichtApp/VergissmeinnichtApp.swift` — `@main` App-Struct,
  Hauptfenster + `MenuBarExtra` (QuickCapture-Stub).
- `Sources/VergissmeinnichtApp/AppContainer.swift` — `@Observable`-Wrapper um
  `TaskStore`. Öffnet die Replica im Sandbox-Container
  (`~/Library/Containers/de.hnsstrk.vergissmeinnicht/Data/Library/Application Support/vergissmeinnicht/replica/`)
  und kapselt FFI-Calls in `Task.detached`.
- `Sources/VergissmeinnichtApp/RootView.swift` — Hauptfenster, listet
  `pending`-Tasks (Smoketest gegen FFI).
- `Resources/Vergissmeinnicht.entitlements` — App-Sandbox + Network-Client.

## Settings

- Bundle-ID: `de.hnsstrk.vergissmeinnicht`
- Min macOS: 14.0
- Swift: 6.0, strict concurrency
- Code-Signing: ad-hoc (`-`), Hardened-Runtime aus (kommt mit Notarization)
- Architektur: arm64 (Rust-Binary aktuell arm64-only)
