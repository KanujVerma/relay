# -*- mode: python ; coding: utf-8 -*-
# Build only from the current checkout and the externally prepared locked env.
from hashlib import sha256
from importlib.metadata import distributions
import json
import os
from pathlib import Path
import sys

from PyInstaller.config import CONF
from PyInstaller.utils.hooks import collect_data_files, copy_metadata

root = Path(SPECPATH).parent
work = Path(CONF["workpath"])
paths = ["EVALS/interview-questions.jsonl", "EVALS/publication-policy-cases.jsonl",
         "EVALS/technical-answer-gate.jsonl", "EVALS/asr-intent-cases.jsonl",
         "ROLE_PACKS/junior-data-analytics.md", "ROLE_PACKS/epic-software-developer.md"]
resources = [{"path": path, "size": (root/path).stat().st_size,
              "sha256": sha256((root/path).read_bytes()).hexdigest()} for path in paths]
manifest = work/"runtime-manifest.json"
manifest.write_text(json.dumps({"schema": 1, "python": "3.14.9", "packager": "6.22.3",
                               "architecture": "arm64", "resources": resources}, sort_keys=True), encoding="utf-8")
datas = [(str(root/path), str(Path(path).parent)) for path in paths]
datas += [(str(manifest), "."), (str(root/"packaging/THIRD_PARTY_NOTICES.md"), "notices")]
datas += [(str(Path(sys.base_prefix)/"lib/python3.14/LICENSE.txt"), "notices/CPython")]
state=Path(os.environ["RELAY_RUNTIME_BUILD_ROOT"])
components=state/"python-component-notices"
datas += [(str(components/"licenses"),"notices/Python-components/licenses"),
          (str(components/"PYTHON.json"),"notices/Python-components"),
          (str(state/"build-provenance.json"),".")]
# Preserve package version/entry-point metadata and its distributed licenses.
# This isolated env contains only the two committed hash locks and pip seed.
for distribution in distributions():
    name = distribution.metadata["Name"]
    if name.lower() != "pip": datas += copy_metadata(name)
# Docling Parse's native decoder also needs its distributed font maps. Native
# library inclusion alone passes imports but fails real born-digital PDFs.
for package in ["docling", "docling_core", "docling_parse", "doclang", "latex2mathml"]:
    datas += collect_data_files(package)

a = Analysis([str(root/"packaging/relay_helper_entry.py")], pathex=[str(root)], binaries=[], datas=datas,
             hiddenimports=["relay_spike.session_host", "relay_spike.profile_bridge", "relay_spike.account_bridge", "relay_spike.product_session", "jwt.algorithms",
                            "cryptography.hazmat.primitives.asymmetric.rsa", "docling.models.plugins.defaults"],
             hookspath=[], hooksconfig={}, runtime_hooks=[],
             excludes=["markitdown", "magika", "onnxruntime", "torch", "torchvision", "transformers", "tkinter", "pytest"],
             noarchive=False, optimize=0)
pyz = PYZ(a.pure)
exe = EXE(pyz, a.scripts, [], exclude_binaries=True, name="relay-helper", debug=False,
          bootloader_ignore_signals=False, strip=False, upx=False, console=True,
          target_arch="arm64", codesign_identity=None, entitlements_file=None)
collection = COLLECT(exe, a.binaries, a.datas, strip=False, upx=False, name="RelayRuntime")
# Use stock code/data separation and crosslinks. Raw COLLECT metadata folders
# below a parent app's Helpers directory violate macOS code-bundle rules.
bundle = BUNDLE(collection,name="RelayRuntime.app",bundle_identifier="com.relay.runtime",
                info_plist={"LSBackgroundOnly":True,"CFBundleDisplayName":"Relay Runtime"})
