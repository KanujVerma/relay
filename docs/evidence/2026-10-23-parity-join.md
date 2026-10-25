# Native UI, automatic setup and My Context join

Controller source `a4789b5` joins independently accepted Contextfe6, automatic speech5aa and UI owna100. The exact owner mappings are below. No peer snapshot or unrelated branch content was imported.

| Accepted source | Controller commits |
| --- | --- |
| Context62a +fe6 |13582e9 +91cc199|
| Automatic d3a/cae/fb +5aa cancellation correction |7bd112a/f1a5956/ad3020d/afa1ac3|
| UI own15e/971/f57/a100 |5f6444e/95e3d40/5d78ec8/a4789b5|

Root exact source comparisons are empty for automatic macos-session source/tests and SessionApplicationModel against5aa, UI entry/presentation/Settings againsta100, and profile native/Python bridge againstfe6. The accepted correction is present even though the UI's frozen feature branch still imports originalfb. Independent review reports preserve each own delta and its dependencies.

Root combined local gate on macOS27/Swift6.4, with owned offline dependency caches and configured synthetic Python:

- Full panel package85 collected:83 passed,2 opt-in synthetic-render skips,zero failures. Its actual app subset35 collected/33pass/2skips completed4.673s; bridge39 and panel-state11 passed. This includes all7 original image-retirement actual-app regressions plus9 automatic-app and10 presentation/action cases.
- Changed speech setup/store/downloader/provisioning subset23 collected:22 passed,1 opt-in real-provision skip,zero failures,0.692s. Six coordinator tests include the obsolete-waiter cancellation correction. No model is loaded by this gate.
- EVALS26 synthetic questions validate; documentation20 required files/local links and whitespace pass.
- Profile24 and Python564/21 optional converter skips remain the prior accepted Context evidence. Exact unchanged-source comparison, rather than a repeated full Python/profile run, preserves that attribution. New typed Python source is still in its separate lane.

The first UI independent scratch command attempted remote dependency refresh and failed before compilation. This combined gate uses the exact pinned cached artifacts with `--skip-update`; no credential or model asset download occurs. Each package had a180-second outer deadline. LaunchServices notification warnings occur on this locked/sandboxed Mac but all XCTest cases above complete successfully.

No actual microphone/process tap/screen/AX capture, account/Keychain/private document, OS permission or visible UI was exercised. The10 committed UI PNGs are synthetic never-ordered view renders, not desktop screenshots. Actual225MB provision/hash/offline validation belongs to the separately recorded automatic author/reviewer evidence. CoreML load and live recognition remain unmeasured. Self-contained runtime packaging, account UI, typed/native app wiring, saved-context reopen, modes and durable history remain active next work. Main is not merged and the older hosted-green commit does not certify this newer source.
