# Generated notes data checkpoint

Owner `/root/review_composition`, GPT-6.1 Sol xhigh. Branch `feature/generated-session-notes-data-2026-10-24`, runtime foundation0c87bae4c1d9c23662b262bf93608dc35901c8c4. Exact approved60539785fda6d213b74ea216caaed834fcf6960d design/evidence are declared docs-only dependencies, imported by3d224f1; designPR98 stays frozen. No unreviewed History source is imported.

## Implemented boundary

`relay_spike/session_notes_data.py` exposes three pure parsers returning frozen data records, tuples and immutable bytes:

- `parse_source_payload(raw)` preserves the original bytes and domain-separated digest, declared selection/order, eleven fixed gaps and final row identity/text proofs. It checks1,024rows/256KiB text/2MiB encoded source, exact field/type/source/revision/UUID/counter domains and actual non-NUL scalar/UTF8 limits without normalization or trimming.
- `parse_generated_notes(raw, source)` checks exact8KiB raw/canonical output, item/count/text limits and included original row IDs with byte-exact supporting quotations. Valid quotations establish structural support only; the summary can still be wrong.
- `parse_notes_document(raw, source)` checks the256KiB payload, captured record/revision/selection/state/gaps/digest and all ordered membership proofs, embedded notes, fixed policy, declared model syntax and generation metadata. It returns canonical data, not a persisted/currentness receipt or configured model identity.

Before recursive decoder allocation, a constant-space byte scan bounds nesting8and8,192value nodes; keys are not counted as values. Existing `generated_answer.strict_json` remains unchanged and supplies duplicate/nonfinite/UTF8/syntax validation. The only non-stdlib dependency is that existing pure decoder module. Safe fixed errors and suppressed DTO representations avoid including source/provider content in diagnostics.

Both timestamps require exact real-calendar24ASCII UTC form. Generated origin requires null editedAt; edited-generated requires a valid timestamp. Per root clarification, a wall-clock rollback is valid; actual ordering belongs to later owned save/edit receipts and revision/CAS, never string comparison of UTC observations.

## Verification

All fixtures are fictional in-memory data. Existing currentPython/PYTHONDONTWRITEBYTECODE, one bounded process with10second SIGALRM:

```sh
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=tests:. /private/tmp/relay-root-current-runtime/venv/bin/python - <<'PY'
import signal, unittest
def stop(*_): raise KeyboardInterrupt('notes data test budget exceeded')
signal.signal(signal.SIGALRM, stop)
signal.setitimer(signal.ITIMER_REAL, 10)
try:
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromName('tests.test_session_notes_data'))
finally:
    signal.setitimer(signal.ITIMER_REAL, 0)
raise SystemExit(not result.wasSuccessful())
PY
```

Final20cases pass0.697s. Initial API-red is the absent module, then16green0.137s. Additional pre-decoder-budget and real backwards-clock cases were red before their fixes. Tests cover every required nested field, unknown authority/model fields, duplicate/nonfinite/partial JSON, raw/node/depth/Unicode/counter/gap/source/citation/provenance negatives;225Unicode/escaping pairs under two byte encodings preserve original literals and distinct source hashes; full1,024row/256KiB control text with maximum-width UInt64 IDs and eleven gaps parses, exact8KiB output and complete derived membership fit the approved caps. Canonical output/document parse roundtrips preserve the parsed data. No new property-test dependency is introduced. Actual parser calls succeed with file/socket/subprocess entrypoints patched to fail.

## Limits and next gate

A parsed full selection does not prove completeness, order or existence in an actual store. Public DTO construction is not a capability. This module has no issuer, permit, claim, currentness, account configuration, save, clock or IO. No host/default/runtime/package entrypoint imports it. No source/admission or native grant is fabricated. Actual source read, surviving-row reconstruction, provider post-token check, scope lifecycle, encryption/migration/CAS/save receipt and app joins are future work requiring accepted History and separate tests/review. No actual recording, model, account, Keychain, private data, helper/native child, compiler, download, dependency/cache/environment change or UI check occurred. No personal or Learning Memory promotion occurs.

Next: root independently reviews the frozen data checkpoint. Keep actual runtime/History/native implementation waiting for its accepted join and resource slot.
