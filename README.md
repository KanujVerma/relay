# Relay

Local-first personal interview copilot for macOS, designed around fast, verified, role-specific talking points and user-authorized personal context.

**Status:** Slice 00, product contract and synthetic evaluations. No runnable interview assistant exists yet.

## Product direction
- Focus on actual job interviews and the questions/edge cases relevant to each targeted role, initially Epic software developer and junior BI/analytics.
- Personal Brain: learn from resumes, user-confirmed experiences and explicitly selected sources, with provenance and verification.
- Continuous learning: track question patterns, correct output mistakes, refine style and retrieval without inventing personal claims.
- Answer quality: correctness, question coverage, relevance and readable concise talking points, with latency measured.
- Local-first: keep source material and recordings private. Record/transcribe only with authorization and use assistance in settings where it is permitted.
- Target official ChatGPT subscription-based inference if available to this account; eligibility and usage limits must be tested, not assumed.

## Source of truth
- [Product contract](PRODUCT.md)
- [Provisional architecture](ARCHITECTURE.md)
- [Epic software developer Role Pack](ROLE_PACKS/epic-software-developer.md)
- [Junior analytics Role Pack](ROLE_PACKS/junior-data-analytics.md)
- [Synthetic interview benchmarks](EVALS/interview-questions.jsonl)
- [Development handoff](HANDOFF.md)

## Validation
Run `python3 EVALS/validate.py`. This checks fixture structure and coverage; it **does not** grade any language model's answers. The PR workflow runs this lightweight check on Ubuntu to conserve private-repo Actions minutes.

## Next slice
01A: verify a supported ChatGPT-authenticated inference path and capture first streamed response/latency in a minimal, text-only spike. See [HANDOFF.md](HANDOFF.md).
