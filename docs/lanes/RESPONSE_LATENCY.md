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

No real account, Keychain, private source, audio/screen capture, model inference,
download or full-app latency result is claimed. Product goals from speech-end
remain first visible text under 1 s median, useful advice by 2 s median, and a
compact complete answer around 3–4 s median; these are unachieved targets.
