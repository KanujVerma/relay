# B3A-1: opt-in reviewed technical cards after completed SSE

This is an explicitly selected experimental mode, not production answer
verification, personal-project attribution, microphone capture or a usable
generic coding solution engine.

## Development

The earlier B2 smoke path remains unchanged by default:

    python3 -m relay_spike live-qa
    python3 -m relay_spike live-qa --case D02 --execute

New opt-in mode, **dry-run by default**:

    python3 -m relay_spike live-qa --case D02 --technical-card
    python3 -m relay_spike live-qa --case E09 --technical-card

Only a separately authorized local account test calls exactly one plan-backed
model request:

    python3 -m relay_spike live-qa --case D02 --technical-card --execute

The new mode collects bounded SSE using the same B1 parser with
`strict_replay=True`: **every data-bearing SSE frame must have a valid
sequence_number**, and any missing number or repeated sequence fails closed.
The original B2/infer/benchmark paths keep their legacy adjacent-replay
deduplication behavior. Strict validation may withhold output if the provider
ever emits unnumbered frames, which is a deliberate opt-in feasibility
constraint, not a proven account-wide wire guarantee. It neither shows
nor judges partials before response.completed. After completion it checks the
raw candidate against the reviewed B3A-0 technical propositions. If accepted,
it returns a **local fixed technical card** instead of generated model prose,
and then reuses deterministic QA and atomic active-turn publication.
An unsupported or unsafe candidate is reduced to **no answer text**,
with a status and sanitized reasons. Even a malformed or substituted internal
`TechnicalVerdict` is rechecked at runtime for exact dataclass type, case ID,
true publishable flag, reviewed success reason and equality to the independent
fixed canonical card. Candidate-provided reason strings are never forwarded:
only local fixed status codes may enter the CLI report. The returned assessment never contains
the raw candidate. An E09 suggestion for a deeper review is advisory and
never triggers another plan request.

## Product truthfulness

A final_unverified result means the approved local synthetic card passed
deterministic checks. It does NOT mean the entire original model response is
correct, user-specific, fact-supported or objectively useful. First text is
still just first model output. Display occurs after entire response and final
QA: no low-latency sentence preview exists. This mode only handles D02/E09.
Live model wording may still be withheld despite technically correct content.
Future semantic, user-fact and incremental display gates need independent
validation, and a real Mac one-request smoke test after merging is required.

## Offline regression acceptance

- No auth/inference in dry run or CI, exactly one mocked Responses POST when
  executed and current model visible.
- Distinct approved D02/E09 paraphrases publish only the reviewed card.
- Unsafe fictional job, contradictory or appended model text never leaks via
  returned assessment, presentation callback, stdout or error details.
- Partial/incomplete/failed/oversized SSE and stale corrected/interrupting
  turns cannot publish any content.
- No extra model call and no mutation to OAuth, native audio, Personal Brain,
  ASR, question-turn machine or the original B2 smoke mode.
- Run fixture/document validators plus Python unittest suite and exact-head
  Codex review before merging.
