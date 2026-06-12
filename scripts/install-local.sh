#!/usr/bin/env bash
# Local install pipeline: Rust core → Swift bindings → Release-Build → /Applications/.
#
# Single command für den Author-Workflow nach Code-Änderungen. Ersetzt die manuelle
# Sequenz aus build-macos.sh + xcodebuild + ditto + lsregister + open.
#
# Optionen:
#   --no-restart   App nach Install nicht starten (z. B. wenn nur das Bundle gebraucht wird)
#   --skip-rust    Rust-/Bindings-Build überspringen (nur Swift-Änderungen)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$REPO_ROOT/app/Vergissmeinnicht"
BUILD_DIR="$APP_DIR/build"
APP_BUNDLE="$BUILD_DIR/Build/Products/Release/Vergissmeinnicht.app"
INSTALL_TARGET="/Applications/Vergissmeinnicht.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"

SKIP_RUST=0
RESTART=1
for arg in "$@"; do
    case "$arg" in
        --skip-rust)  SKIP_RUST=1 ;;
        --no-restart) RESTART=0   ;;
        *) echo "Unbekannte Option: $arg" >&2; exit 64 ;;
    esac
done

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

if [[ $SKIP_RUST -eq 0 ]]; then
    step "Rust-Core + Swift-Bindings + XCFramework"
    bash "$REPO_ROOT/scripts/build-macos.sh"
else
    step "Rust-Build übersprungen (--skip-rust)"
fi

step "Release-Build der App"
cd "$APP_DIR"
# Ad-hoc-Signierung (CODE_SIGN_IDENTITY="-" aus dem pbxproj) bleibt aktiv:
# ohne Signierung fehlt das app-sandbox-Entitlement und die App liest/schreibt
# unsandboxed Pfade statt des Containers (siehe docs/building.md).
xcodebuild \
    -scheme Vergissmeinnicht \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    build \
    | tail -5

if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "FEHLER: Bundle nicht gefunden unter $APP_BUNDLE" >&2
    exit 1
fi
BUNDLE_SIZE=$(du -sh "$APP_BUNDLE" | cut -f1)
echo "Bundle gebaut: $APP_BUNDLE ($BUNDLE_SIZE)"

step "Aktuell laufende Instanz beenden"
if pgrep -f "Vergissmeinnicht.app" > /dev/null; then
    pkill -f "Vergissmeinnicht.app" || true
    sleep 1
fi

step "Installation nach /Applications/"
rm -rf "$INSTALL_TARGET"
ditto "$APP_BUNDLE" "$INSTALL_TARGET"
"$LSREGISTER" -f "$INSTALL_TARGET"
killall Dock

if [[ $RESTART -eq 1 ]]; then
    step "App starten"
    sleep 2
    open "$INSTALL_TARGET"
    sleep 2
    if pgrep -f "Vergissmeinnicht.app" > /dev/null; then
        echo "OK — App läuft (PID $(pgrep -f Vergissmeinnicht.app))"
    else
        echo "WARNUNG: App nicht im Process-Listing nach open" >&2
        exit 1
    fi
else
    step "App nicht gestartet (--no-restart)"
fi

step "Fertig"
echo "Installiert unter: $INSTALL_TARGET"
