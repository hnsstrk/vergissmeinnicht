---

Unsigned **arm64-only** build for Apple Silicon. Requires macOS 14 (Sonoma) or later.

### Install

```sh
# 1. Download Vergissmeinnicht-__TAG__-arm64.zip and unzip
unzip Vergissmeinnicht-__TAG__-arm64.zip

# 2. Drag Vergissmeinnicht.app to /Applications

# 3. Remove the quarantine flag (build is not notarized)
xattr -dr com.apple.quarantine /Applications/Vergissmeinnicht.app

# 4. Open
open /Applications/Vergissmeinnicht.app
```

Without step 3 Gatekeeper will block the app with "Apple could not verify ...".
The build is not signed by an Apple Developer ID, so this is expected. The
checksum file (`.sha256`) lets you verify the download.

### From source

See [`docs/building.md`](https://github.com/hnsstrk/vergissmeinnicht/blob/main/docs/building.md).
