# Hosted integration verification

## Current query-corrected controller

Exact0e9f6d0bf5e61e8d37f30586235dc7bf1b4d38d3: [macOS/Python40053765188](https://github.com/KanujVerma/relay/actions/runs/40053765188) and [contract40053765194](https://github.com/KanujVerma/relay/actions/runs/40053765194) both succeeded. Actual job120752094948 logs confirm Python605collected/581pass/24optional skips in9.992s; native session60/2skips, profile45, context28, controls18, composition19, panel130/6skips =300collected/292pass/8skips. All six native packages and final app compile succeeded on Swift6.2.3, x86_64 macOS15/Xcode26.2. This includes query grammar6eb1717 and test64ff4b8; its opt-in packaged-only case remains among explicit hosted skips, separately passed against the actual local artifact. New account/idle/résumé feature branches are not integrated in this head.

## Preceding native/context checkpoint

Exact source1cea00234373644670e8f8e07c96f38e2fd43316: [macOS/Python40049024032](https://github.com/KanujVerma/relay/actions/runs/40049024032) and [contract40049024059](https://github.com/KanujVerma/relay/actions/runs/40049024059) both succeeded. Downloaded job120737309073 confirms Swift6.2.3, x86_64 macOS15/Xcode26.2, all six native packages and final SwiftUI app compilation.

Python:598 collected,574 pass,24 optional skips in9.653s. Native: session60 collected/2skips; profile45pass; context28pass; controls18pass; composition19pass; panel130collected/6skips. Total300 collected,292 pass,8 explicit opt-in skips. Final app compilation succeeded. Raw downloaded log SHA256:6050ec9e5f222a0a8205d0b2441b10f0e010efc048176d7536dbe7494a68088c.

This aggregate green confirms the narrow test-only synchronous-XCTest isolated-deinit correction45a742b, previously proven by the same-host LLDB focused control. It resolves that earlier hosted abort for this source. Production/tests/workflow are unchanged from1cea throughf86bc3a, and the later0e9f6d0 result above additionally certifies query grammar6eb1717. Its independent local full605-case run and packaged-app evidence are separately recorded in the [query review](reviews-2026-10-23/review-query-f0fe9d0.md). Hosted synthetic tests do not establish real account, permissions, capture, model quality or latency.
