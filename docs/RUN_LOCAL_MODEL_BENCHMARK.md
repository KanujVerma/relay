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
