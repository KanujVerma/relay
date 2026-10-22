# Issue 29 document converters implementation plan

> For agentic workers: execute using superpowers:subagent-driven-development.

Goal: satisfy the frozen issue29 acceptance contract and produce one reviewed Relay PR.
Architecture: a bytes-only bounded conversion adapter uses narrow real vendor APIs, preserves original and derived hashes separately, and feeds existing unverified candidate review. Model-free native PDF and paragraph-scoped DOCX are the only reviewable paths; flattened vendor comparisons remain needs_review.
Tech stack: Python3.12, stdlib SQLite, pinned optional MarkItDown/Docling Slim/python-docx.
Spec: docs/superpowers/specs/2026-10-22-issue29-acceptance.md

## Global constraints
All spec constraints apply. Frozen existing tests/EVALS and new controller tests/fixtures/spec cannot change. No private sources, credentials, model downloads, audio, cloud services or new datastore. Controller alone pushes/reviews/merges.

### Task 1: implement and measure the frozen conversion contract
Read the spec first and the controller tests `tests/test_document_acceptance.py`; they are the exact requirements. Read `AGENTS.md`, `docs/RESUME_CANDIDATES.md`, and existing gateway methods. Implement the interface/signatures/statuses/limits in the spec, keeping modules small. Allowed files: new relay_spike/document_conversion.py and focused document_*.py helpers; backward-compatible metadata keyword in relay_spike/resume_candidates.py; new worker-owned tests/test_document_conversion.py; requirements-documents.txt; new .github/workflows/document-converters.yml; EVALS/benchmark_documents.py; docs/DOCUMENT_CONVERTERS.md; relevant HANDOFF/README/ADRs/roadmap pointers. Never alter existing tests, existing CI, frozen acceptance or fixtures. No unrelated runtime edits.

- [ ] Run frozen acceptance before implementation and capture the expected missing-module failure.
- [ ] Build a task-local optional Python3.12 virtualenv and install only pinned narrow requirements. Do not modify shared runtimes. Dependency setup may use PyPI; converter imports/execution must run offline with an empty task-local cache. If a package/API fails, report precise evidence and choose no replacement or reduced assertion without controller decision.
- [ ] Write focused worker-owned negative tests first for implementation-specific failure branches. Implement the smallest bytes-only adapter and safe provenance/staging seam satisfying the frozen contract.
- [ ] Run focused tests while repairing; run mandatory real-library acceptance with RELAY_DOCUMENT_INTEGRATION=1, no skips, socket guard and empty cache. Run all existing checks unchanged.
- [ ] Run the synthetic converter benchmark, capture actual wall/RSS/version/support evidence, and document limitations plus the narrow follow-up toward real approved imports. No raw document output.
- [ ] Self-review diff, run final checks, commit implementation (no push), and write report with commands, exact outputs/exit status, changes, limitations and any concerns.

The controller independently verifies protected-file hashes, all mandatory checks and benchmark, then dispatches task and final reviews. Fixes return to this same Luna XHigh worker through followup_task with concrete failures. Three repair rounds maximum before controller diagnosis; never silently change acceptance. Final GitHub Codex review and CI apply to the exact merge head.
