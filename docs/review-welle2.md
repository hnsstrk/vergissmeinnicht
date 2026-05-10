# Code-Review Welle 2 — Vergissmeinnicht App-Skelett

## A) Sandbox-Entitlements
app/Vergissmeinnicht/Resources/Vergissmeinnicht.entitlements:5 — `com.apple.security.app-sandbox` ist gesetzt und auf `true`; die App läuft damit grundsätzlich sandboxed. — Schweregrad: info

app/Vergissmeinnicht/Resources/Vergissmeinnicht.entitlements:7 — `com.apple.security.network.client` ist aktiv, aber im App-Skelett unter `Sources/VergissmeinnichtApp/` wird keine Netzwerkfunktionalität verwendet. Falls Welle 2 nur lokale Replica/FFI abdecken soll, ist das ein unnötiges App-Store-Entitlement. — Schweregrad: warn

app/Vergissmeinnicht/project.yml:49 — Die Entitlements-Datei ist in XcodeGen per `CODE_SIGN_ENTITLEMENTS: Resources/Vergissmeinnicht.entitlements` referenziert; dieselbe Referenz steht auch im generierten Projekt. — Schweregrad: info

app/Vergissmeinnicht/Sources/VergissmeinnichtApp/AppContainer.swift:41 — Die vorhandene lokale Replica-Funktionalität nutzt `applicationSupportDirectory` im User-Container und braucht kein zusätzliches User-Selected-File- oder App-Group-Entitlement. — Schweregrad: info

## B) Bundle-Konformität
app/Vergissmeinnicht/project.yml:37 — Bundle-ID ist als `de.hnsstrk.vergissmeinnicht` gesetzt und konsistent mit der dokumentierten Container-Pfad-Annahme. — Schweregrad: info

app/Vergissmeinnicht/Resources/Info.plist:11 — `CFBundleIdentifier` delegiert korrekt auf `$(PRODUCT_BUNDLE_IDENTIFIER)`, dadurch bleibt die Bundle-ID mit den Build Settings konsistent. — Schweregrad: info

app/Vergissmeinnicht/Resources/Info.plist:19 — `CFBundleShortVersionString` ist vorhanden und wird aus `$(MARKETING_VERSION)` befüllt; `0.1.0` ist in `project.yml` gesetzt. — Schweregrad: info

app/Vergissmeinnicht/Resources/Info.plist:21 — `CFBundleVersion` ist vorhanden und wird aus `$(CURRENT_PROJECT_VERSION)` befüllt; `1` ist in `project.yml` gesetzt. — Schweregrad: info

app/Vergissmeinnicht/project.yml:33 — `LSUIElement` ist auf `false` gesetzt. Für die angeforderte MenuBarApp ohne Dock-Icon müsste der Wert `true` sein; aktuell erscheint die App als normale Dock-App. — Schweregrad: fail

app/Vergissmeinnicht/Resources/Info.plist:31 — `NSPrincipalClass` ist nicht gesetzt. Für eine SwiftUI-`@main`-App ist das nicht erforderlich; es gibt keinen Hinweis auf eine falsche Principal-Class. — Schweregrad: info

## C) XcodeGen / project.yml
app/Vergissmeinnicht/project.yml:13 — Es gibt genau ein macOS-Application-Target `Vergissmeinnicht`; Sources, Assets, Package-Dependency, Info.plist und Entitlements sind im YAML benannt. — Schweregrad: info

app/Vergissmeinnicht/project.yml:17 — Deployment-Target ist `14.0` und erfüllt damit die Mindestanforderung macOS 13.0 für `MenuBarExtra`. — Schweregrad: info

app/Vergissmeinnicht/project.yml:45 — `CODE_SIGN_STYLE: Manual`, leeres `DEVELOPMENT_TEAM`, `CODE_SIGN_IDENTITY: "-"` und `ENABLE_HARDENED_RUNTIME: NO` sind nicht App-Store-tauglich. Für Release/App Store fehlen echte Team-/Signing-/Provisioning-Einstellungen. — Schweregrad: fail

app/Vergissmeinnicht/project.yml:44 — `ONLY_ACTIVE_ARCH: YES` ist global gesetzt und damit auch im Release-Target wirksam. Das ist für reproduzierbare Release-/Archive-Builds ungünstig, auch wenn `ARCHS: arm64` aktuell bewusst gesetzt ist. — Schweregrad: warn

app/Vergissmeinnicht/Vergissmeinnicht.xcodeproj/project.pbxproj:85 — Das generierte Target hat nur `Sources` und `Frameworks` als Build Phases; eine `Resources`-Build-Phase für `Resources/Assets.xcassets` fehlt im `pbxproj`. Die `project.yml` referenziert die Assets, aber das generierte Projekt bildet sie nicht sichtbar als Build Phase ab. — Schweregrad: warn

## D) Replica-Pfad
app/Vergissmeinnicht/project.yml:19 — Referenzierter Source-Pfad `Sources` existiert. — Schweregrad: info

app/Vergissmeinnicht/project.yml:21 — Referenzierter Resource-Pfad `Resources/Assets.xcassets` existiert. — Schweregrad: info

app/Vergissmeinnicht/project.yml:26 — Referenzierte `Resources/Info.plist` existiert. — Schweregrad: info

app/Vergissmeinnicht/project.yml:49 — Referenzierte `Resources/Vergissmeinnicht.entitlements` existiert. — Schweregrad: info

app/Vergissmeinnicht/project.yml:11 — Lokale Package-Referenz `../../swift/VergissmeinnichtKit` existiert relativ zu `app/Vergissmeinnicht`. — Schweregrad: info

## E) Karpathy-Prinzipien
app/Vergissmeinnicht/Sources/VergissmeinnichtApp/VergissmeinnichtApp.swift:17 — Das Skelett startet sowohl ein `WindowGroup` als auch ein `MenuBarExtra`. Für ein reines Menu-Bar-Skelett ist das mehr Oberfläche als nötig und erklärt mit `LSUIElement: false` das Dock-Icon. — Schweregrad: warn

app/Vergissmeinnicht/Sources/VergissmeinnichtApp/VergissmeinnichtApp.swift:24 — Der Text `QuickCapture (Welle 4)` ist in Welle 2 bereits sichtbar, obwohl die Funktion nur als Stub existiert. Das ist spekulative UI und sollte entweder neutral benannt oder erst in der passenden Welle eingeführt werden. — Schweregrad: warn

app/Vergissmeinnicht/Sources/VergissmeinnichtApp/AppContainer.swift:12 — `AppContainer` ist klar und chirurgisch: Replica-Pfad, `TaskStore`, Pending-Liste und Fehlerstatus sind eng auf das Skelett begrenzt. — Schweregrad: info

## F) Allgemeine Swift/iOS-Qualität
app/Vergissmeinnicht/Sources/VergissmeinnichtApp/VergissmeinnichtApp.swift:12 — `fatalError` beim Initialisieren des `AppContainer` beendet die App hart. Für ein App-Store-fähiges macOS-UI sollte ein initialer Fehlerzustand angezeigt werden, damit ein beschädigter Replica-Pfad nicht zum Crash führt. — Schweregrad: warn

app/Vergissmeinnicht/Sources/VergissmeinnichtApp/AppContainer.swift:27 — `Task.detached` ruft `store.listPending()` außerhalb des MainActor auf. Das ist gut für UI-Responsiveness, setzt aber voraus, dass `TaskStore`/FFI thread-safe und `Sendable`-kompatibel ist; das sollte durch das Package abgesichert sein. — Schweregrad: warn

app/Vergissmeinnicht/Sources/VergissmeinnichtApp/RootView.swift:18 — `List(container.pending, id: \.uuid)` ist sauber und minimal; Naming und SwiftUI-Struktur sind nachvollziehbar. — Schweregrad: info

app/Vergissmeinnicht/Sources/VergissmeinnichtApp/VergissmeinnichtApp.swift:22 — `MenuBarExtra` ist grundsätzlich korrekt implementiert und nutzt `.menuBarExtraStyle(.window)`, kollidiert aber mit der Bundle-Konfiguration `LSUIElement: false` für eine Dock-freie Menu-Bar-App. — Schweregrad: warn

## Verdict
needs-fix

Top-3-Findings:

1. fail — app/Vergissmeinnicht/project.yml:33 — `LSUIElement` ist `false`; für die geforderte MenuBarApp ohne Dock-Icon muss es `true` sein.
2. fail — app/Vergissmeinnicht/project.yml:45 — Signing ist ad-hoc/manuell ohne Team und Hardened Runtime; das ist nicht App-Store-tauglich.
3. warn — app/Vergissmeinnicht/Resources/Vergissmeinnicht.entitlements:7 — `network.client` ist aktiv, obwohl im Welle-2-App-Skelett keine Netzwerkfunktionalität sichtbar ist.
