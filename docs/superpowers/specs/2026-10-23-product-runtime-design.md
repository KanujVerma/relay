# Self-contained Relay runtime design

2026-10-23. Research/design checkpoint only. Own clone `work/relay-product-runtime`, branch `feature/self-contained-runtime-2026-10-23`, CLEAN at frozen `1f8e7fbc7e4c7a2f925e1380ddec67f46c5fc3a7`. Read root direction `docs/superpowers/specs/2026-10-23-product-runtime-direction.md` at root5de9a318. No runtime files, dependency environment or Python interpreter build changed/fetched in this phase. Controller approved the exact resolver/layout, isolated pinned arm64 interpreter/PyInstaller onedir strategy, minimal production dependency resolution, existing build-session-app.sh ownership and test plan. Automatic P2 correction5aa65cb is published for narrow re-review; the packaging worker has resumed implementation. This document is the design checkpoint, not completed packaging evidence.

## Decision and frozen input proposal

Use **PyInstaller6.22.3, native arm64, console onedir mode** for one inherited-pipe helper. This reuses its mature bootloader, dependency graph, hooks, binary relocation and interpreter embedding. No per-launch archive extraction or onefile parent process is introduced into the existing actual-child shutdown/reap contract. Py2app0.28.10 is a reasonable Mac app packager but adds a second app-oriented launcher around this existing Swift app. A raw standalone Python shipment alone would leave custom dependency/bootstrap/relocation work. Use Python Standalone Builds only as the isolated build interpreter input, then PyInstaller to freeze the product.

Authoritative current verification corrected the preliminary3.14.8 recommendation: **CPython3.14.9** is the current patched3.14 release, published2026-10-21. Do not package local3.14.5 merely because it passes tests. Choose the GIL-enabled arm64 build, not free-threaded/3.15:

- Official source tag `v3.14.9`, annotated tag17acf00d155cb8536eca1c3af3a8404db648e37f, resolved commit **ead82c07db1f111d613926ed1b6667411d768125**.
- Standalone builder release **20261021**, commit **0c5e581b54a4736cdbbe68bdd6d7e571a1dca11e**.
- Exact artifact `cpython-3.14.9+20261021-aarch64-apple-darwin-install_only_stripped.tar.gz`, **26,705,294bytes**, SHA256 **9f8c3480b8f0db553c270db548e8a21ae8e39df412e5661d66e8050c5c6ed2a8**. [Pinned release](https://github.com/astral-sh/python-build-standalone/releases/tag/20261021), [official Python release](https://www.python.org/downloads/release/python-3149/). Public GitHub asset metadata/tag objects were read; the interpreter artifact has not been downloaded.
- PyInstaller macOS universal2 wheel1,071,847bytes, SHA256 **052f4a1cd4f81092ccb7a18fe8ebc9ecf832a5917317e39fb3775af4e959b253**. Source archive SHA256 **05eb2f5615503e72939a7224d68b4aff572c6b0438ee4a17d0a4b481f399362d**. Source/tests were read from that4.4MB archive in memory, without installation.

Pin the interpreter artifact and every build/runtime wheel hash in project-owned lock/manifest files. Extract only to a new private temporary build root; no Homebrew/system Python/client configuration changes. Validate interpreter version/arm64, `ssl`, `_sqlite3` and actual in-memory SQLite `serialize`/`deserialize` before dependency installation. Require binary wheels for native dependencies to avoid unrecorded local compiler/library variation. Build using the current source checkout, never a hard-coded peer snapshot. Native deployment target remains macOS15.2; inspect every collected Mach-O minimum OS/architecture and fail incompatible output rather than imply validation on older systems.

## Dependencies and inclusion

Direct production proposal: HTTPX0.28.1; PyJWT2.15.1 + cryptography50.0.2; docling-slim[format-pdf,format-docx]2.142.0; python-docx1.2.0; defusedxml0.7.1. Retain already measured Docling Core2.104.0, Docling Parse7.23.0 and pypdfium2 5.14.0 as constraints. Resolve all transitives in the isolated3.14.9 arm64 environment, save exact versions/hashes and licenses, then run actual native-PDF/DOCX tests before freezing. These are candidate pins verified against public package metadata, not an already tested combined lock.

Do not reuse `requirements-documents.txt` unchanged: it also installs MarkItDown/Magika/ONNX comparator paths. No torch/transformers/OCR/VLM/model/download extras, MarkItDown or Magika belong in this product. Minimal Docling is still substantial: its required Core package includes pandas, Pillow, Pydantic and JSON/schema/text dependencies. Do not promise a tiny helper or manually exclude a declared transitive required by the approved pipeline. Freeze only the necessary package imports/data/metadata and verify them, including Docling plugin metadata and PDFium native library. No model weights are required for the configured NativePdf pipeline.

Package actual `relay_spike` modules needed by the two real hosts plus auth/HTTPX/document adapters. Entry imports are explicit so dynamic lazy paths cannot silently disappear from analysis. Include four public EVALS JSONL files and the two ROLE_PACKS markdown files with preserved relative paths; current `publication_policy`, `benchmark` and `technical_gate` use `Path(__file__).resolve().parents[1]`. Add required third-party license/certificate/data files and a bounded generated runtime manifest. Do not copy whole repository/home, tests, raw research/Cluely material, private config/tokens/user files, caches, audio or225MB speech weights.

## Bundle and exact resolver seam

Proposed layout:

```text
Relay.app/Contents/MacOS/relay-panel-session
Relay.app/Contents/Helpers/RelayRuntime/relay-helper
Relay.app/Contents/Helpers/RelayRuntime/_internal/{embedded Python, frozen modules, native deps, EVALS, ROLE_PACKS, runtime-manifest.json, notices}
Relay.app/Contents/Resources/{KeyboardShortcuts_KeyboardShortcuts.bundle,FluidAudio_LuxTtsG2pResources.bundle}
Relay.app/Contents/Frameworks/{only actual non-system dynamic dependencies, if any}
```

Root approved the resolver seam, retaining module/`-m` argv compatibility:

```swift
public struct HelperRuntimeLocation: Sendable, Equatable {
    public let executable: URL
    public let arguments: [String]
    public let resourceRoot: URL
}
public enum HelperRuntimeResolver {
    public static func resolve(bundleURL: URL, arguments: [String], workingDirectory: URL) throws -> HelperRuntimeLocation
}
```

Fixed `HelperRuntimeError` categories provide useful bounded messages. In a normal packaged app, resolve only its own helper/data manifest and throw if missing/invalid; never fall back to cwd, `/usr/bin/env` or system Python inside a broken app. Explicit `--repository`/`--python` developer/test overrides remain a separate deliberate path, and existing non-app unit/CLI fixture behavior remains supported. Root owns model init/error/default hookup and its exact production error presentation, not this worker. No auth/profile/typed core changes.

The frozen entry accepts only existing `-m relay_spike.session_host` and `-m relay_spike.profile_bridge`, then calls their unchanged main functions with unchanged remaining args. Reject `-c`, arbitrary modules and unsupported forms before any host/capability operation. Keep stdout exclusively framed host output; fixed startup diagnostics go to stderr/nonzero exit. Account-bridge extensibility is a later reviewed allowlist addition, not generic interpreter execution now. Validate bundled immutable resources independently of cwd; PyInstaller documents module `__file__` and `_MEIPASS` paths for this purpose.

## Native resources/signing/relocation

Inspected exact existing compiled SwiftPM accessors: both first search `Bundle.main.resourceURL`, then owning bundle/CLI paths. Current prototype does not copy either bundle (approximately1.0MB +92KB). Embed them under Contents/Resources. Current executable has absolute temporary PackageFrameworks and Xcode toolchain LC_RPATH entries; remove build/toolchain rpaths and use bundle-relative loader/framework paths. `otool -L` currently shows no dynamic Nemo dependency and PackageFrameworks is empty; audit actual output instead of blindly copying a framework. Preserve public binary provenance/checksum if a future current build links it dynamically.

Enumerate all native helper/extension/framework Mach-O files, reject unbundled non-system absolute dependencies/build paths, repair install names/rpaths where necessary, sign nested code first and outer app last. Verify individual signatures plus outer `codesign --verify --deep --strict`; do not use deep signing to conceal a broken layout. Preserve symlinks required by PyInstaller rather than flatten them. Ad hoc signing is a local build proof, not notarization/Gatekeeper distribution approval; no paid certificate/notarization purchase is in scope.

Initial resource budget is an estimate: helper likely150-350MB uncompressed plus native binary/resources, with a provisional512MiB product ceiling. Measure actual total/largest components after the minimal locked build; escalate before adding weight/framework stacks to meet missing imports. No size/build/resource/latency claim has yet been measured for the proposed frozen helper.

## Proposed ownership and test gate

Worker: new `packaging/relay_helper_entry.py`, `packaging/relay-helper.spec`, production requirements/constraints/hash lock, build/manifest/audit scripts, frozen-helper smoke/relocation tests, new HelperRuntimeResolver.swift and its focused tests, new runtime notices/lane doc. Propose worker also updates the existing `spikes/macos-panel/scripts/build-session-app.sh` into the actual product wrapper so the normal build cannot keep producing an incomplete app; root must confirm that exact file. Root owns SessionApplicationModel hookup and global docs. No UI, helper/core protocol, auth, profile, image/capture or accepted automatic source edits in this lane.

Tests before product claims:

1. Resolver temp bundles: valid, spaces/relocation, missing executable/data, malformed/wrong schema/unsafe manifest paths, explicit override and non-app fixture; broken `.app` cannot use a working cwd/system interpreter.
2. Entry strict two-module dispatch/argv compatibility and no stdout startup noise; arbitrary module/`-c` reject. Real frozen executable starts with `PATH=/usr/bin:/bin`, no PYTHONPATH/virtualenv/dev overrides and cwd in a non-repository directory.
3. Real framed session-host fixture question/answer and EOF/reap; real standalone profile new/state/selected synthetic TXT/PDF/DOCX/chunk/snapshot/lock through bundled modules. Production native converters must succeed without import-skip logic; encrypted/malformed/page-limit/DOCX unsupported fixtures remain rejected. No optional comparator availability is presented as production support.
4. Relocate the complete app to a fresh directory containing spaces, use nonrepo cwd, audit resources/rpaths/signatures and repeat the framed/helper/converter smokes. Do not mutate/remove peer checkouts to demonstrate isolation. Test no repository path or ambient Python dependency by environment/path audits and frozen `sys.executable`/origin diagnostics restricted to synthetic smoke mode.
5. Build the actual current-source native product and package it; measure output size, verify no weights/private files and store exact lock/manifest/provenance. Locked Mac means no visible UI/capture/account test in this gate.

After source acceptance, root may run a separately labeled offline model-load/ASR smoke with the public verified225MB cache and generated fictional audio, no microphone/screen/Keychain/account. The current runtime design does not perform or pre-approve that smoke.

## Primary evidence and limits

- [PyInstaller6.22.3 release](https://pyinstaller.org/en/v6.22.3/CHANGES.html), [runtime paths](https://pyinstaller.org/en/stable/runtime-information.html), [macOS feature notes](https://pyinstaller.org/en/stable/feature-notes.html), [pinned license](https://github.com/pyinstaller/pyinstaller/blob/v6.22.3/COPYING.txt). GPL2-or-later has a bootloader/loader exception permitting combined distribution; runtime hooks are Apache2. Retain exact notices and all bundled dependency licenses rather than infer permissive status from the packager.
- Pinned packager source/tests inspected: loader/pyiboot01_bootstrap.py; tests/functional/test_basic.py (`test_run_from_path_environ`, absolute Python paths), test_multiprocessing.py (`test_subprocess_environment_inheritance`, paired onedir/onefile fixtures) and test_symlinks.py (actual relocated/symlink executable handling); ctypes tests inspected for native library coverage. These upstream tests were read, not run.
- [Docling2.142.0 project metadata](https://github.com/docling-project/docling/blob/v2.142.0/pyproject.toml), [DocumentConverter source](https://github.com/docling-project/docling/blob/v2.142.0/docling/document_converter.py), [NativePdf pipeline](https://github.com/docling-project/docling/blob/v2.142.0/docling/pipeline/native_pdf_pipeline.py). Direct Core/PDF/native package metadata and repository's accepted converter implementation/tests/docs were read. A guessed upstream PDF test filename was unavailable; no upstream converter test execution is claimed.
- [Standalone distribution format](https://docs.astral.sh/python-build-standalone/), [py2app comparison](https://py2app.readthedocs.io/en/latest/). PyInstaller build-tool wheel/source hashes and Python builder/source tags were read from primary public PyPI/GitHub metadata; Python3.14.9 official release supersedes the preliminary3.14.8 note.
- Only live source/metadata/compiled resource/rpath inspection occurred. No Python build/dependencies installed, no new product built, no runtime source/index/HEAD changed, and no private user/account/OS capture/model operation occurred. Local existing HTTPX-only environment is Python3.14.5 and lacks converter/crypto packages; it is evidence of the current gap, not the proposed product environment.
