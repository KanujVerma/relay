"""Strict frozen entry dispatch, without private files or account work."""
from importlib.util import module_from_spec, spec_from_file_location
from pathlib import Path
import sys
import unittest
from unittest.mock import patch


ENTRY = Path(__file__).resolve().parents[1] / "packaging" / "relay_helper_entry.py"


class ProductRuntimeEntryTests(unittest.TestCase):
    def setUp(self):
        spec = spec_from_file_location("relay_product_entry_test", ENTRY)
        self.entry = module_from_spec(spec)
        spec.loader.exec_module(self.entry)

    def test_session_dispatch_preserves_existing_module_arguments_and_restores_argv(self):
        arguments = ["-m", "relay_spike.session_host", "--role", "developer", "--fixture-model"]
        original = sys.argv
        observed = []
        with patch("relay_spike.session_host.main", side_effect=lambda: observed.append(sys.argv[:]) or 7):
            self.assertEqual(self.entry.main(arguments), 7)
        self.assertEqual(observed, [["relay_spike.session_host", "--role", "developer", "--fixture-model"]])
        self.assertIs(sys.argv, original)

    def test_profile_dispatch_uses_only_existing_standalone_host(self):
        with patch("relay_spike.profile_bridge.main", return_value=0) as run:
            self.assertEqual(self.entry.main(["-m", "relay_spike.profile_bridge"]), 0)
        run.assert_called_once_with()

    def test_unsupported_interpreter_forms_never_invoke_a_host(self):
        with patch("relay_spike.session_host.main") as session, patch("relay_spike.profile_bridge.main") as profile:
            for arguments in [[], ["-c", "print('no')"], ["-m", "relay_spike.auth"], ["-m", "os"],
                              ["-m", "relay_spike.profile_bridge", "ignored"],
                              ["-m", "relay_spike.session_host"] + ["extra"] * 17,
                              ["-m", "relay_spike.session_host", "x" * 513]]:
                with self.subTest(arguments=arguments[:3]):
                    self.assertEqual(self.entry.main(arguments), 2)
            session.assert_not_called(); profile.assert_not_called()


if __name__ == "__main__":
    unittest.main()
