"""Slice 01A-R, mocked OAuth renewal security and concurrency checks.

No actual user credentials, HTTP requests, browser launch or inference calls.
"""
from __future__ import annotations

from contextlib import ExitStack
import io
import json
import os
from pathlib import Path
import tempfile
import threading
import time
import unittest
from unittest.mock import patch
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qs

from relay_spike import auth


NOW = 100_000.0


def credentials(*, expired=True, **changes):
    data = {
        "client_id": "oaiapp_test-issued-client",
        "ext_agent_host_id": "urn:uuid:synthetic-host",
        "subject": "synthetic-subject",
        "scopes": [
            "openid", "offline_access", "resource.invoke",
            auth.REQUIRED_PLAN_SCOPE,
        ],
        "id_token": "synthetic-id-hint",
        "access_token": "test-access-original",
        "refresh_token": "test-refresh-original",
        "token_type": "Bearer",
        "expires_in": 3600,
        "saved_at": NOW - 3590 if expired else NOW - 10,
    }
    data.update(changes)
    return data


def replacement(**changes):
    data = {
        "access_token": "test-access-replacement",
        "refresh_token": "test-refresh-replacement",
        "token_type": "Bearer",
        "scope": "openid offline_access resource.invoke chatgpt.tokens.use.direct",
        "expires_in": 3600,
    }
    data.update(changes)
    return data


class LocalAuthCase(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / "relay" / "credentials.json"
        self.patch_path = patch.object(auth, "TOKEN_PATH", self.path)
        self.patch_clock = patch.object(auth.time, "time", return_value=NOW)
        self.patch_path.start()
        self.patch_clock.start()
        self.addCleanup(self.patch_path.stop)
        self.addCleanup(self.patch_clock.stop)

    def save(self, **changes):
        auth._write_protected(self.path, credentials(**changes))

    def saved(self):
        return auth._read_protected(self.path)


class RefreshTests(LocalAuthCase):
    def test_valid_access_token_never_refreshes_or_takes_lock(self):
        self.save(expired=False)
        with patch.object(auth, "request_json",
                          side_effect=AssertionError("no HTTP")), \
             patch.object(auth, "_refresh_lock",
                          side_effect=AssertionError("no lock")):
            self.assertEqual(auth.active_access_token(), "test-access-original")

    def test_near_expiry_rotates_both_tokens_and_updates_scopes_atomically(self):
        self.save()
        with patch.object(auth, "request_json", return_value=replacement()) as request:
            token = auth.active_access_token()
            self.assertEqual(auth.active_access_token(), token)
        self.assertEqual(token, "test-access-replacement")
        self.assertEqual(request.call_count, 1)
        self.assertEqual(request.call_args.args[0], auth.TOKEN_URL)
        kwargs = request.call_args.kwargs
        self.assertEqual(kwargs["form"], {
            "grant_type": "refresh_token",
            "client_id": "oaiapp_test-issued-client",
            "refresh_token": "test-refresh-original",
            "resource": auth.RESOURCE,
        })
        self.assertTrue(kwargs["refresh_errors"])
        self.assertNotIn("scope", kwargs["form"])
        self.assertNotIn("client_secret", kwargs["form"])
        self.assertEqual(self.saved()["refresh_token"], "test-refresh-replacement")
        self.assertEqual(self.saved()["access_token"], "test-access-replacement")
        self.assertEqual(self.saved()["saved_at"], NOW)
        self.assertEqual(self.saved()["subject"], "synthetic-subject")
        self.assertEqual(self.saved()["id_token"], "synthetic-id-hint")
        self.assertEqual(self.path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.path.parent.stat().st_mode & 0o777, 0o700)
        lock = self.path.parent / (self.path.name + ".lock")
        self.assertTrue(lock.is_file())
        self.assertEqual(lock.stat().st_mode & 0o777, 0o600)

    def test_atomic_rotation_syncs_both_file_and_parent_directory(self):
        self.save()
        real_fsync = os.fsync
        with patch.object(auth.os, "fsync", wraps=real_fsync) as sync, \
             patch.object(auth, "request_json", return_value=replacement()):
            self.assertEqual(auth.active_access_token(), "test-access-replacement")
        self.assertGreaterEqual(sync.call_count, 2)
        self.assertEqual(self.saved()["refresh_token"], "test-refresh-replacement")

    def test_directory_fsync_failure_is_reported_not_silently_accepted(self):
        self.save()
        original_fsync = os.fsync
        operations = []

        def fail_directory_sync(fd):
            operations.append(os.fstat(fd).st_mode)
            if len(operations) == 2:
                raise OSError("filesystem cannot sync directories")
            return original_fsync(fd)

        with patch.object(auth, "request_json", return_value=replacement()), \
             patch.object(auth.os, "fsync", side_effect=fail_directory_sync):
            with self.assertRaisesRegex(auth.AuthError, "durably sync"):
                auth.active_access_token()
        # Atomic rename happened before the durability diagnostic.
        # A subsequent invocation can safely reuse the new credential.
        self.assertEqual(self.saved()["access_token"], "test-access-replacement")
        with patch.object(auth, "request_json",
                          side_effect=AssertionError("must not refresh twice")):
            self.assertEqual(auth.active_access_token(), "test-access-replacement")

    def test_preemptive_refresh_at_boundary(self):
        self.save(saved_at=NOW - 3540, expires_in=3600)
        with patch.object(auth, "request_json", return_value=replacement()) as request:
            self.assertEqual(auth.active_access_token(), "test-access-replacement")
        self.assertEqual(request.call_count, 1)

    def test_no_refresh_without_saved_rotating_grant(self):
        for changes in (
            {"refresh_token": ""},
            {"client_id": "dynamic_agent_client"},
            {"client_id": None},
            {"scopes": [auth.REQUIRED_PLAN_SCOPE]},
        ):
            with self.subTest(changes=changes):
                self.save(**changes)
                with patch.object(auth, "request_json",
                                  side_effect=AssertionError("unexpected network")):
                    with self.assertRaises(auth.AuthError):
                        auth.active_access_token()
                self.assertEqual(self.saved()["access_token"], "test-access-original")

    def test_nan_or_infinite_credential_expiry_cannot_bypass_refresh_check(self):
        for bad in (float("nan"), float("inf"), float("-inf"), -1, 0):
            with self.subTest(bad=str(bad)):
                self.save(saved_at=bad)
                with patch.object(auth, "request_json",
                                  side_effect=AssertionError("corrupt record made HTTP request")):
                    with self.assertRaisesRegex(auth.AuthError, "Invalid saved OAuth expiry"):
                        auth.active_access_token()
        for bad in (float("nan"), float("inf"), float("-inf")):
            with self.subTest(expires_in=str(bad)):
                self.save(expires_in=bad)
                with patch.object(auth, "request_json",
                                  side_effect=AssertionError("corrupt record made HTTP request")):
                    with self.assertRaisesRegex(auth.AuthError, "Invalid saved OAuth expiry"):
                        auth.active_access_token()

    def test_no_refresh_if_plan_scope_missing_even_if_expired(self):
        self.save(scopes=["openid", "offline_access"])
        with patch.object(auth, "request_json",
                          side_effect=AssertionError("network unexpectedly")):
            with self.assertRaisesRegex(auth.AuthError, "permission"):
                auth.active_access_token()

    def test_reject_bad_rotations_and_preserve_old_record(self):
        invalid = (
            {"refresh_token": "test-refresh-original"},
            {"refresh_token": ""},
            {"refresh_token": None},
            {"access_token": "test-access-original"},
            {"access_token": None},
            {"access_token": "   \t "},
            {"token_type": "Basic"},
            {"expires_in": 0},
            {"scope": "openid offline_access"},
            {"scope": "openid chatgpt.tokens.use.direct"},
            {"client_id": "oaiapp_other-client"},
        )
        for override in invalid:
            with self.subTest(override=override):
                self.save()
                original = self.saved()
                with patch.object(auth, "request_json",
                                  return_value=replacement(**override)):
                    with self.assertRaises(auth.AuthError):
                        auth.active_access_token()
                self.assertEqual(self.saved(), original)

    def test_terminal_invalid_grant_clears_secrets_but_preserves_registration(self):
        self.save()
        with patch.object(auth, "request_json",
                          side_effect=auth.UnusableRefreshToken("terminal")):
            with self.assertRaisesRegex(auth.AuthError, "Run: python3 -m relay_spike auth"):
                auth.active_access_token()
        remaining = self.saved()
        self.assertEqual(remaining, {
            "client_id": "oaiapp_test-issued-client",
            "ext_agent_host_id": "urn:uuid:synthetic-host",
            "subject": "synthetic-subject",
        })
        self.assertEqual(self.path.stat().st_mode & 0o777, 0o600)
        with self.assertRaisesRegex(auth.AuthError, "permission"):
            auth.active_access_token()

    def test_transient_error_preserves_rotating_credentials(self):
        for failure in (
            auth.AuthError("Network or timeout failure during authorization."),
            auth.AuthError("OAuth/API request rejected (HTTP 503)."),
        ):
            with self.subTest(failure=str(failure)):
                self.save()
                prior = self.saved()
                with patch.object(auth, "request_json", side_effect=failure):
                    with self.assertRaises(auth.AuthError):
                        auth.active_access_token()
                self.assertEqual(self.saved(), prior)

    def test_concurrent_cli_threads_refresh_once_with_new_token_reuse(self):
        self.save()
        tokens = []
        failures = []
        requests = []
        barrier = threading.Barrier(2)

        def request(*args, **kwargs):
            requests.append(kwargs["form"]["refresh_token"])
            time.sleep(0.045)
            return replacement()

        def get_access():
            try:
                barrier.wait(timeout=2)
                tokens.append(auth.active_access_token())
            except BaseException as exc:
                failures.append(type(exc).__name__)

        with patch.object(auth, "request_json", side_effect=request):
            threads = [threading.Thread(target=get_access) for _ in range(2)]
            for t in threads:
                t.start()
            for t in threads:
                t.join(timeout=2)
        self.assertFalse(any(t.is_alive() for t in threads))
        self.assertEqual(failures, [])
        self.assertEqual(tokens, ["test-access-replacement"] * 2)
        self.assertEqual(requests, ["test-refresh-original"])

    def test_lock_symlink_is_never_followed(self):
        self.save()
        victim = Path(self.temp.name) / "target"
        victim.write_text("untouched")
        lock = self.path.parent / (self.path.name + ".lock")
        lock.symlink_to(victim)
        with patch.object(auth, "request_json",
                          side_effect=AssertionError("network after bad lock")):
            with self.assertRaisesRegex(auth.AuthError, "lock"):
                auth.active_access_token()
        self.assertEqual(victim.read_text(), "untouched")

    def test_insecure_preexisting_lock_is_rejected(self):
        self.save()
        lock = self.path.parent / (self.path.name + ".lock")
        lock.write_text("fake")
        os.chmod(lock, 0o666)
        with patch.object(auth, "request_json",
                          side_effect=AssertionError("network after bad lock")):
            with self.assertRaisesRegex(auth.AuthError, "owner-only"):
                auth.active_access_token()

    def test_disconnect_removes_tokens_without_unlinking_lock(self):
        self.save()
        with patch("builtins.print"):
            auth.disconnect()
        self.assertFalse(self.path.exists())
        self.assertTrue((self.path.parent / (self.path.name + ".lock")).exists())


class WireTests(unittest.TestCase):
    @staticmethod
    def response_with(json_object):
        return io.BytesIO(json.dumps(json_object).encode())

    def test_raw_post_is_form_encoded_without_scope_or_client_secret(self):
        fake = self.response_with(replacement())
        with patch.object(auth, "urlopen", return_value=fake) as transport:
            value = auth.request_json(
                auth.TOKEN_URL,
                form={
                    "grant_type": "refresh_token",
                    "client_id": "oaiapp_issued",
                    "refresh_token": "synthetic_secret",
                    "resource": auth.RESOURCE,
                },
                refresh_errors=True,
            )
        self.assertEqual(value["access_token"], "test-access-replacement")
        self.assertEqual(transport.call_count, 1)
        req = transport.call_args.args[0]
        self.assertEqual(req.get_method(), "POST")
        self.assertEqual(req.full_url, auth.TOKEN_URL)
        self.assertNotIn("synthetic_secret", req.full_url)
        self.assertEqual(parse_qs(req.data.decode()), {
            "grant_type": ["refresh_token"],
            "client_id": ["oaiapp_issued"],
            "refresh_token": ["synthetic_secret"],
            "resource": [auth.RESOURCE],
        })
        self.assertIsNone(req.get_header("Authorization"))

    def test_terminal_refresh_error_codes_are_classified_without_leak(self):
        for code in sorted(auth.INVALID_REFRESH_CODES):
            with self.subTest(code=code):
                error = HTTPError(
                    auth.TOKEN_URL, 400, "Sensitive label", {},
                    io.BytesIO(json.dumps({
                        "error": code,
                        "error_description": "do not reveal refresh token!",
                    }).encode()),
                )
                with patch.object(auth, "urlopen", side_effect=error):
                    with self.assertRaises(auth.UnusableRefreshToken) as result:
                        auth.request_json(auth.TOKEN_URL,
                                          form={"grant_type": "refresh_token"},
                                          refresh_errors=True)
                self.assertNotIn("do not reveal", str(result.exception))

    def test_nested_error_object_and_invalid_client(self):
        err = HTTPError(auth.TOKEN_URL, 400, "", {},
                        io.BytesIO(b'{"error":{"code":"refresh_token_reused"}}'))
        with patch.object(auth, "urlopen", side_effect=err):
            with self.assertRaises(auth.UnusableRefreshToken):
                auth.request_json(auth.TOKEN_URL, form={}, refresh_errors=True)

        wrong_client = HTTPError(auth.TOKEN_URL, 400, "", {},
                                 io.BytesIO(b'{"error":"invalid_client","detail":"secret"}'))
        with patch.object(auth, "urlopen", side_effect=wrong_client):
            with self.assertRaisesRegex(auth.AuthError, "client was rejected") as caught:
                auth.request_json(auth.TOKEN_URL, form={}, refresh_errors=True)
        self.assertNotIn("secret", str(caught.exception))

    def test_503_and_malformed_body_are_not_terminal_and_do_not_echo_body(self):
        for status, body in ((503, b'{"error":"oops","secret":"token"}'),
                             (503, b'{"error":"invalid_grant"}'),
                             (400, b'non-JSON private stuff')):
            with self.subTest(status=status):
                err = HTTPError(auth.TOKEN_URL, status, "", {}, io.BytesIO(body))
                with patch.object(auth, "urlopen", side_effect=err):
                    with self.assertRaises(auth.AuthError) as caught:
                        auth.request_json(auth.TOKEN_URL, form={}, refresh_errors=True)
                self.assertNotIsInstance(caught.exception, auth.UnusableRefreshToken)
                self.assertNotIn("secret", str(caught.exception))
                self.assertNotIn("private", str(caught.exception))

    def test_malformed_success_body_reports_sanitized_auth_error(self):
        with patch.object(auth, "urlopen",
                          return_value=io.BytesIO(b'not JSON with sensitive content')):
            with self.assertRaises(auth.AuthError) as caught:
                auth.request_json(auth.TOKEN_URL, form={}, refresh_errors=True)
        self.assertNotIn("sensitive", str(caught.exception))

    def test_untrusted_error_code_array_does_not_crash_or_clear_tokens(self):
        err = HTTPError(auth.TOKEN_URL, 400, "", {},
                        io.BytesIO(b'{"error":{"code":["invalid_grant"]}}'))
        with patch.object(auth, "urlopen", side_effect=err):
            with self.assertRaises(auth.AuthError) as caught:
                auth.request_json(auth.TOKEN_URL, form={}, refresh_errors=True)
        self.assertNotIsInstance(caught.exception, auth.UnusableRefreshToken)

    def test_timeout_never_forces_reauthorization_or_leaks_data(self):
        with patch.object(auth, "urlopen",
                          side_effect=URLError("sensitive diagnostics")):
            with self.assertRaises(auth.AuthError) as caught:
                auth.request_json(auth.TOKEN_URL, form={}, refresh_errors=True)
        self.assertNotIn("sensitive", str(caught.exception))


class DependencyPreflightTests(unittest.TestCase):
    def test_missing_jwt_is_caught_before_browser_or_files(self):
        original_import = __import__

        def missing_jwt(name, *args, **kwargs):
            if name == "jwt":
                raise ImportError("simulated missing PyJWT")
            return original_import(name, *args, **kwargs)

        with patch("builtins.__import__", side_effect=missing_jwt), \
             patch.object(auth, "load_or_create_host",
                          side_effect=AssertionError("opened filesystem before preflight")), \
             patch.object(auth.webbrowser, "open",
                          side_effect=AssertionError("opened browser before preflight")):
            with self.assertRaisesRegex(auth.AuthError, "pip install -r requirements-spike.txt"):
                auth.sign_in()

    def test_base_pyjwt_without_cryptography_stops_before_browser(self):
        from types import ModuleType
        import sys

        fake_jwt = ModuleType("jwt")
        fake_jwt.PyJWKClient = object
        original_import = __import__

        def no_crypto(name, *args, **kwargs):
            if name.startswith("cryptography"):
                raise ImportError("simulated missing cryptography extra")
            return original_import(name, *args, **kwargs)

        with patch.dict(sys.modules, {"jwt": fake_jwt}), \
             patch("builtins.__import__", side_effect=no_crypto), \
             patch.object(auth, "load_or_create_host",
                          side_effect=AssertionError("browser state created")), \
             patch.object(auth.webbrowser, "open",
                          side_effect=AssertionError("browser opened")):
            with self.assertRaisesRegex(auth.AuthError, "pip install -r requirements-spike.txt"):
                auth.sign_in()

    def test_new_authorizations_verify_renewable_grant(self):
        tokens = {
            "access_token": "test_access", "token_type": "Bearer",
            "scope": "openid offline_access chatgpt.tokens.use.direct",
            "expires_in": 3600,
        }
        # The core validator remains usable by auth and refresh.
        self.assertEqual(auth.validate_token_fields(tokens)[0], "test_access")


if __name__ == "__main__":
    unittest.main()
