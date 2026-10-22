# Slice 01B-A: run a local model comparison

This benchmark compares synthetic interview questions only. It uses your existing ChatGPT OAuth permission, not a separately billed API key. **Do not run against real interview transcripts or confidential files.** The commands are local to your Mac, not GitHub Actions.

## Prepare
From the already cloned Relay directory:

```bash
git pull
source .venv/bin/activate
python3 -m unittest discover -s tests -v
```

If your local access token expired, sign in again with `python3 -m relay_spike auth`.

## Start with a dry run (no network, no OAuth)
```bash
python3 -m relay_spike benchmark
```
This prints the expected models, case IDs and number of plan inference requests. It makes **zero** model requests.

## Opt in to a real comparison
```bash
python3 -m relay_spike benchmark --execute --cases D02,D01,E01 --show-answers
```

This makes **six sequential plan-backed inference requests**, one per model/case pair, and stops on any failure. The models are gpt-6-luna and gpt-6.1-sol. It outputs first_text_ms, total_ms, output length, word count and whether simple length/table constraints were met. It does not claim factual correctness; any answer printed under --show-answers is for local human review only.

You can limit to a single question pair:
```bash
python3 -m relay_spike benchmark --execute --cases D02 --show-answers
```

The CLI limits each invocation to twelve planned requests, without unlimited loops or automatic paid API fallback. These consume your ChatGPT plan allowance even though they do not bill an ordinary API key. Don't paste OAuth tokens, callback links or credential files into issues or chat.

## Interpretation
- First_text_ms is time to first nonempty output text, **not necessarily the first complete usable talking point**.
- Total_ms is completion time, only reported after response.completed.
- Formatted output is not automatically verified correct. Mark personal-claim honesty and SQL correctness manually.
- Small-sample medians are descriptive. p95 is withheld when fewer than 10 samples per model.
- Answer prompts are constrained with top-level instructions; the preview disallows max_output_tokens and conventional service-tier overrides.

After the run, share only model slugs, non-sensitive synthetic responses if desired, and timing/format metrics. Do not share account IDs, raw recordings, access tokens or local credential paths.

Sources and rationale: docs/MODEL_STRATEGY.md, docs/INFERENCE_AUTH.md, https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations.

## Optional reasoning effort override (Slice 01B-A1)

The original commands remain unchanged. Both Luna and Sol use their documented **medium defaults** when `--effort` or `--efforts` are omitted. The owner **successfully tested both explicit Low and Medium** with Luna and Sol 6.1 on 2026-10-22; those four server responses reported the requested efforts. Other effort levels, future availability and speed gains remain unverified.

```bash
# Confirm request count before any account use, 4 requests if executed:
python3 -m relay_spike benchmark --cases D02 --efforts low,medium

# Explicit comparison of both models at Low and Medium, synthetic case only:
python3 -m relay_spike benchmark --execute --cases D02 --efforts low,medium --show-answers

# Single direct test with an explicit effort:
python3 -m relay_spike infer --model gpt-6.1-sol --effort low
```

The benchmark performs every case/model/effort combination, sequentially, with a strict maximum of 12 potential requests per run. `--efforts none` **cannot** be combined with Sol 6.1, because that model does not support none. Run `--models gpt-6-luna --efforts none` separately if desired.

`requested_reasoning_effort` is an input choice; `server_reported_reasoning_effort` is populated only if actually returned in a terminal response. Timing medians/p95 are grouped by model and requested effort, with p95 still withheld below 10 responses for that combination. Default behavior omits the `reasoning` field.

If any explicit effort returns HTTP 400 or another unsupported-param error, record the non-sensitive status and stop that test rather than altering the authorization pathway or retrying with paid API credentials. Successful Low/Medium tests on one account do not establish universal preview support.

## Completed harder-case comparison, 2026-10-22

The owner successfully ran the 12 planned requests for `D13,D07,E09 --repeats 2` on both models at their default (server-reported Medium) effort. **Do not rerun automatically**. Along with the first 10-request round, Relay now has 22 user-reported completed synthetic model calls, including four explicit Low/Medium override tests. Timings, rubric-based assistant inspection and sample-size limits are in [MODEL_STRATEGY.md](MODEL_STRATEGY.md) and [issue #9](https://github.com/KanujVerma/relay/issues/9).

Further model calls need a new, narrow evaluation purpose and explicit owner consent. Do not claim p95 from nine default-effort responses per model or confuse first output text with a useful complete answer. The offline-only QA decision contract has now landed in [PR #14](https://github.com/KanujVerma/relay/pull/14). The next slice is [issue #15](https://github.com/KanujVerma/relay/issues/15), synthetic streaming/QA integration; no new ChatGPT-plan usage is required to start.
