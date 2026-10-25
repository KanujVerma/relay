# Stock bundled Notes acceptance

Artifact source: `fd7b283d34edfef2ecabab9cdbfbc74f71e121a1`, clean. The relocated runtime's build-provenance file independently reports that commit and `sourceDirty:false`; its SHA-256 is `b6da734ee8cbad8f2b5547c1852402dae0f7c0c8d0e5190c578aac2ea8254da0`. Runtime-manifest SHA-256 is `a3210977b81a79eda810384ab39bcd81f92d5451bb6f241241c5752476a0830b`.

Root built the one stock packaged test app, checked strict signatures and 100 Mach-O audit entries after whole-app relocation, then passed three existing frozen-helper smokes. No second app or render was created for Notes. Those build/audit results are the controller's observations; this lane separately read the committed source, runtime provenance and actual native test log.

The actual bundled application gate passed **11 cases, zero skips, zero failures**: Notes2 in1.061s, product runtime4 in0.768s, résumé4 in5.846s and saved context1 in0.681s. Named application cases took8.355s; the controller recorded106.781s for the complete command, exit0. The local raw log is not published; its SHA-256 is `3ba6df2c01e9a5a5f0942c6549b15d7a0b461078bb0ba75203fef1ec1a4f1540`.

The two Notes cases use normal bundled resolution, working directory `/`, no repository/Python override and actual fixture-native session finals saved by the real temporary encrypted History owner. They exercise the owned bundled helper, cited generation, same-run protected save, original-row citation navigation, wording edit with preserved citations, schema2 export, regeneration, actual End/helper reap, reopen and generated-only deletion with transcript preservation. The nonfixture AI-off control proves saved-note reading/local editing and reviewed reference assistance remain available without account/model preparation.

Both nonfixture local-only gates explicitly disable remembered account, context, History, response-guide and Learning settings through test ports. Existing in-memory response fixtures replace persistent receipts/storage; account/browser and unintended History effects fail the test. Notes retains its separate real temporary encrypted History fixture. The default resolver and all original assertions remain; production defaults are unchanged.

Test files match the exact controller-tested bytes:

- `GeneratedMeetingNotesProductTests.swift`: `77ea24ebfe2932485677058a39d6f7835a96f1389bca07c3634d7760cf76a9d2`.
- `ProductRuntimeApplicationTests.swift`: `598d615e72a4b23edff6ce7fae7c3208a576cb2864c5cfa74ea21266bfde7b36`.

The remaining isolation-only patch against artifact source fd7 has SHA-256 `67664588746f5a7d1e812bcef79c3b91214179e6166d3740da97d6f9129c7d86`,12 insertions/3 deletions in those two test files. The test-only successor to64c5 also includes the previously applied account-isolation hunk. No production source changes or native rerun were made by this lane after the controller's gate.

This closes synthetic packaged Notes acceptance alongside the earlier [actual saved-source History render](SOURCE_RENDER.md). It does not establish real account/Keychain/capture or model quality, live interview readiness, complete Learning behavior, measured interview latency, notarization or a main merge. Main remains unmerged. Raw host paths, environment, logs and private data remain local.
