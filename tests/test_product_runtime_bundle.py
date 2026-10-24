"""Opt-in actual frozen helper gate; only public synthetic documents/events."""
import base64
from hashlib import sha256
import json
import os
from pathlib import Path
import select
import shutil
import struct
import subprocess
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[1]
EXECUTABLE = os.environ.get("RELAY_TEST_BUNDLED_HELPER")


class FrozenChild:
    def __init__(self, executable, module, *arguments):
        self.directory = tempfile.TemporaryDirectory(prefix="relay-frozen-nonrepo-")
        environment = {"PATH": "/usr/bin:/bin", "HOME": self.directory.name, "TMPDIR": self.directory.name,
                       "LANG": "en_US.UTF-8", "PYTHONPATH": "/nonexistent-relay-python", "PYTHONHOME": "/nonexistent-relay-python",
                       "HF_HUB_OFFLINE": "1", "TRANSFORMERS_OFFLINE": "1", "XDG_CACHE_HOME": self.directory.name}
        self.child = subprocess.Popen([str(executable), "-m", module, *arguments], cwd=self.directory.name,
                                      env=environment, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    def exchange(self, value):
        payload = json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode()
        assert 0 < len(payload) <= 16384
        self.child.stdin.write(struct.pack(">I", len(payload)) + payload); self.child.stdin.flush()
        return self.read()

    def _read(self, count):
        deadline = time.monotonic() + 30
        data = bytearray()
        while len(data) < count:
            remaining = deadline - time.monotonic()
            if remaining <= 0 or not select.select([self.child.stdout], [], [], remaining)[0]:
                raise TimeoutError("frozen helper response deadline")
            part = os.read(self.child.stdout.fileno(), count-len(data))
            if not part:
                raise EOFError("frozen helper closed its framed channel")
            data.extend(part)
        return bytes(data)

    def read(self):
        size, = struct.unpack(">I", self._read(4))
        assert 0 < size <= 16384, "frozen stdout was not a bounded host frame"
        return json.loads(self._read(size))

    def close(self):
        self.child.stdin.close()
        self.child.wait(timeout=10)
        output, errors = self.child.stdout.read(), self.child.stderr.read()
        self.child.stdout.close(); self.child.stderr.close(); self.directory.cleanup()
        return self.child.returncode, output, errors

    def abort(self):
        if self.child.poll() is None: self.child.kill()
        self.child.wait(timeout=10)
        for stream in (self.child.stdin, self.child.stdout, self.child.stderr): stream.close()
        self.directory.cleanup()


@unittest.skipUnless(EXECUTABLE, "actual frozen helper artifact is an explicit packaging gate")
class ProductRuntimeBundleTests(unittest.TestCase):
    def test_relocated_helper_keeps_its_pdf_resources_without_repo_or_python_paths(self):
        with tempfile.TemporaryDirectory(prefix="relay-relocation-") as name:
            executable=Path(EXECUTABLE)
            source=executable.parent.parent.parent if executable.parent.name=="MacOS" else executable.parent
            runtime=Path(name)/"Folder With Spaces"/"Moved Relay.app/Contents/Helpers"/source.name
            shutil.copytree(source,runtime,symlinks=True)
            child=FrozenChild(runtime/executable.relative_to(source),"relay_spike.profile_bridge")
            try:
                self.assertTrue(child.exchange({"command":"new"})["ready"])
                data=(ROOT/"tests/fixtures/documents/synthetic-two-page.pdf").read_bytes()
                child.exchange({"command":"select_begin","size":len(data),"sha256":sha256(data).hexdigest(),"file_type":"pdf",
                                "purpose":"project","label":"Synthetic","role":"developer","project_hint":"Synthetic"})
                for offset in range(0,len(data),4096): child.exchange({"command":"transfer_chunk","offset":offset,"data":base64.b64encode(data[offset:offset+4096]).decode()})
                result=child.exchange({"command":"select_commit"})
                self.assertTrue(result["ok"]);self.assertTrue(result["card"]["locator"].startswith("pdf:page:"))
                code,output,errors=child.close()
                self.assertEqual(code,0);self.assertEqual(output,b"");self.assertEqual(errors,b"")
            except BaseException:
                child.abort();raise

    def test_standalone_profile_converts_actual_txt_pdf_docx_and_serializes_memory(self):
        documents = [(b"I implemented Atlas SQL tests.", "txt", "text:line:"),
                     ((ROOT/"tests/fixtures/documents/synthetic-two-page.pdf").read_bytes(), "pdf", "pdf:page:"),
                     ((ROOT/"tests/fixtures/documents/synthetic-unicode.docx").read_bytes(), "docx", "docx:paragraph:")]
        for data, kind, locator in documents:
            with self.subTest(kind=kind):
                child = FrozenChild(EXECUTABLE, "relay_spike.profile_bridge")
                try:
                    self.assertTrue(child.exchange({"command": "new"})["ready"])
                    self.assertTrue(child.exchange({"command": "select_begin", "size": len(data), "sha256": sha256(data).hexdigest(),
                        "file_type": kind, "purpose": "project", "label": "Synthetic", "role": "developer", "project_hint": "Synthetic"})["ok"])
                    for offset in range(0, len(data), 4096):
                        self.assertTrue(child.exchange({"command": "transfer_chunk", "offset": offset,
                            "data": base64.b64encode(data[offset:offset+4096]).decode()})["ok"])
                    result = child.exchange({"command": "select_commit"})
                    self.assertTrue(result["ok"], f"bundled {kind} converter failed")
                    self.assertTrue(result["card"]["locator"].startswith(locator))
                    manifest = child.exchange({"command": "snapshot_begin"})
                    snapshot = b"".join(base64.b64decode(child.exchange({"command": "snapshot_chunk", "offset": offset})["data"])
                        for offset in range(0, manifest["size"], 4096))
                    self.assertEqual(sha256(snapshot).hexdigest(), manifest["sha256"])
                    self.assertTrue(snapshot.startswith(b"SQLite format 3\x00"))
                    self.assertTrue(child.exchange({"command": "lock"})["locked"])
                    code, output, errors = child.close()
                    self.assertEqual(code, 0); self.assertEqual(output, b""); self.assertEqual(errors, b"")
                except BaseException:
                    child.abort(); raise

    def test_real_session_host_fixture_uses_bundled_reference_data_without_repo_python(self):
        # These are the existing public synthetic schema constructors, never
        # production audio or invented permission/account authority.
        from test_session_host import start, speech, end, final
        child = FrozenChild(EXECUTABLE, "relay_spike.session_host", "--role", "analytics", "--fixture-model")
        try:
            values = [start(), speech(2), end(3), final(4, "What is the difference between WHERE and HAVING?")]
            for value in values:
                payload = json.dumps(value, separators=(",", ":")).encode()
                child.child.stdin.write(struct.pack(">I", len(payload))+payload)
            child.child.stdin.flush()
            decision = child.read()
            while decision["disposition"] == "pending": decision = child.read()
            self.assertEqual(decision["disposition"], "answer"); self.assertEqual(decision["answerKind"], "reviewed_reference")
            code, output, errors = child.close()
            self.assertEqual(code, 0); self.assertEqual(output, b""); self.assertEqual(errors, b"")
        except BaseException:
            child.abort(); raise


if __name__ == "__main__": unittest.main()
