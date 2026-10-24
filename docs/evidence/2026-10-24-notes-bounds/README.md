# Full saved-record notes bounds

Design proof only,2026-10-24. No native build, model/private data/account call, new environment, dependency/cache or heavy job. The stdlib script allocates a few bounded fictional JSON buffers and emits totals only. It is not imported by Relay. The global heavy slot remains with the artifact owner.

Actual immutable History772/d9 text domain and updated05e6924 eleven-gap type list inspected read-only: <=1024finals/256KiB raw UTF-8 text per record; each nonblank row <=1200Unicode scalars/4800UTF-8 bytes and no NUL. Other control scalars are not excluded. Final row revision is exactly1. Native counters remain lossless strings in persisted/exported proof.

`id = UUID36 + ':' + epoch20 + ':' + sourceCode1 + ':' + generation20 + ':' + segment20`, giving101ASCII bytes. The fixture uses1,024unique IDs with maximum-width UInt64 fields and descending20digit segment IDs; source2's label `selected_app_audio` is longest. Full selection endpoints, count1024, record UUID/revision at maximum width, interrupted state and all11unique gap strings are included. This models the validated projection domain; it does not fabricate original native envelopes or claim actual capture.

With sorted compact JSON and unescaped solidus, fixed header is660bytes and each empty-text row costs165bytes. A Unicode scalar expands by at most6JSON bytes per admitted UTF-8 byte; U+0001 attains6:1. Therefore:

```text
source <= 660 + 1024*165 + 1023(commas) + 6*262144
       = 1,743,507 bytes < 2,097,152 (2 MiB)
```

Actual fictional witnesses in [result.json](result.json): ordinary and astral UTF-8 source432,787bytes/53chunks; quote/backslash694,931bytes/85chunks; admitted control U+0001 reaches1,743,507bytes/213chunks. Thus illustrative768KiB would not cover the actual admitted domain. Cap2MiB permits <=256sequential8KiB chunks. A full all-0xff/base64 chunk with max-width scope epoch/index255 and UUID metadata has11,179byte body/11,183bytes with frame prefix, below16KiB. Awaited whole writes leave queue32frame/256KiB limits unchanged; do not enqueue every transfer frame at once.

Persisted payload proof includes1,024exact101byte row IDs, actual revision1 and64byte text digests, maximum-width record/note revisions, source scope/gaps/hash, actual-model identifier limit256bytes, all generation UUID/counter fields, maximal-width valid timestamps, edited origin and an exactly8,192byte structurally valid notes object. Encoded payload is223,799bytes. A conservative allowance expands every row revision from1to20digits (+19,456bytes) and every model identifier byte to six JSON bytes (+1,280bytes), although source schema1 requires actual revision1 and model controls are prohibited. This gives244,535bytes, below262,144 (256KiB). No persisted full-source text copy is included. Whole SQLite/snapshot page overhead still uses the existing8MiB cap and final encrypted candidate receipt; the per-document result does not promise that every100maximum-size records/documents fit together.

Reproduce using the already existing interpreter, without package installation or bytecode/cache creation:

```sh
PYTHONDONTWRITEBYTECODE=1 /private/tmp/relay-root-current-runtime/venv/bin/python docs/evidence/2026-10-24-notes-bounds/calculate_bounds.py
```

[Script](calculate_bounds.py) assertions cover scalar/UTF-8 limits, unique/max-width IDs, raw aggregate bytes, exact6:1 witness, source cap/chunk counts, frame size, exact8KiB output and derived cap. It does not validate native event authenticity, semantic summary correctness, Swift serializer runtime, provider context window,15s latency or the future encrypted schema migration. Those require approved implementation fixtures and the serial resource budget. The analytical6:1 bound includes permitted optional Unicode escaping; final native writers must retain compact JSON/unescaped solidus for chunk framing.
