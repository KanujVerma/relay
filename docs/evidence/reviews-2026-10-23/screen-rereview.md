# Scoped screen-context re-review

Reviewed 2026-10-23. PR #69.

- Original reviewed head: `ec2ef2565da6ff6d056c58f08eb06128dbc9bf36`
- Fixed head: `e3fcfbe3d7f6caa87e2ba3d95f0cb012fc1781ca`
- Checkout: `<workspace>/work/relay-build-screen`
- Scope: only the prior confirmed P2 upscaling finding and its immediate effect. No new audit or full re-review.

## Verdict: addressed

The original finding is addressed at `spikes/macos-context/Sources/RelayScreenContext/SystemSelectedWindowCapture.swift:81`: the actual screenshot configuration now sets `scalesToFit = false`.

The installed Apple public SDK `SCStream.h:257` explicitly documents false as scaling down only, while true scales up and down. Thus a selected window shrinking after output dimensions are measured no longer receives the upscaling instruction identified in the original review. Nearby requested width/height, cursor/audio/shadow options, selected-source fences and screenshot call remain unchanged. The existing maximum-dimension calculation remains in force. No concrete regression was found in this tiny delta.

`docs/lanes/SCREEN.md:33` records the correction and distinguishes the builder's fresh actual-adapter compile from earlier full test results.

## Verification and limits

- Read the complete immutable `ec2ef25..e3fcfbe` delta: two files, six additions and one deletion, consisting only of this option/comment and lane handoff.
- Rechecked the installed public SDK's scaling and default aspect-ratio declarations.
- Fresh `git diff --check <original> <fixed>` passed.
- Initial checkout status was clean and HEAD exactly matched the fixed head. No source/index/HEAD/branch or remote mutation occurred.
- Builder-reported actual-adapter compilation was not rerun. No full suite, real screen capture, permission prompt, Vision/model/account call or private material was used.
- This closes only the prior P2 finding. Existing composition and hardware/account acceptance limits in the original review remain unchanged.
