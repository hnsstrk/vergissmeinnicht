# Code-Review Welle 3 + Welle 4 - Vergissmeinnicht

Datum: 2026-05-10  
Reviewer: Codex  
Scope: `app/Vergissmeinnicht/Sources/VergissmeinnichtApp/` plus FFI-Grenze in `swift/VergissmeinnichtKit/` und `rust/vergissmeinnicht-core/`  
Verdict: **needs-fix**

## Executive Summary

Die App-Schicht ist insgesamt schlank und der `AppContainer` ist als zentraler UI-State-Holder erkennbar. FFI-Aufrufe laufen im App-Code überwiegend off-MainActor, aber Sync invalidiert den UI-State nicht, parallele Syncs sind nicht robust ausgeschlossen, und mehrere UI-Flows behandeln fehlgeschlagene Mutationen wie Erfolg. Der QuickCapture-Parser ist bewusst klein, erfüllt aber die angefragten Welle-4-Edge-Cases (`#foo`, `!1`, escaped spaces) nicht.

## Top-3-Findings

1. **High** - `app/Vergissmeinnicht/Sources/VergissmeinnichtApp/AppContainer.swift:95` - `sync(...)` refresht `pending` nach erfolgreichem FFI-Sync nicht. Remote-Änderungen bleiben bis zu einem manuellen Refresh unsichtbar.
2. **High** - `app/Vergissmeinnicht/Sources/VergissmeinnichtApp/QuickCaptureSheet.swift:107` - QuickCapture löscht die Eingabe nach `addTask`, auch wenn die FFI-Mutation fehlschlägt. Ähnliche Erfolgsannahmen existieren in Edit- und Annotation-Sheets.
3. **Medium** - `app/Vergissmeinnicht/Sources/VergissmeinnichtApp/QuickCaptureParser.swift:44` - Der Parser splittet nur nach Whitespace und erkennt `+tag`/`priority:value`, nicht aber die angefragten Formen `#foo`, `!1` oder escaped spaces.

## A) Threading & Concurrency

app/Vergissmeinnicht/Sources/VergissmeinnichtApp/AppContainer.swift:29 - `refresh()` ruft `store.listPending()` in `Task.detached(priority: .userInitiated)` auf und setzt `pending` danach im `@MainActor`-Container. Das schützt die UI vor dem synchronen FFI-Read. - Schweregrad: Info

app/Vergissmeinnicht/Sources/VergissmeinnichtApp/AppContainer.swift:84 - Mutationen laufen ebenfalls in `Task.detached`, danach wird `refresh()` awaitet. UI-State-Updates (`pending`, `lastError`) bleiben durch `@MainActor` korrekt isoliert. - Schweregrad: Info

app/Vergissmeinnicht/Sources/VergissmeinnichtApp/AppContainer.swift:95 - `sync(...)` setzt zwar `isSyncing`, startet den synchronen FFI-Call aber nur über Caller-Disziplin. Die Methode selbst verhindert keinen zweiten parallelen Sync; `RootView`, `SyncStatusView` und `SettingsView` können mehrere Tasks starten. Der erste beendete Sync setzt `isSyncing = false`, obwohl ein zweiter noch laufen kann. Empfehlung: am Anfang von `sync` mit `guard !isSyncing else { return }` serialisieren oder einen eigenen Sync-Task/Actor verwenden; `defer { isSyncing = false }` nutzen. - Schweregrad: Medium

app/Vergissmeinnicht/Sources/VergissmeinnichtApp/VergissmeinnichtApp.swift:10 - `AppContainer()` und damit `TaskStore(dbPath:)` laufen synchron während App-Initialisierung. Die Rust-Seite öffnet SQLite über `rt.block_on` (`rust/vergissmeinnicht-core/src/lib.rs:82`). Das ist kein normaler UI-Action-Freeze, kann aber den Start blockieren, wenn Storage langsam oder beschädigt ist. Empfehlung: initialen Lade-/Fehlerzustand statt `fatalError` und Store-Öffnung außerhalb des harten App-Init-Pfads. - Schweregrad: Low

swift/VergissmeinnichtKit/Sources/VergissmeinnichtKit/vergissmeinnicht_core.swift:484 - `TaskStore` ist generiert als `@unchecked Sendable`; die App verlässt sich deshalb korrekt auf eine kleine Fassade (`AppContainer`) statt FFI direkt aus Views aufzurufen. Empfehlung: diese Grenze beibehalten und keine direkten FFI-Aufrufe in Views einführen. - Schweregrad: Info

## B) State-Konsistenz

app/Vergissmeinnicht/Sources/VergissmeinnichtApp/AppContainer.swift:13 - `AppContainer` enthält die geforderten zentralen State-Felder `pending`, `lastError`, `isSyncing`, `lastSyncDate` und einen `mutate(_:)`-Helper. - Schweregrad: Info

app/Vergissmeinnicht/Sources/VergissmeinnichtApp/AppContainer.swift:81 - `mutate(_:)` refresht `pending` nach erfolgreicher Mutation. Das ist der richtige zentrale Invalidierungsmechanismus für `addTask`, `markDone`, `modifyDescription`, `deleteTask` und `addAnnotation`. - Schweregrad: Info

app/Vergissmeinnicht/Sources/VergissmeinnichtApp/AppContainer.swift:95 - Nach erfolgreichem Sync wird nur `lastSyncDate` gesetzt, aber `pending` nicht neu geladen. Da Sync die Replica verändern kann, bleiben Liste, Selektion und Detailansicht potentiell stale. Empfehlung: nach erfolgreichem Sync `await refresh()` ausführen oder Sync selbst über denselben Mutations-/Invalidierungsmechanismus führen. - Schweregrad: High

app/Vergissmeinnicht/Sources/VergissmeinnichtApp/RootView.swift:42 - `RootView` startet `refresh()` und `syncIfConfigured()` in zwei unabhängigen `.task`-Modifiern. Das ist funktional, kann aber beim Start zu konkurrierenden FFI-Reads/Sync führen; Rust serialisiert per Mutex, die UI sieht aber je nach Reihenfolge erst Pre-Sync-Daten und nach Sync keinen automatischen Refresh. Empfehlung: Startsequenz explizit ordnen: erst initial refresh für schnelle Anzeige, dann sync, danach refresh. - Schweregrad: Medium

rust/vergissmeinnicht-core/src/lib.rs:248 - Rust hält den Replica-Mutex während `replica.sync(...).await` (`rust/vergissmeinnicht-core/src/lib.rs:254`). Das verhindert Datenkorruption innerhalb einer `TaskStore`-Instanz, blockiert aber alle lokalen Reads/Writes während langsamem Netzwerk-Sync. Empfehlung: UX während Sync bewusst sperren oder Sync als lange Operation modellieren; wenn TaskChampion es erlaubt, Server-Aufbau vor dem Replica-Lock erledigen. - Schweregrad: Medium

## C) QuickCapture-Parser

app/Vergissmeinnicht/Sources/VergissmeinnichtApp/QuickCaptureParser.swift:44 - Der Parser ist robust gegen leeren Input und Whitespace-only-Input: `split` liefert keine Tokens, `description` wird leer, der Save-Button bleibt deaktiviert. - Schweregrad: Info

app/Vergissmeinnicht/Sources/VergissmeinnichtApp/QuickCaptureParser.swift:53 - Tags werden nur als `+tag` erkannt. Der Review-Fokus nennt explizit `#foo`; solche Tokens landen aktuell in der Description. Empfehlung: entweder `#tag` zusätzlich unterstützen oder UI/Docs konsistent auf `+tag` festlegen und das Requirement klären. - Schweregrad: Medium

app/Vergissmeinnicht/Sources/VergissmeinnichtApp/QuickCaptureParser.swift:51 - Priorität wird nur als `priority:value` erkannt. Die angefragte Kurzform `!1` wird nicht erkannt und landet in der Description. Empfehlung: Kurzform parsen oder bewusst ablehnen und diagnostizieren. - Schweregrad: Medium

app/Vergissmeinnicht/Sources/VergissmeinnichtApp/QuickCaptureParser.swift:34 - Escaping und Quoting sind explizit nicht implementiert. Dadurch wird `hello\ world +foo` als zwei Description-Tokens gespeichert und escaped spaces werden nicht als ein Feld behandelt. Empfehlung: für Welle 4 mindestens Backslash-escaped spaces in der Tokenisierung unterstützen, wenn das Requirement gilt; sonst aus Scope und UI-Hinweisen entfernen. - Schweregrad: Medium

app/Vergissmeinnicht/Sources/VergissmeinnichtApp/QuickCaptureParser.swift:69 - Malformed Metadata wie `project:` oder `due:` wird nicht als leeres Feld akzeptiert, sondern fällt in die Description zurück. Das ist sicher und crashfrei, aber es gibt keine Diagnostics für den User. Empfehlung: bei späterer Persistenz von Metadata strukturierte Parser-Diagnostics einführen. - Schweregrad: Low

## D) Karpathy-Prinzipien

app/Vergissmeinnicht/Sources/VergissmeinnichtApp/TaskListViewModel.swift:17 - ViewModel hält nur Suchtext und Selektion; die FFI-Daten bleiben im `AppContainer`. Das ist eine gute, minimale Trennung ohne zweite Source of Truth. - Schweregrad: Info

app/Vergissmeinnicht/Sources/VergissmeinnichtApp/AppContainer.swift:39 - Die App persistiert in QuickCapture bewusst nur die Description, weil die FFI Tags/Project/Due/Priority noch nicht annimmt. Das ist chirurgisch und vermeidet Fake-Persistenz. - Schweregrad: Info

app/Vergissmeinnicht/Sources/VergissmeinnichtApp/QuickCaptureSheet.swift:45 - Der Hinweistext erklärt im UI technische Wellen-/FFI-Details. Das ist für Entwickler transparent, aber für Nutzer unnötige Implementierungsoberfläche. Empfehlung: entweder kürzen oder nur die nicht persistierten Vorschau-Felder still als Preview behandeln. - Schweregrad: Low

app/Vergissmeinnicht/Sources/VergissmeinnichtApp/DetailView.swift:10 - Annotationen können hinzugefügt, aber nicht angezeigt werden, weil die FFI keine Liste liefert. Das ist als Übergang sauber kommentiert; es kann aber UX-seitig verwirren, wenn ein erfolgreicher Add keine sichtbare Änderung erzeugt. Empfehlung: bis zur FFI-Erweiterung nach Erfolg eine kurze Statusmeldung anzeigen. - Schweregrad: Low

## E) Error-Handling

app/Vergissmeinnicht/Sources/VergissmeinnichtApp/RootView.swift:56 - `lastError` wird in der Hauptansicht sichtbar als Overlay angezeigt. Fehler werden also nicht vollständig verschluckt. - Schweregrad: Info

app/Vergissmeinnicht/Sources/VergissmeinnichtApp/QuickCaptureSheet.swift:107 - `save()` wartet zwar auf `container.addTask`, löscht danach aber immer `input`, auch wenn `lastError` gesetzt wurde. Der User verliert bei FFI-Fehlern die Eingabe. Empfehlung: Container-Mutationen `async throws` oder `Bool` zurückgeben lassen und Eingabe nur bei Erfolg löschen. - Schweregrad: High

app/Vergissmeinnicht/Sources/VergissmeinnichtApp/EditDescriptionSheet.swift:56 - Das Edit-Sheet dismissed nach `modifyDescription` immer, auch bei Fehler. Dadurch sieht der User den Fehler nur indirekt im Root-Overlay und muss den Edit erneut öffnen. Empfehlung: Sheet offen lassen und lokale Fehlermeldung anzeigen, bis die Mutation erfolgreich war. - Schweregrad: High

app/Vergissmeinnicht/Sources/VergissmeinnichtApp/AnnotationEditor.swift:62 - Das Annotation-Sheet dismissed nach `addAnnotation` immer, auch bei Fehler. Bei Storage-/NotFound-Fehlern geht der Annotationstext verloren. Empfehlung: wie bei QuickCapture Erfolg explizit zurückmelden und bei Fehler offen bleiben. - Schweregrad: High

app/Vergissmeinnicht/Sources/VergissmeinnichtApp/AppContainer.swift:88 - Mutationsfehler werden mit `String(describing: error)` gespeichert, Sync-Fehler mit `localizedDescription` (`AppContainer.swift:105`). Die generierte FFI-Fehlerbeschreibung ist `String(reflecting: self)` (`swift/VergissmeinnichtKit/Sources/VergissmeinnichtKit/vergissmeinnicht_core.swift:857`). Empfehlung: handgeschriebenes Error-Mapping im App-Layer einführen: kurze User-Message, technische Details optional fürs Log. - Schweregrad: Medium

app/Vergissmeinnicht/Sources/VergissmeinnichtApp/SettingsView.swift:59 - `runTestSync()` übernimmt `container.lastError` in eine Statusmeldung und erlaubt danach erneutes Auslösen. Recovery durch Retry ist möglich. - Schweregrad: Info

## Positive Aspekte

- `AppContainer` ist klar als zentrale Fassade vor dem FFI-Layer angelegt.
- UI-State wird durch `@MainActor` und SwiftUI `@State` sauber auf dem MainActor gehalten.
- FFI-Reads und -Writes laufen im App-Code nicht direkt synchron in SwiftUI-Button-Closures.
- Jede normale Mutation läuft über denselben `mutate(_:)`-Pfad und refresht anschließend `pending`.
- QuickCapture ist als reine Parser-Funktion ohne Seiteneffekte testbar.
- Keychain-Zugriff ist klein gehalten und speichert Sync-Credentials nicht in UserDefaults.

## Empfehlungen fuer naechste Schritte

1. `sync(...)` serialisieren, mit `defer` absichern und nach erfolgreichem Sync `pending` refreshen.
2. AppContainer-Mutationen so ändern, dass UI-Flows Erfolg/Fehler unterscheiden können (`async throws` oder Result). Eingaben und Sheets nur bei Erfolg zurücksetzen.
3. QuickCapture-Parser an das tatsächliche Welle-4-Requirement angleichen: `#tag`, `!priority`, escaped spaces und Parser-Tests ergänzen.
4. Startsequenz in `RootView` ordnen: initialer schneller Refresh, optionaler Sync, danach garantierter Refresh.
5. User-taugliches Error-Mapping für `VmError` einführen und Debug-Repräsentationen aus sichtbaren UI-Meldungen entfernen.
6. App-Tests für Parser und Container-State ergänzen, besonders Fehlerpfade und parallele Sync-/Mutation-Szenarien.

## Verdict

**needs-fix**

Die Welle-3/4-App ist nicht grundsätzlich falsch geschnitten: zentrale State-Fassade, MainActor-Isolation und off-MainActor-FFI-Aufrufe sind vorhanden. Vor Freigabe sollten aber Sync-State-Invalidierung, Fehler-Retention in den Edit-Flows und die QuickCapture-Requirement-Lücken geschlossen werden.
