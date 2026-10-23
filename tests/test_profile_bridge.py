import base64
from hashlib import sha256
import json
from pathlib import Path
import struct
import subprocess
import sys
import unittest

from relay_spike.profile_bridge import ProfileBridge, MAX_FRAME_BYTES


class ProfileBridgeTests(unittest.TestCase):
    def setUp(self):
        self.changes = []
        self.bridge = ProfileBridge(on_change=lambda: self.changes.append("invalidated"))
        self.bridge.handle({"command": "new"})

    def tearDown(self):
        self.bridge.close()

    def select(self):
        data = b"I implemented Atlas SQL tests."
        self.bridge.handle({"command": "select_begin", "size": len(data), "sha256": sha256(data).hexdigest(),
                            "file_type": "txt", "purpose": "project", "label": "Atlas",
                            "role": "developer", "project_hint": "Atlas"})
        self.bridge.handle({"command": "transfer_chunk", "offset": 0,
                            "data": base64.b64encode(data).decode()})
        return self.bridge.handle({"command": "select_commit"})["card"]

    def test_selected_review_and_revocation_use_the_same_provider(self):
        card = self.select()
        self.assertEqual(self.bridge.retrieve("Atlas SQL?", "developer").facts, ())
        self.bridge.handle({"command": "decide", "fact_id": card["fact_id"],
                            "fingerprint": card["card_fingerprint"], "decision": "approve",
                            "actor": "self", "claim_key": "atlas.tests"})
        bundle = self.bridge.retrieve("Atlas SQL?", "developer")
        self.assertTrue(self.bridge.validate_current(bundle))
        self.bridge.handle({"command": "revoke", "source_id": card["source_id"]})
        self.assertFalse(self.bridge.validate_current(bundle))
        self.assertEqual(self.bridge.retrieve("Atlas SQL?", "developer").facts, ())
        self.assertGreaterEqual(len(self.changes), 3)

    def test_incomplete_or_wrong_digest_load_never_authorizes_context(self):
        card = self.select()
        self.bridge.handle({"command": "decide", "fact_id": card["fact_id"],
                            "fingerprint": card["card_fingerprint"], "decision": "approve",
                            "actor": "self", "claim_key": "atlas.tests"})
        bundle = self.bridge.retrieve("Atlas SQL?", "developer")
        with self.assertRaises(ValueError):
            self.bridge.handle({"command": "load_begin", "size": 20, "sha256": "0" * 64})
        self.bridge.handle({"command": "lock"})
        self.bridge.handle({"command": "load_begin", "size": 20, "sha256": "0" * 64})
        self.assertFalse(self.bridge.validate_current(bundle))
        with self.assertRaises(ValueError):
            self.bridge.handle({"command": "load_commit"})
        with self.assertRaises(ValueError):
            self.bridge.retrieve("Atlas SQL?", "developer")

    def test_snapshot_is_chunked_and_restores_to_one_memory_ledger(self):
        self.select()
        manifest = self.bridge.handle({"command": "snapshot_begin"})
        parts = []
        for offset in range(0, manifest["size"], 4096):
            message = self.bridge.handle({"command": "snapshot_chunk", "offset": offset})
            self.assertLessEqual(len(json.dumps(message).encode()), MAX_FRAME_BYTES)
            parts.append(base64.b64decode(message["data"]))
        snapshot = b"".join(parts)
        self.assertEqual(sha256(snapshot).hexdigest(), manifest["sha256"])
        self.bridge.handle({"command": "lock"})
        self.bridge.handle({"command": "load_begin", "size": len(snapshot), "sha256": manifest["sha256"]})
        for offset in range(0, len(snapshot), 4096):
            self.bridge.handle({"command": "transfer_chunk", "offset": offset,
                    "data": base64.b64encode(snapshot[offset:offset+4096]).decode()})
        self.assertIsNotNone(self.bridge.handle({"command": "load_commit"})["card"])
        with self.assertRaises(ValueError):
            self.bridge.handle({"command": "load_begin", "size": len(snapshot), "sha256": manifest["sha256"]})

    def test_oversized_out_of_order_and_extra_authority_fail(self):
        for message in ({"command": "new", "authorized": True},
                        {"command": "load_begin", "size": 9*1024*1024, "sha256": "0"*64}):
            with self.subTest(message=message), self.assertRaises(ValueError):
                self.bridge.handle(message)
        self.bridge.handle({"command": "select_begin", "size": 4, "sha256": "0"*64,
                            "file_type": "txt", "purpose": "resume", "label": "Selected", "role": "developer"})
        with self.assertRaises(ValueError):
            self.bridge.handle({"command": "transfer_chunk", "offset": 1, "data": "YWJjZA=="})

    def test_lookup_current_fact_enables_explicit_correction_only(self):
        card = self.select()
        self.bridge.handle({"command": "decide", "fact_id": card["fact_id"],
                            "fingerprint": card["card_fingerprint"], "decision": "approve",
                            "actor": "self", "claim_key": "atlas.tests"})
        result = self.bridge.handle({"command": "current_claim", "claim_key": "ATLAS.TESTS"})
        self.assertEqual(result["fact"]["fact_id"], card["fact_id"])
        self.bridge.handle({"command": "revoke", "source_id": card["source_id"]})
        self.assertIsNone(self.bridge.handle({"command": "current_claim", "claim_key": "atlas.tests"})["fact"])

    def test_actual_child_uses_bounded_frames_and_no_content_logs(self):
        root = Path(__file__).resolve().parents[1]
        data = json.dumps({"command": "new"}).encode()
        result = subprocess.run([sys.executable, "-m", "relay_spike.profile_bridge"],
                    input=struct.pack(">I", len(data)) + data, capture_output=True, cwd=root, timeout=5)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stderr, b"")
        size, = struct.unpack(">I", result.stdout[:4])
        self.assertLessEqual(size, MAX_FRAME_BYTES)
        self.assertTrue(json.loads(result.stdout[4:])["ok"])
        malformed = subprocess.run([sys.executable, "-m", "relay_spike.profile_bridge"],
                    input=struct.pack(">I", MAX_FRAME_BYTES+1), capture_output=True, cwd=root, timeout=5)
        self.assertNotEqual(malformed.returncode, 0)
        self.assertEqual(malformed.stderr, b"")


if __name__ == "__main__":
    unittest.main()
