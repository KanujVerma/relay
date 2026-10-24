# Synthetic storage research probe

This is an opt-in comparison artifact, not a normal test, feature implementation or private-data collector. It uses only hardcoded fictional text in temporary in-memory databases. There are no app, capture, account, Keychain, profile or network-model calls. It does not write History storage or modify the repository. GRDB is cloned only to the owned temporary reproduction directory; no dependency is added to Relay.

Measured: Swift 6.4 (`swiftlang-6.4.0.34.1`), arm64, installed SDK/runtime macOS 27; exact GRDB v7.11.1 commit `b83108d10f42680d78f23fe4d4d80fc88dab3212`; system SQLite 3.54.0 with deserialize available. Deployment target macOS 14 is a compile setting, not an older-OS execution result. The source is original Relay research code, not copied upstream implementation.

`Probe.swift` checks direct C serialize/restore and integrity, enforced deserialized size limit and rollback; GRDB multi-page backup abort preserving destination, successful backup/restore, writable restored state and size-limit rollback; actual close held behind real writer work; rejected read after close; and no SQLite/WAL/journal/temp files in the owned working directory or TMPDIR. It exercises no production History schema or encryption. The current actual output is [result.txt](result.txt).

From the design branch repository root, opt in to this reproduction (requires a supported Swift toolchain, macOS SQLite headers and public GitHub access for the exact upstream checkout):

```sh
task_history_probe=$(mktemp -d /private/tmp/relay-history-repro.XXXXXX)
git clone --depth 1 --branch v7.11.1 https://github.com/groue/GRDB.swift.git "$task_history_probe/GRDB"
git -C "$task_history_probe/GRDB" rev-parse HEAD
# Must print b83108d10f42680d78f23fe4d4d80fc88dab3212 before continuing.
mkdir -p "$task_history_probe/Probe/Sources/StorageProbe" "$task_history_probe/contained/tmp"
cp docs/evidence/2026-10-23-history-storage/Probe.swift "$task_history_probe/Probe/Sources/StorageProbe/main.swift"
cp docs/evidence/2026-10-23-history-storage/ProbePackage.swift.txt "$task_history_probe/Probe/Package.swift"
env CLANG_MODULE_CACHE_PATH="$task_history_probe/clang-cache" \
    SWIFT_MODULECACHE_PATH="$task_history_probe/swift-cache" \
    swift build --disable-sandbox --package-path "$task_history_probe/Probe" \
    --scratch-path "$task_history_probe/build" --cache-path "$task_history_probe/cache" \
    --config-path "$task_history_probe/config" --security-path "$task_history_probe/security"
(cd "$task_history_probe/contained" && \
    env TMPDIR="$task_history_probe/contained/tmp" "$task_history_probe/build/debug/StorageProbe")
```

`--disable-sandbox` here avoids nested SwiftPM sandbox creation failing in the already restricted development environment. The manifest is a local-only package dependency on the pinned cloned source; no plugin or application is invoked. Build/cache paths are outside the containment directory. Do not infer global filesystem containment, swap exclusion or secure erase from the directory assertion. Do not run this against a private/real database.

All waits in the synthetic held-writer check are bounded. A failed assertion is a failing process, not a skipped test or successful timeout. The 100ms unfinished-close observation is combined with source inspection and the actual release/join/read-after-close outcome; it is not a latency target. Release/toolchain/platform and maximum-size production tests remain necessary after the design is approved.
