# Relay handoff

Updated: 2026-10-22
Current slice: **00, product contract + Role Packs**
Work branch: `slice-00-product-contract`
Status: draft PR pending review/merge; nothing implemented in the application yet.

## Locked decisions
- Name: Relay.
- Platform target: native, local-first macOS app.
- Primary goal: useful, accurate, rapid interview assistance in permitted settings, not a generic learning platform.
- Personal Brain and continuous learning are foundational; memory changes require verification.
- Specialize first for Epic software developer and junior BI / analytics / data visualization interviews.
- Test first whether official ChatGPT subscription-backed inference is actually available; no assumed API credits.
- Work in small PRs with documented scope, checks, risks and precise next steps.

## This slice's artifacts
- PRODUCT.md: product contract, priorities and non-goals.
- ARCHITECTURE.md: provisional components, security boundaries and feasibility gates.
- ROLE_PACKS/: role-specific subject priorities and edge cases.
- EVALS/interview-questions.jsonl: synthetic questions only, no personal data.
- EVALS/validate.py and a cheap Linux workflow: fixture/schema checks.

## Done criteria for Slice 00
- Artifacts present and internally consistent.
- Sample questions cover SQL, coding, behavioral, personal attribution, ambiguities and interruptions.
- Fixture validator passes in CI.
- Remaining feasibility questions are explicitly documented.

## Next action after merging
Open **Slice 01A: inference authorization spike**. Implement the smallest supported sign-in/authentication test and a single streamed text response, without UI, Zoom, recording or personal data. Measure first-token latency and account access. No external API charges without explicit approval.

## Agent handoff protocol
Before work: read PRODUCT.md, ARCHITECTURE.md, this file and only role/eval files relevant to the task. Make one narrowly scoped PR. After work: report changes, exact tests run, observed results, unresolved issues, updated handoff, and next slice. Do not treat planned architecture as functioning software.
