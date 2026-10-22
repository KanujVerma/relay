"""Offline regression tests: no browser, OAuth account, network or API key required."""
from __future__ import annotations

import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from urllib.parse import parse_qs, urlparse
from unittest.mock import patch

from relay_spike import auth, stream


def event_lines(name, payload):
    return [
        ("event: " + name + "\n").encode(),
        ("data: " + json.dumps(payload) + "\n").encode(),
        b"\n",
    ]


class AuthTests(unittest.TestCase):
    def test_pkce_sha256_round_trip(self):
        verifier, challenge = auth.pkce_pair()
        import hashlib
        import base64
        self.assertEqual(challenge, base64.urlsafe_b64encode(
            hashlib.sha256(verifier.encode("ascii")).digest()
        ).decode("ascii").rstrip("="))
        self.assertGreater(len(verifier), 40)

    def test_first_login_has_dynamic_registration_and_scopes(self):
        url = auth.authorization_url(
            client_id="dynamic_agent_client", host_id="urn:uuid:sample",
            redirect_uri="http://127.0.0.1:1234/auth/callback",
            state="unique-state", nonce="nonce", challenge="challenge"
        )
        fields = parse_qs(urlparse(url).query)
        self.assertEqual(fields["agent_name_hint"], ["Relay"])
        self.assertEqual(fields["client_id"], ["dynamic_agent_client"])
        self.assertEqual(fields["resource"], [auth.RESOURCE])
        self.assertEqual(fields["code_challenge_method"], ["S256"])
        self.assertIn("chatgpt.tokens.use.direct", fields["scope"][0])
        self.assertNotIn("client_secret", fields)

    def test_returning_login_does_not_include_agent_name_hint(self):
        url = auth.authorization_url(
            client_id="oaiapp_abc", host_id="urn:uuid:sample",
            redirect_uri="http://127.0.0.1:1234/auth/callback",
            state="unique-state", nonce="nonce", challenge="challenge"
        )
        self.assertNotIn("agent_name_hint", parse_qs(urlparse(url).query))

    def test_dynamic_callback_requires_issued_client(self):
        with self.assertRaises(auth.AuthError):
            auth.verify_callback(
                {"state": ["s"], "code": ["c"]}, "s", "dynamic_agent_client"
            )
        self.assertEqual(
            auth.verify_callback(
                {"state": ["s"], "code": ["c"], "client_id": ["oaiapp_abc"]},
                "s", "dynamic_agent_client",
            ), ("c", "oaiapp_abc")
        )

    def test_callback_rejects_state_tampering_duplicate_code_and_switch(self):
        invalid = [
            {"state": ["wrong"], "code": ["c"]},
            {"state": ["s", "s"], "code": ["c"]},
            {"state": ["s"], "code": ["a", "b"]},
            {"state": ["s"], "code": ["c"], "client_id": ["different"]},
            {"state": ["s"], "code": ["c"], "error": ["access_denied"]},
        ]
        for query in invalid:
            with self.subTest(query=query), self.assertRaises(auth.AuthError):
                auth.verify_callback(query, "s", "oaiapp_abc")

    def test_protected_credentials_and_scope_expiry(self):
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "relay" / "tokens.json"
            with patch.object(auth, "TOKEN_PATH", path):
                record = {"access_token": "dummy", "scopes": [auth.REQUIRED_PLAN_SCOPE],
                          "saved_at": 123_000, "expires_in": 3600}
                auth._write_protected(path, record)
                self.assertEqual(path.stat().st_mode & 0o777, 0o600)
                self.assertEqual(auth._read_protected(path), record)
                with patch.object(auth.time, "time", return_value=123_500):
                    self.assertEqual(auth.active_access_token(), "dummy")
                with patch.object(auth.time, "time", return_value=130_000):
                    with self.assertRaises(auth.AuthError):
                        auth.active_access_token()
                record["scopes"] = ["openid"]
                auth._write_protected(path, record)
                with patch.object(auth.time, "time", return_value=123_500):
                    with self.assertRaises(auth.AuthError):
                        auth.active_access_token()

    def test_reject_symlink_as_credential_file(self):
        with tempfile.TemporaryDirectory() as td:
            source = Path(td) / "real.json"
            link = Path(td) / "link.json"
            source.write_text("{}")
            link.symlink_to(source)
            with self.assertRaises(auth.AuthError):
                auth._write_protected(link, {"access_token": "secret"})


class StreamTests(unittest.TestCase):
    def test_model_catalog_visible_only(self):
        catalog = {"models": [
            {"slug": "model-a", "display_name": "Model A", "visibility": "list"},
            {"slug": "model-b", "display_name": "Model B", "visibility": "hidden"},
        ]}
        self.assertEqual(stream.visible_models(catalog),
                         [{"slug": "model-a", "display_name": "Model A"}])

    def test_responses_fields_are_preview_compatible(self):
        payload = stream.response_payload("model-a", "What is a CTE?")
        self.assertEqual(set(payload), {"model", "input", "store", "stream"})
        self.assertIs(payload["store"], False)
        self.assertIs(payload["stream"], True)
        self.assertIsInstance(payload["input"], list)

    def test_complete_stream_provides_timings(self):
        data = (
            event_lines("response.output_text.delta", {
                "type": "response.output_text.delta", "delta": "WHERE "
            })
            + event_lines("response.output_text.delta", {
                "type": "response.output_text.delta", "delta": "filters rows."
            })
            + event_lines("response.completed", {
                "type": "response.completed", "response": {"status": "completed"}
            })
        )
        times = iter([0.035, 0.085])
        collected = []
        result = stream.consume_stream(
            data, started=0.0, clock=lambda: next(times),
            on_delta=collected.append,
        )
        self.assertEqual("".join(collected), "WHERE filters rows.")
        self.assertEqual(result["first_text_ms"], 35)
        self.assertEqual(result["total_ms"], 85)
        self.assertTrue(result["completed"])

    def test_partial_stream_is_not_success(self):
        data = event_lines("response.output_text.delta", {
            "type": "response.output_text.delta", "delta": "Partial"
        })
        with self.assertRaisesRegex(stream.StreamError, "without response.completed"):
            stream.consume_stream(data, started=0, clock=lambda: 1)

    def test_incomplete_and_failed_events_do_not_pass(self):
        events = [
            {"type": "response.incomplete"},
            {"type": "response.failed", "response": {
                "error": {"code": "subscription_sharing_usage_limit_exceeded"}}},
            {"type": "error"},
        ]
        for event in events:
            with self.subTest(event=event), self.assertRaises(stream.StreamError):
                stream.consume_stream(
                    event_lines(event["type"], event), started=0, clock=lambda: 1
                )

    def test_completed_without_text_is_not_success(self):
        with self.assertRaisesRegex(stream.StreamError, "no output text"):
            stream.consume_stream(
                event_lines("response.completed", {
                    "type": "response.completed", "response": {"status": "completed"}
                }), started=0, clock=lambda: 1
            )

    def test_malformed_event_rejected(self):
        with self.assertRaises(stream.StreamError):
            list(stream.sse_events([b"event: response.completed\n", b"data: not-json\n", b"\n"]))
        with self.assertRaises(stream.StreamError):
            list(stream.sse_events([b"data: {}\n"]))


if __name__ == "__main__":
    unittest.main()
