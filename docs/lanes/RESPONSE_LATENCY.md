# Response latency

Base: canonical published `88af72044b4dd0127bba869b8783803a2769ec40`.
The complete validated response remains the publication boundary. First text
is transport telemetry, not useful advice or a visible answer.

## Approved first checkpoint

1. Retain one lazily created HTTPX client per actual helper, with one active
   request and explicit awaited close. Read the current bearer for each request;
   never store it in client defaults. Do not persist response cookies. Preserve
   response-context cancellation and immediate return at validated completion.
2. Keep one immutable, content-free timing snapshot per completed attempt:
   credential ready, client ready, request start, headers, first valid nonempty
   text delta, validated `response.completed`, and local attempt finish. Record
   failed and cancelled attempts distinctly; a completion timestamp alone cannot
   turn a failed visual-continuity check into success.
3. Prove constructor reuse, lazy initialization, fresh bearer, cookie isolation,
   bounded request admission, active-request retirement, actual stalled-socket
   cancellation, completion without EOF, failures and deadlines using offline
   synthetic transport/socket tests. Measure identical local fixture requests
   before and after. This does not measure network or model latency.
4. Independently review the frozen patch before joining. Native speech/ASR,
   helper admission, final checks, post-drain Model availability and actual
   readable presentation remain a later coordinated measurement seam.

The client pool may reuse a connection only when HTTPX can safely return that
connection to the pool. An early return at `response.completed` can close an
unfinished HTTP body. Do not wait for trailing server EOF merely to reuse TCP.
The measured first benefit is avoiding repeated client/TLS-context setup, not
guaranteed socket/TLS-handshake reuse.

## Checkpoint 1 implementation and verification

The transport now retains its lazy client, with one pool connection, a 15 s
keepalive expiry and a joined, idempotent `aclose()`. Actual helper finalization
drains answer/probe ownership and closes that client. Responses retain their
individual streaming context. Per-request headers carry fresh bearer authority;
response cookies are cleared before each request and on final close. The latest
admitted completion attempt replaces one immutable timing snapshot. The native
wire and answer admission rules have no changes in this checkpoint.

The new constructor regression failed on the base (`2 != 1`). New timing tests
also initially failed at the absent API. Final focused gate: **139 tests passed,
zero skips, 4.390 s**. Full Python discovery: **767 collected, 735 passed,
32 explicit optional skips, 10.378 s**. Optional document/converter/package
dependencies remain disabled; no Swift build, real account or capture gate ran.
Existing HTTP-error/SQLite ResourceWarnings remain. `git diff --check` passed.

Two existing visual fixtures captured `self.handler` when constructing a new
client for each request. Their failure/retirement controls replace that handler
after capability verification. Reusing the client exposed this fixture
assumption. The fixture transport now dispatches to the current handler on
every request. Assertions and held response controls are unchanged. The bearer
rotation test additionally proves a validated completion timestamp can coexist
with a **failed** attempt and a withheld answer. The original actual-socket
cancel and completed-before-EOF tests stay enabled; a new actual-socket close
test joins concurrent cleanup callers and observes real disconnect.

Matched local probe: `python -m tests.support.transport_latency_probe`, unchanged
script before/after, three batches of eight synthetic requests. A real loopback
HTTP server forces `Connection: close`, so these results cannot claim TCP/TLS
handshake reuse or provider speed. The real HTTPX default transport is created;
using only MockTransport would skip SSL-context construction and understate that
cost. No external request, credential or inference is involved.

| Local component | Base | Candidate |
| --- | ---: | ---: |
| Client constructions across 24 requests | 24 | 3 |
| Median subsequent fixture request, 21 observations | 5.701 ms | 1.703 ms |
| Median first request of each batch | 6.580 ms | 6.398 ms |
| Median client construction | 3.671 ms | 4.030 ms |

The observed warm component difference is **3.998 ms**. First process requests
also incurred one-time HTTPX/backend initialization (133.904 and 177.163 ms in
the two runs); they are retained rather than excluded from the raw probe output.
This small setup improvement does not meet or substantiate any seconds-level
speech-end, visible-card or first-useful-answer target.

## Evidence and reuse

HTTPX **0.28.1**, ref `26d48e0634e6ee9cdc0533996db289ce4b430177`,
BSD-3-Clause, is already pinned. Inspected the
[AsyncClient implementation](https://github.com/encode/httpx/blob/26d48e0634e6ee9cdc0533996db289ce4b430177/httpx/_client.py),
[lifecycle tests](https://github.com/encode/httpx/blob/26d48e0634e6ee9cdc0533996db289ce4b430177/tests/client/test_async_client.py),
[license](https://github.com/encode/httpx/blob/26d48e0634e6ee9cdc0533996db289ce4b430177/LICENSE.md),
and [official async guidance](https://www.python-httpx.org/async/). Reuse the
existing dependency and its streaming context manager; no code is copied and
no new dependency, server, model, credential flow or framework is introduced.
Upstream mock cleanup tests do not establish actual Relay socket cancellation;
the local real-socket regressions remain required.

## Subsequent decisions

Keep current VAD silence/closed-activity ASR unchanged in this checkpoint.
Shortening endpointing without a pause/continuation corpus risks splitting a
question and increasing cancelled or wrong answers. A compact complete-card
prompt must retain multi-part/code requirements and personal-grounding guards.
Native telemetry must be descriptive only, bounded and separate from currentness
authority, and must measure after the actual Model reentrant snapshot drain.

## Checkpoint 2: stage measurement and compact prompt foundation

The second checkpoint adds an optional top-level decision `timing` member. It
contains only integer monotonic timestamps, explicit nulls, a fixed schema and
a fixed transport outcome. Existing decision IDs and native 13-key EOU payload
are unchanged. The helper records the read of the chunk completing the input
frame, generation entry, transport entry, valid first delta, validated provider
completion, successful helper format/visual checks and decision emission. A
rejected later request cannot borrow the preceding attempt's transport snapshot.
Reviewed references, missing personal evidence and disabled inference never
acquire invented provider timestamps. A valid provider completion followed by
a format or continuity failure remains a withheld/failed result.

Native measurement joins the original calibrated speech end, endpoint event
emission, ASR finalization, native EOU emission, enqueue to the bounded helper
writer, terminal receipt before final native context checks and panel commit.
The recorder retains at most **32 memory-only rows**, with no question, card,
transcript, personal source, image, credential or persistent log. It never
participates in admission. Malformed optional telemetry is discarded while all
existing required decision validation remains strict. Accepted panel commit,
post-drain Model availability and observed visible-window state are distinct
marks. Window visibility is not pixel paint or a usefulness rating.

The Learning Memory owner owns the single actual Model observation seam. Source
inspection found a lock hazard: `panel.onChange` runs inside
`SessionPresentationAuthority.withCurrentLease`'s nonrecursive lock. Completing
the reentrant `@Published` drain does not release that lock. A synchronous
observer cannot call `authority.snapshot()` there. Root and the Memory owner
will place full currentness checks after the outer `panel.accept` returns, or
defer and recheck original ownership/currentness. The latency recorder itself
has no locks, callbacks or authority reads. An actual Model watchdog is a
required joined gate; this source-only finding is not an app verification claim.

The compact prompt uses **soft** targets of a 20–35 word complete lead and
35–70 spoken words overall, with zero to two points. Optional detail is omitted
unless explicitly requested or necessary for correctness. Every requested part,
required code, critical assumption and grounding rule takes precedence over
brevity. Parser/byte/code limits, personal classification and currentness rules
are unchanged. This is a generation instruction, not a proven speed result.

`EVALS/benchmark_answer_latency.py` prints its synthetic plan when run directly;
it cannot obtain credentials or create a client. Root may supply the existing
explicit protected product stream to compare six bounded model attempts on
identical SQL, coding and feature-case questions, alternating prompt order.
Missing-personal-evidence controls make no model attempt. Results preserve
transport errors, format withholds, first-delta/completion times and output
length. Deterministic format/syntax checks leave correctness **unreviewed**;
the listed rubrics require human inspection. The frozen baseline prompt comes
from `a8fb232`; no model/effort change or second review call is introduced.

Five helper-stage tests failed before telemetry;
the native API-first gate failed on absent timing/recorder APIs in 56.596 s,
under the shared two-compiler-job limit and 180 s deadline. That is expected
failure evidence. The following native gate succeeds: **94 collected, 93 passed,
one explicit packaged-artifact resolver skip, 7.625 s**. It includes all six new
timing cases, the full native panel test target, actual source Python helper
delivery, typed/visual/guide and currentness controls. The overall command took
74.526 s including compilation. App/state targets compiled but selected zero
test cases; no actual Model/GUI measurement is claimed by this gate. Fresh
sampled budget was 23.155 GiB Relay temporary allocation and 48.792 GiB free,
with 0.75 GiB reserved. Both gates reused the retained shared cache, two compiler
jobs and the 180 s external deadline; the heavy lease was released afterward.

Final Python discovery: **777 collected, 745 passed, 32 explicit optional skips,
10.027 s**. The existing converter/package optional gates remain disabled and
the existing HTTP-error/SQLite ResourceWarnings remain. The three offline
benchmark tests verify identical paired prompts, required runnable binary-search
behavior, zero personal inference, missing credential fallback, failed streams,
and retained refusal/incomplete observations. Refusal markers are observations,
not successful completion or proof of valid provider lifecycle. The preceding
two-test image-retirement correction is frozen separately in `3f634c0`;
its exact focused gate passed 141 tests in 3.957 s before broader work resumed.
`git diff --check` passes. Actual Model seam, GUI/paint, packaged artifact, real
account and full speech-end latency gates remain pending and root-coordinated.

The larger source bottleneck remains measured only in the next permitted gate:
the sole current reviewed fixture is D02; other general supported questions use
generation. `SourcePipeline` starts recognition only after closed VAD activity,
and the adapter feeds the whole closed span sequentially. Lagged incremental
preprocessing could reduce finalization work, but feeding ahead of the eventual
VAD end index would break exact-span provenance. No speculative ASR, silence
change, new model, download or architecture is included here.

## Active next gate: safe-prefix ASR and actual Model observation

The four prepared actual Model cases reached the expected API-first failure
because `responseLatencySamples` is not yet supplied by the coordinated Model
observation seam. The bounded command exited 1 in 59.903 s, with no passing-test
claim; the heavy lease was released. Existing source checkpoints stay frozen.

[The lagged-ASR proposal](../superpowers/specs/2026-10-24-lagged-asr-preprocessing-design.md)
now defines the exact returned-state watermark, padding/cutoff proof, original
activity key, one existing recognizer and bounded worker **per source**, and
actual cancellation/quiescence and two-source gates. A fixed delay alone is
rejected: a pending VAD end survives long middle-band sequences. Design-only
metadata fixtures preserve that counterexample and six explicit original-cutoff
cases. Four pure tests pass in 0.067 s, including 9,841 bounded class sequences.
This is not execution of the future Swift path or an ASR performance claim.
No preprocessing implementation has begun before root's concrete design review.

[Current official effort research](../research/RESPONSE_EFFORT_OPTIONS.md)
confirms generic Luna None/Low and Sol Low support, distinguishes omitted effort
from the literal `none`, and records the actual local product omission policy.
Current plan/account acceptance and quality/speed comparisons remain untested;
no default, service-tier, account or inference change has been made.

No real account, Keychain, private source, audio/screen capture, model inference,
download or full-app latency result is claimed. Product goals from speech-end
remain first visible text under 1 s median, useful advice by 2 s median, and a
compact complete answer around 3–4 s median; these are unachieved targets.
