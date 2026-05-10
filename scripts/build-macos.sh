#!/usr/bin/env bash
# Builds the Rust core as a static lib for arm64 macOS, generates Swift bindings
# via UniFFI, and packages everything as an XCFramework consumable by SwiftPM.
#
# arm64-only by design (spike on Apple Silicon). Universal Binary is a later concern.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUST_DIR="$REPO_ROOT/rust"
BINDINGS_DIR="$REPO_ROOT/swift-bindings/generated"
SWIFT_SOURCES_DIR="$REPO_ROOT/swift/VergissmeinnichtKit/Sources/VergissmeinnichtKit"
XCFRAMEWORK_OUT="$REPO_ROOT/swift/VergissmeinnichtKit/VergissmeinnichtCoreFFI.xcframework"
LIB_NAME="vergissmeinnicht_core"

echo "==> Cleaning previous artifacts"
rm -rf "$BINDINGS_DIR" "$XCFRAMEWORK_OUT"
mkdir -p "$BINDINGS_DIR"

echo "==> Building Rust static lib (release, arm64-darwin host, deployment target 14.0)"
(cd "$RUST_DIR" && MACOSX_DEPLOYMENT_TARGET=14.0 cargo build --release -p vergissmeinnicht-core)

STATIC_LIB="$RUST_DIR/target/release/lib${LIB_NAME}.a"
DYLIB="$RUST_DIR/target/release/lib${LIB_NAME}.dylib"

if [[ ! -f "$STATIC_LIB" ]]; then
    echo "ERROR: expected static lib at $STATIC_LIB"
    exit 1
fi

echo "==> Generating Swift bindings via embedded uniffi-bindgen"
(cd "$RUST_DIR" && cargo run --release --quiet --bin uniffi-bindgen -- \
    generate \
    --library "$DYLIB" \
    --language swift \
    --out-dir "$BINDINGS_DIR")

echo "==> Generated files:"
ls -1 "$BINDINGS_DIR"

echo "==> Assembling XCFramework headers directory"
HEADERS_DIR="$BINDINGS_DIR/headers"
mkdir -p "$HEADERS_DIR"
cp "$BINDINGS_DIR/${LIB_NAME}FFI.h" "$HEADERS_DIR/"
# UniFFI emits the modulemap with crate-specific name; xcodebuild expects
# exactly "module.modulemap" in the headers dir.
cp "$BINDINGS_DIR/${LIB_NAME}FFI.modulemap" "$HEADERS_DIR/module.modulemap"

echo "==> Building XCFramework"
xcodebuild -create-xcframework \
    -library "$STATIC_LIB" \
    -headers "$HEADERS_DIR" \
    -output "$XCFRAMEWORK_OUT"

echo "==> Copying Swift wrapper into SwiftPM sources"
mkdir -p "$SWIFT_SOURCES_DIR"
cp "$BINDINGS_DIR/${LIB_NAME}.swift" "$SWIFT_SOURCES_DIR/"

echo "==> Done."
echo "    XCFramework: $XCFRAMEWORK_OUT"
echo "    Swift wrapper: $SWIFT_SOURCES_DIR/${LIB_NAME}.swift"
