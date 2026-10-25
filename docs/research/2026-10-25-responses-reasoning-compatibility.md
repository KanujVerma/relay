# Responses reasoning compatibility reproduction

Source research and original synthetic tests only. Production is unchanged.
This does not establish the cause of the observed live Relay answer failure.

## Primary references

Checked 2026-10-25:

- [Official streaming-event reference](https://developers.openai.com/api/reference/resources/responses/streaming-events) documents `response.reasoning_text.delta`/`done` and `reasoning_text` content parts.
- OpenAI Python SDK **3.37.0**, exact commit **e8a0fd28bbdc1699c97ff0f602b1af3dd378382d**, [version declaration](https://github.com/openai/openai-python/blob/e8a0fd28bbdc1699c97ff0f602b1af3dd378382d/src/openai/_version.py), [Apache-2.0 license](https://github.com/openai/openai-python/blob/e8a0fd28bbdc1699c97ff0f602b1af3dd378382d/LICENSE). This is the assembler's existing conceptual reference, not a new dependency.
- [Reasoning item schema](https://github.com/openai/openai-python/blob/e8a0fd28bbdc1699c97ff0f602b1af3dd378382d/src/openai/types/responses/response_reasoning_item.py), blob `8744204522b660d0ec5bb1506ee2b983ba7b88de`: reasoning content has its own text type; item status is optional. This supports a schema-compatible omitted-status fixture, not a claim that a particular live API request omitted it.
- [Content-part added schema](https://github.com/openai/openai-python/blob/e8a0fd28bbdc1699c97ff0f602b1af3dd378382d/src/openai/types/responses/response_content_part_added_event.py), blob `1fc89b699f06b3adcef11bebd363b49535f69073`, and [done schema](https://github.com/openai/openai-python/blob/e8a0fd28bbdc1699c97ff0f602b1af3dd378382d/src/openai/types/responses/response_content_part_done_event.py), blob `d817253d9da74cc14b7380b4fa85287d46cab345`, include reasoning text alongside output text/refusal variants.
- [SDK stream state](https://github.com/openai/openai-python/blob/e8a0fd28bbdc1699c97ff0f602b1af3dd378382d/src/openai/lib/streaming/responses/_responses.py), blob `6d379f8e6ce0ee7007a6a171b04da9ddcf03c565`, validates output identities and records finalized output items without imposing a universal item-status requirement. Its final-response API still requires response completion. Its more permissive handling is not authority to remove Relay's additional checks.

No SDK code was copied, installed or executed. No new environment, model,
archive or cache was created. Reference source was read through GitHub; API
documentation was read directly. Fixtures are independently written fictional
events, with separate reasoning and final-answer sentinels.

## Frozen source and actual original results

`relay_spike/response_assembly.py` SHA-256:
`2a9f4f6c7484b974853af3ca26d889d6dfcca7d1e5217b2485a1847cdc05fb05`.
These bytes match the current canonical Root assembler and this isolated lane.

New fixture: `tests/test_response_reasoning_compatibility.py`, SHA-256
`a2b3d85a6cb8c9ff0963fbe52cef7c71b3a706840ea9e0c5326bf963fbe831da`.

Existing Python runtime, `PYTHONDONTWRITEBYTECODE=1`:

```text
python -m unittest -v tests.test_response_reasoning_compatibility
12 cases run, 10 passed, 2 compatibility errors, 0.005s; exit 1
```

| Positive fixture | Actual unchanged-source result |
| --- | --- |
| Reasoning item with explicit completed status, followed by final message/completed response | Pass; returns only the final answer. |
| Same finalized reasoning item with optional status omitted | Rejects synthetic event 2, `response.output_item.done`, at assembler line 71. |
| Full reasoning-text added/delta/done/part-done/item-done lifecycle before final message | Rejects synthetic event 2, `response.content_part.added`, at line 58. The later documented reasoning delta/done types also lack handler branches, but the first original rejection is the part event. |

The nine passing negative cases use the accepted explicit-status baseline, so
their success is not masked by either compatibility rejection. They cover
changed reasoning-item and response identities, item-done before addition,
duplicate sequence, explicit incomplete item/response, missing response/item
completion and an unknown event. No refusal or unsupported event is converted
to successful output.

A separate unchanged regression selection also passes **4/4**, zero skips,
0.000s of cases, exit 0: `tests.test_contextual_answers.AssemblyTests` and
`SDKLifecycleRegressions`. It preserves indexed text, terminal identity,
refusal/unfinished rejection, duplicate identity and null-output recovery.

## Narrow contract for review before implementation

This reproduces API-schema compatibility defects. Any correction should
recognize only documented reasoning shapes, bind them to the original reasoning
item/index and content position, retain bounded state and enforce ordering and
completion. Reasoning text must not enter the returned user answer. The existing
final response completion, strict identity/replay checks, final output matching,
refusal rejection and text/global byte caps remain required.

An omitted optional reasoning status is different from an explicitly incomplete
item, and message completion must remain explicit. Do not solve this by ignoring
unknown events, treating every part as answer text or accepting arbitrary item
statuses. The current red tests are deliberately preserved before production
changes; Root review is still required.

No account, model inference, live provider stream, credential, UI, native build
or permission action occurred. The live failure's actual event type, response
shape and terminal reason remain unknown to this lane.
