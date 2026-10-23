"""Issue #57: zero-model reference publishing with explicit permission and turn checks.

Entirely synthetic/offline. This does not test native SwiftUI, macOS TCC or
real meeting speech/source identification. No paid model use or private files.
"""
from __future__ import annotations

from dataclasses import FrozenInstanceError
from contextlib import redirect_stdout, redirect_stderr
from io import StringIO
import json
import unittest
from unittest.mock import patch

from relay_spike.__main__ import main
from relay_spike.benchmark import load_cases
from relay_spike.publication_policy import (
    PolicyInput, PublicationDecision, _REFERENCES,
    _fixture_request, evaluate_publication, load_evaluation_fixtures,
)
from relay_spike.reference_host import (
    ReferenceCard, ReferencePermission, ReferencePreview, ReferenceRoute,
    preview_reference, publish_reference, render_queued_card,
)
from relay_spike.streaming_qa import ActiveTurns, TurnToken


def policy_input(case="D02", **overrides):
    row = load_cases((case,))[0]
    fields = dict(
        question=row["question"], role=row["role"], category=row["category"],
        source_channel="user_synthetic", question_status="final",
        host_authorized=True,
    )
    fields.update(overrides)
    return PolicyInput(**fields)


def trusted_session():
    turns = ActiveTurns()
    token = turns.activate("synthetic:reference-question", 1)
    permission = ReferencePermission(turns)
    return turns, token, permission


def demo_args(*extra):
    return [
        "reference-qa",
        "--question", load_cases(("D02",))[0]["question"],
        "--role", "analytics", "--category", "sql",
        *extra,
    ]


class ReviewedReferenceHostTests(unittest.TestCase):
    def test_explicit_authorized_full_question_commits_reviewed_card_without_model(self):
        turns, token, permission = trusted_session()
        permission.grant()
        published = []
        route = publish_reference(
            policy_input(), turns=turns, token=token, consent=permission,
            on_present=published.append,
        )
        ref, = _REFERENCES
        self.assertEqual(route.state, "reviewed_reference")
        self.assertEqual(route.reason_code, "reviewed_full_question")
        self.assertEqual(route.model_requests, 0)
        self.assertIsNone(route.first_useful_verified_ms)
        self.assertEqual(len(published), 1)
        self.assertIs(route.card, published[0])
        self.assertEqual(route.card.text, ref.answer)
        self.assertEqual(route.card.reference_id, ref.reference_id)
        self.assertEqual(route.card.source_ref, ref.source_ref)
        self.assertEqual(route.card.label, "reviewed_reference")
        self.assertEqual(route.card.token, token)

    def test_preview_never_contains_text_or_invokes_host_callback(self):
        turns, token, permission = trusted_session()
        permission.grant()
        result = preview_reference(
            policy_input(), turns=turns, token=token, consent=permission,
        )
        self.assertIsInstance(result, ReferencePreview)
        self.assertTrue(result.would_publish)
        self.assertEqual(result.state, "reviewed_reference")
        self.assertEqual(result.model_requests, 0)
        self.assertFalse(hasattr(result, "card"))
        self.assertNotIn(_REFERENCES[0].answer, repr(result))
        with self.assertRaises(ValueError):
            ReferencePreview("unavailable", True, "no_complete_reviewed_reference")

    def test_queued_paint_rechecks_token_at_actual_render(self):
        turns, token, permission = trusted_session()
        permission.grant()
        queued, painted = [], []
        out = publish_reference(
            policy_input(), turns=turns, token=token, consent=permission,
            on_present=queued.append,
        )
        self.assertEqual(len(queued), 1)
        self.assertEqual(painted, [])  # on_present only staged it.
        self.assertTrue(render_queued_card(
            queued[0], turns=turns, consent=permission, on_paint=painted.append,
        ))
        self.assertEqual(painted, [out.card])

    def test_late_ui_queue_after_correction_cannot_paint_old_answer(self):
        turns, token, permission = trusted_session()
        permission.grant()
        queued, painted = [], []
        publish_reference(policy_input(), turns=turns, token=token,
                          consent=permission, on_present=queued.append)
        turns.activate("remote:corrected-question", 2)
        self.assertFalse(render_queued_card(
            queued[0], turns=turns, consent=permission, on_paint=painted.append
        ))
        self.assertEqual(painted, [])

    def test_cancelled_and_replaced_question_never_publishes(self):
        for state in ("cancelled", "superseded"):
            turns, token, permission = trusted_session()
            permission.grant()
            if state == "cancelled":
                turns.cancel()
            else:
                turns.activate("replacement-question", 2)
            called = []
            result = publish_reference(
                policy_input(), turns=turns, token=token, consent=permission,
                on_present=called.append,
            )
            self.assertEqual(result.state, "unavailable")
            self.assertEqual(result.reason_code, "superseded_turn")
            self.assertIsNone(result.card)
            self.assertEqual(called, [])

    def test_revoke_clears_current_ui_and_invalidates_queued_card(self):
        turns, token, permission = trusted_session()
        permission.grant()
        shown = []
        result = publish_reference(policy_input(), turns=turns, token=token,
                                   consent=permission, on_present=shown.append)
        card = result.card
        permission.revoke(on_clear=shown.clear)
        self.assertFalse(permission.authorized())
        self.assertIsNone(turns.current())
        self.assertEqual(shown, [])
        painted = []
        self.assertFalse(render_queued_card(
            card, turns=turns, consent=permission, on_paint=painted.append
        ))
        permission.grant()
        self.assertFalse(render_queued_card(
            card, turns=turns, consent=permission, on_paint=painted.append
        ))
        self.assertEqual(painted, [])  # Re-grant cannot resurrect old turn.

    def test_permission_has_to_be_both_host_authorized_and_currently_granted(self):
        turns, token, permission = trusted_session()
        for request, expect in (
            (policy_input(), "permission_not_confirmed"),
            (policy_input(host_authorized=False), "permission_not_confirmed"),
        ):
            seen = []
            result = publish_reference(
                request, turns=turns, token=token, consent=permission,
                on_present=seen.append,
            )
            self.assertEqual(result.state, "unavailable")
            self.assertEqual(result.reason_code, expect)
            self.assertEqual(seen, [])
        permission.grant()
        seen = []
        result = publish_reference(
            policy_input(host_authorized=False), turns=turns, token=token,
            consent=permission, on_present=seen.append,
        )
        self.assertEqual(result.state, "unavailable")
        self.assertEqual(seen, [])

    def test_consent_revoke_between_policy_and_commit_suppresses_callback(self):
        turns, token, permission = trusted_session()
        permission.grant()
        seen = []
        original = evaluate_publication

        def revoke_after_assessment(*a, **kwargs):
            result = original(*a, **kwargs)
            permission.revoke()
            return result

        with patch("relay_spike.reference_host.evaluate_publication",
                   side_effect=revoke_after_assessment):
            out = publish_reference(policy_input(), turns=turns, token=token,
                                    consent=permission, on_present=seen.append)
        self.assertEqual(out.state, "suppressed")
        self.assertEqual(out.reason_code, "permission_not_confirmed")
        self.assertIsNone(out.card)
        self.assertEqual(seen, [])

    def test_supersession_between_policy_and_commit_suppresses_callback(self):
        turns, token, permission = trusted_session()
        permission.grant()
        seen = []
        original = evaluate_publication

        def supersede_after_assessment(*a, **kwargs):
            result = original(*a, **kwargs)
            turns.activate("new-d02-question", 2)
            return result

        with patch("relay_spike.reference_host.evaluate_publication",
                   side_effect=supersede_after_assessment):
            out = publish_reference(policy_input(), turns=turns, token=token,
                                    consent=permission, on_present=seen.append)
        self.assertEqual(out.state, "suppressed")
        self.assertEqual(out.reason_code, "superseded_turn")
        self.assertIsNone(out.card)
        self.assertEqual(seen, [])

    def test_mismatched_permission_session_is_rejected(self):
        turns, token, permission = trusted_session()
        other_turns = ActiveTurns()
        wrong_permission = ReferencePermission(other_turns)
        with self.assertRaises(TypeError):
            publish_reference(policy_input(), turns=turns, token=token,
                              consent=wrong_permission, on_present=lambda _: None)
        with self.assertRaises(TypeError):
            render_queued_card(
                ReferenceCard(token, _REFERENCES[0].answer,
                              _REFERENCES[0].reference_id,
                              _REFERENCES[0].source_ref),
                turns=turns, consent=wrong_permission, on_paint=lambda _: None)

    def test_unissued_or_forged_card_cannot_bypass_queued_paint(self):
        turns, token, permission = trusted_session()
        permission.grant()
        queue = []
        result = publish_reference(policy_input(), turns=turns, token=token,
                                   consent=permission, on_present=queue.append)
        valid = result.card
        # Semantically identical copy is NOT the object issued by this host.
        duplicate = ReferenceCard(
            token, valid.text, valid.reference_id, valid.source_ref
        )
        painted = []
        self.assertFalse(render_queued_card(
            duplicate, turns=turns, consent=permission, on_paint=painted.append
        ))
        forged = object.__new__(ReferenceCard)
        object.__setattr__(forged, "token", token)
        object.__setattr__(forged, "text", "I shipped the whole project.")
        object.__setattr__(forged, "reference_id", valid.reference_id)
        object.__setattr__(forged, "source_ref", valid.source_ref)
        object.__setattr__(forged, "label", "reviewed_reference")
        self.assertFalse(render_queued_card(
            forged, turns=turns, consent=permission, on_paint=painted.append
        ))
        self.assertEqual(painted, [])

    def test_rejects_model_suggestions_and_unsupported_sql_without_fallback(self):
        for req in (
            policy_input(candidate="I built a private job dashboard.", stream_completed=True),
            policy_input(question="How does HAVING filter raw rows?"),
            policy_input(constraints=("show PostgreSQL query",)),
            policy_input(role="epic"),
            policy_input(category="coding"),
            policy_input(question="What is NOT the difference between WHERE and HAVING?"),
        ):
            turns, token, permission = trusted_session()
            permission.grant()
            outputs = []
            result = publish_reference(req, turns=turns, token=token,
                                       consent=permission, on_present=outputs.append)
            self.assertNotEqual(result.state, "reviewed_reference")
            self.assertIsNone(result.card)
            self.assertEqual(outputs, [])
            self.assertEqual(result.model_requests, 0)
            self.assertNotIn("I built a private", repr(result))

    def test_unsupported_e09_missing_code_remains_withheld(self):
        turns, token, permission = trusted_session()
        permission.grant()
        seen = []
        res = publish_reference(policy_input("E09"), turns=turns, token=token,
                                consent=permission, on_present=seen.append)
        self.assertEqual(res.state, "unavailable")
        self.assertIsNone(res.card)
        self.assertEqual(seen, [])

    def test_host_remains_fail_closed_for_partial_unknown_mic_and_corrections(self):
        for changes in (
            {"source_channel": "remote_partial"},
            {"source_channel": "microphone"},
            {"source_channel": "unknown"},
            {"question_status": "partial"},
            {"question_status": "correction"},
            {"question_status": "interrupted"},
            {"question_status": "discontinuous"},
            {"question": "What is the difference between WHЕRE and HAVING?"},
        ):
            turns, token, permission = trusted_session()
            permission.grant()
            seen = []
            res = publish_reference(policy_input(**changes),
                                    turns=turns, token=token, consent=permission,
                                    on_present=seen.append)
            self.assertEqual(res.state, "unavailable")
            self.assertEqual(seen, [])

    def test_reviewed_reference_cannot_be_forged_via_policy_return(self):
        turns, token, permission = trusted_session()
        permission.grant()
        bad = object.__new__(PublicationDecision)
        object.__setattr__(bad, "state", "reviewed_reference")
        object.__setattr__(bad, "displayed_text", "I created all company systems.")
        object.__setattr__(bad, "reviewed_reference_id", _REFERENCES[0].reference_id)
        object.__setattr__(bad, "reviewed_source_ref", _REFERENCES[0].source_ref)
        object.__setattr__(bad, "reason_code", "reviewed_full_question")
        seen = []
        with patch("relay_spike.reference_host.evaluate_publication",
                   return_value=bad):
            res = publish_reference(policy_input(), turns=turns, token=token,
                                    consent=permission, on_present=seen.append)
        self.assertEqual(res.state, "needs_revision")
        self.assertEqual(res.reason_code, "question_context_unresolved")
        self.assertEqual(seen, [])
        self.assertIsNone(res.card)

    def test_successful_callback_failure_does_not_authorize_later_queued_paint(self):
        turns, token, permission = trusted_session()
        permission.grant()
        captured = []
        def callback(card):
            captured.append(card)
            raise RuntimeError("mock UI render failure")
        with self.assertRaisesRegex(RuntimeError, "mock UI render failure"):
            publish_reference(policy_input(), turns=turns, token=token,
                              consent=permission, on_present=callback)
        seen = []
        self.assertEqual(len(captured), 1)
        self.assertFalse(render_queued_card(
            captured[0], turns=turns, consent=permission, on_paint=seen.append
        ))
        self.assertEqual(seen, [])

    def test_policy_fixture_corpus_host_replay_has_no_unsafe_publication(self):
        rows = load_evaluation_fixtures()
        self.assertEqual(len(rows), 64)
        publication_count = 0
        for row in rows:
            turns, token, permission = trusted_session()
            permission.grant()
            request = _fixture_request(row)
            state = row["input"].get("turn_state", "current")
            if state == "cancelled":
                turns.cancel()
            elif state == "superseded":
                turns.activate("offline:correction", 2)
            seen = []
            out = publish_reference(
                request, turns=turns, token=token, consent=permission,
                on_present=seen.append,
            )
            self.assertEqual(out.state, row["expected_state"], row["id"])
            self.assertEqual(bool(seen), out.state == "reviewed_reference")
            self.assertEqual(out.model_requests, 0)
            if out.card is not None:
                publication_count += 1
                self.assertTrue(row["safe_to_publish"])
                self.assertTrue(row["annotated_useful"])
                self.assertEqual(row["technical_correctness"], "correct")
                self.assertEqual(row["coverage_label"], "complete")
                self.assertEqual(seen[0].text, _REFERENCES[0].answer)
        self.assertEqual(publication_count, 2)

    def test_no_network_auth_or_inference_in_host_and_cli(self):
        flags = demo_args("--synthetic-source", "--final", "--authorized", "--publish")
        out = StringIO()
        with patch("relay_spike.__main__.active_access_token",
                   side_effect=AssertionError("credential read")), \
             patch("relay_spike.__main__.request_json",
                   side_effect=AssertionError("model catalog")), \
             patch("relay_spike.__main__.run_live_synthetic_case",
                   side_effect=AssertionError("inference")), \
             patch("relay_spike.__main__.stream_answer",
                   side_effect=AssertionError("stream request")), \
             patch("urllib.request.urlopen",
                   side_effect=AssertionError("network request")), \
             redirect_stdout(out):
            code = main(flags)
        self.assertEqual(code, 0)
        data = json.loads(out.getvalue())
        self.assertEqual(data["state"], "reviewed_reference")
        self.assertEqual(data["model_requests"], 0)
        self.assertEqual(data["oauth_requests"], 0)
        self.assertEqual(data["answer"], _REFERENCES[0].answer)
        self.assertEqual(data["source_ref"], _REFERENCES[0].source_ref)
        self.assertIsNone(data["first_useful_verified_ms"])

    def test_cli_dry_run_never_paints_and_has_no_answer(self):
        out = StringIO()
        with redirect_stdout(out):
            code = main(demo_args("--synthetic-source", "--final", "--authorized"))
        self.assertEqual(code, 0)
        data = json.loads(out.getvalue())
        self.assertTrue(data["dry_run"])
        self.assertTrue(data["would_publish_reviewed_reference"])
        self.assertIsNone(data["answer"])
        self.assertEqual(data["model_requests"], 0)

    def test_cli_denies_without_explicit_source_final_or_authorization(self):
        for args in (
            demo_args("--publish"),
            demo_args("--synthetic-source", "--publish"),
            demo_args("--synthetic-source", "--final", "--publish"),
            demo_args("--final", "--authorized", "--publish"),
            demo_args("--synthetic-source", "--authorized", "--publish"),
        ):
            with self.subTest(args=args):
                out = StringIO()
                with redirect_stdout(out):
                    code = main(args)
                data = json.loads(out.getvalue())
                self.assertEqual(code, 2)
                self.assertEqual(data["state"], "unavailable")
                self.assertIsNone(data["answer"])
                self.assertEqual(data["model_requests"], 0)
                self.assertEqual(data["oauth_requests"], 0)

    def test_cli_unknown_question_and_e09_withhold_even_if_authorized(self):
        for question, role, category in (
            ("What is NOT the difference between WHERE and HAVING?", "analytics", "sql"),
            (load_cases(("E09",))[0]["question"], "epic", "coding"),
        ):
            out = StringIO()
            with redirect_stdout(out):
                code = main([
                    "reference-qa", "--question", question, "--role", role,
                    "--category", category, "--synthetic-source", "--final",
                    "--authorized", "--publish",
                ])
            self.assertEqual(code, 2)
            data = json.loads(out.getvalue())
            self.assertEqual(data["state"], "unavailable")
            self.assertIsNone(data["answer"])
            self.assertEqual(data["model_requests"], 0)

    def test_public_result_and_card_metadata_are_immutable(self):
        turns, token, permission = trusted_session()
        permission.grant()
        captured = []
        out = publish_reference(policy_input(), turns=turns, token=token,
                                consent=permission, on_present=captured.append)
        with self.assertRaises(FrozenInstanceError):
            out.card.text = "I built all projects"
        with self.assertRaises(ValueError):
            ReferenceCard(token, "Unsafe model prose", "forged", "unknown")
        with self.assertRaises(ValueError):
            ReferenceRoute("reviewed_reference", "reviewed_full_question")
        with self.assertRaises(ValueError):
            ReferenceRoute("needs_revision", "arbitrary private source ID")


if __name__ == "__main__":
    unittest.main()
