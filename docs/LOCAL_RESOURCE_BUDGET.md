# Local resource budget

The owner's Mac is the primary working computer. On 2026-10-24 the owner reported a nearly full disk and laptop disruption. The controller measured only 3.1 GiB available. Relay-prefixed temporary files reported 97.457 GiB allocated and the isolated workspace reported approximately 8.7 GiB. Separate compiled Swift build/test caches accumulated across feature and independent-review checkpoints. Keeping all of those caches was a workflow error.

All three workers were interrupted. A permitted process inspection found no active Relay compiler, build or download process. The pre-existing original Relay prototype was left untouched.

## Approved cleanup and evidence

The controller inventoried and checked 68 exact old Swift package cache directories, each with its standard cache signature, package state and generated-only top-level entries. Explicit filesystem approval covered only that immutable list. The deletion completed with 68 removed and zero failures. Source checkouts, uncommitted work, evidence, speech assets, Python runtime and verified application bundles were retained.

The directories reported 75.425 GiB allocated. Actual available disk increased by 40.815 GiB during the deletion, from 7.084 to 47.899 GiB. The initial observation was 3.1 GiB; other system activity changed availability before deletion started. Shared blocks and concurrent system activity mean reported directory sizes are not a promise of physical reclamation. The final filesystem check reported 48 GiB available.

Local inventory, immutable approved plan and completed receipt live in `work/coordination-2026-10-24/` in the parent workspace, outside this Git checkout. Plan SHA-256: `98621b98e6b7c5ccb82fd00c571ac94794bf0b1e6feaffed48f25ce205fd3727`. Historical test logs remain valid evidence, but removed cache paths no longer identify existing binaries.

## Required operating limits

1. Run one heavy local job at a time across the controller and all workers. Builds, dependency installs, package assembly, converter-heavy tests and large artifact copies share that slot. Independent research and source editing may continue in parallel.
2. Before a heavy job, check current available disk. Require at least 30 GiB free and account for the job's peak staging size; stop if the projected result crosses that floor. Do not automatically restart an interrupted heavy job.
3. Do not create another independent multi-gigabyte scratch directory for each review or commit. Use the two retained Swift build roots serially: `/private/tmp/relay-root-account-app-build` and `/private/tmp/relay-root-history-ledger-build`. Their module/cache siblings remain available. A genuinely necessary clean-build proof needs a bounded temporary plan and prompt retirement of its newly generated outputs after preserving evidence.
4. Use at most two compiler jobs by default. Raise that only for a specific measured need while the Mac is otherwise idle. Never infer application latency from a busy or unavailable automation service.
5. Reuse `/private/tmp/relay-root-current-runtime/venv/bin/python` and already verified public dependency/model inputs. Do not create a fresh dependency environment or download the same speech/model/archive set for each lane. Do not mutate a shared environment while another consumer uses it.
6. Limit aggregate Relay-prefixed temporary files to 25 GiB of reported allocated storage, including retained legacy witnesses. Inspect current usage before creating large staging directories. Current caches, one working Python environment, one public speech cache and a current app/relocation witness fit within that budget. If retained older witnesses prevent the next job fitting, propose exact cleanup rather than silently exceeding the budget.
7. Preserve source, uncommitted work, test fixtures, sanitized logs, exact source hashes and the latest verified app. New ephemeral build outputs must have a known owner and lifecycle. Delete old or uncertain material only under an explicit exact-scope approval; never use broad temporary-directory globs for deletion.
8. Preserve review independence through frozen source refs and separate test observations. A separate copy of every dependency and historical build output is not required for independent review.

The new frozen b270 preferences artifact has now completed under the reviewed resource-only driver, using existing pinned inputs and retained caches. Its sanitized evidence is in [PR99](https://github.com/KanujVerma/relay/pull/99). This supersedes the earlier interrupted-artifact status. The later root History error-stop gate began at 23.125 GiB Relay temporary allocation and 46.126 GiB free with a 1 GiB reserve; its existing-cache command completed in 17.334 seconds. These are sampled observations, not a continuous peak measurement. Recheck current space and ownership before every next heavy job. This document authorizes no additional deletion, model download, private file access, account operation or main merge.

## Stock builder cache reuse

The stock `packaging/build_product.py` preserves explicitly supplied `CLANG_MODULE_CACHE_PATH` and `SWIFTPM_MODULECACHE_OVERRIDE` and uses `RELAY_BUILD_SWIFT_CACHE` for its native Swift cache. The existing `--native-scratch` selects the retained build root. With those settings omitted, previous work-root defaults remain unchanged. These are developer build settings; they do not add a product setting, model download or runtime fallback.

Use only already verified retained inputs/environment and `--offline`, check the aggregate reserve first, and choose a new output path inside the retained work root so the last verified app remains intact. This setting support does not authorize a new build environment, replacement of preserved witnesses or extra deletion. The two original override assertions fail on the old builder; all eight packaging tests pass after the narrow fix. The actual final stock build, signatures, relocation and bundled feature checks remain required.

The later current stock build from clean fd7b283 has now passed with those retained inputs, strict signatures, 100 native audits, one full relocation and11actual packaged feature cases. [Exact evidence](evidence/2026-10-24-integrated-product-build.md) supersedes the preceding unbuilt status. Completion allocation was24.462GiB; relocation reached24.635GiB and the native gate ended24.651GiB, with free space remaining above32GiB at those observations. The stock builder had a five-second resource watchdog. These results do not authorize additional copies, deletion or a second environment; recheck the narrow remaining headroom before every heavy job.
