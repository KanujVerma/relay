# Query mechanism and prospective team planning review

2026-10-23. Exact source f6452a572518294f29a723d64b48c93c6c59b07c, corrected by f0fe9d0e4e5adf932742532777af823252a88517. Independently reviewed in clean immutable checkouts. Accepted together and imported as dc262bd +6eb1717; no main merge or GitHub review approval.

The old shared conservative matcher treated ordinary present mechanism questions, including “How does Python implement lists?”, as requests for a person's history. The correction adds query-only grammar handling, retaining historical/possessive/attribution checks in remaining clauses. It introduces no person/technology name registry. An ambiguous present-tense named subject may receive generic guidance or clarification; it does not authorize an invented assertion about that person.

The first patch introduced a P2 regression: “How would our team design a feature for nurse handoffs?” changed from an actual Host answer with one model call to personal_context_missing with zero calls. The narrow correction preserves prospective modal/procedural team planning while keeping real ownership/history and mixed-tail negatives. The unchanged reproduction now answers through the real Host.

Independent evidence:74 focused tests pass; actual Host positive and negative controls pass. AST comparisons show all seven shared/output guards unchanged: _ATTRIBUTION, _HISTORY_REQUEST, _CONTRIBUTION_ASSERTION, _NEUTRAL_START, _has_individual_attribution, _check_neutral_prose, parse_generated_card. Joined root6eb1717 full Python:605 collected,581 pass,24 optional converter skips,4.486s. The permitted full run resolves the two earlier sandbox-only localhost bind denials. Existing SQLite ResourceWarnings remain, without test failures.

A real self-contained app artifact built from clean6eb1717 passes18 resolver/actual-app cases. The new product test sends both example questions through the actual Model and bundled helper, sees a card, and confirms typed questions do not become recognized audio transcript rows. It is test-only commit64ff4b8. This is synthetic provider evidence, not real model quality or interview acceptance.
