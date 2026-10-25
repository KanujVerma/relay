# Cluely ordinary UI observation, 2026-10-24

Read-only product research. No Relay implementation decision or feature change.

## Identity and method

Observed installed `/Applications/Cluely (New).app`, bundle
`com.cluely.app.april22`, version/build `2.1.24`. Its ASAR still hashes to
`5ed201e85fc9de452b338887bffadca2a5dd1eef1f12fd101db81be02b0b28a0`.
The actual accessibility tree identifies a hosted renderer at
`renderer.v2.cluely.com/#/settings` and `#/chat`. The installed package hash does
not identify that live renderer's deployment bytes.

Reused the existing [REA investigation](CLUELY_DEEP_DIVE.md), including its
partial/truncated static coverage, rather than repeating extraction or analysis.
Methodology: [REA v45 at f470350](https://github.com/morluto/rea/blob/f470350528ffdfd3f1ec800ffafbf24ae5c7b593/.agents/skills/reverse-engineer-anything/SKILL.md).
The retained CLI is `rea-agents@6.7.0`, MIT; no tool/package was installed or run
for this observation. Native UI actions used computer use only.

Relay comparison uses canonical source `f618525` and its runtime source
`d40f7ba101c00c38d45e21c8240f5abc5536d8d3`. Relay was not launched by this audit.
Its [current artifact/setup evidence](https://github.com/KanujVerma/relay/blob/f618525567668624bcd2bd1bcf2e67f12593b162/docs/evidence/2026-10-24-current-app-and-signing.md)
and [joined Learning evidence](https://github.com/KanujVerma/relay/blob/f618525567668624bcd2bd1bcf2e67f12593b162/docs/evidence/2026-10-24-learning-integration.md)
remain separately attributed to their actual gates.

## Observed ordinary workflow

| Surface | Direct observation | Evidence limit |
| --- | --- | --- |
| General Settings | Horizontal tabs; distinct update, general, language, audio and account sections. Transcription/output language selectors and a microphone-test action are discoverable. | No selector/toggle/test/update/account action was exercised. |
| Keybinds | Readable action labels and visible shortcut recipes, grouped into general, window movement and response scrolling. | No binding was edited or invoked. |
| Notifications | A concise explanation of a scheduled-meeting reminder before a call. | No Calendar/account/schedule was opened; delivery and synchronization remain unknown. |
| About | Installed version and release notes describe a rewrite, faster responses, longer context and improved file search. | These are vendor claims, not observed speed, memory or retrieval performance. |
| Idle Ask | Closing Settings revealed an empty compact two-row composer, with separate screen-context, mode, Listen and History controls. Reopening Settings returned General. | No text was entered/submitted. No Listen/History/mode-content action or answer was observed. Control labels do not prove their backend behavior. |

The audit started and ended on General Settings. It did not start recording,
capture a screen through Cluely, test a microphone, grant permissions, log in,
purchase, change preferences, open saved history or inspect personal content.
No competitor screenshot, proprietary source, asset or raw account state is
included in this record. The original Relay prototype was untouched.

## Current Relay comparison and proposed priorities

The earlier static parity inventory predates substantial Relay implementation.
Typed Ask, transcript, saved History, cited generated notes, response guides and
inspectable Learning are present in current source; they are not new gaps.
See `AssistantComposerView.swift`, `RelayHistoryWorkspace.swift`,
`GeneratedMeetingNotesSection.swift`, `ResponsePreferencesSettingsView.swift`
and `LearningMemorySettingsSection.swift` under the native app target.
Their synthetic application acceptance does not establish real account or
interview usefulness. Cluely's corresponding private workflows were not opened.

| Priority | Proposal, not implementation | Reason and tradeoff |
| --- | --- | --- |
| P0 | Finish normal Relay account setup and bounded real useful-answer acceptance. | Its verified signing/setup blocker matters more than another visual feature. This audit supplies no competitor latency comparison. |
| P1 | Make the current audio/screen source, response guide, confirmed background and tentative Learning status easy to understand together. | Cluely's compact surface makes current choices visible. Relay can improve discoverability without merging their distinct permissions or turning instructions into facts. |
| P1 | Review a simpler ready idle surface while preserving explicit recording controls. | Cluely's empty Ask is economical; Relay Home exposes more setup. Less chrome may help repeated use, but hiding consent or source readiness would be a regression. This is a design hypothesis, not a measured usability result. |
| P1/P2 | Consider a separately authorized short audio preflight, and clearer shortcut recipes. | Cluely exposes both affordances. Relay already has managed speech readiness and editable shortcuts; neither proves the chosen physical input works. Preflight would add capture/privacy scope and requires a separate decision. |
| P2 | Defer calendar reminders and multilingual breadth unless the owner's workflow requires them. | Visible Cluely settings establish discoverability only. They do not justify delaying Relay's English interview quality and lifecycle acceptance. |

## Architecture implication and unresolved evidence

No new backend, framework, memory server or credential interface follows from
this observation. Prefer presentation changes through Relay's existing native
owner and request paths if Root approves them. Keeping guides, confirmed facts,
saved transcripts and tentative adaptation separate costs some UI explanation,
but preserves explicit authority, deletion and correction behavior. A combined
status summary can explain these sources without merging their policies.

Do not copy concealment behavior. Ordinary window controls and consented source
selection meet this task's intended use. No live answer, automatic trigger,
long-meeting recall, personal adaptation, retrieval quality, durable notes,
capture accuracy, server retention, hiring outcome or end-to-end latency was
tested in Cluely. Relay's bounded continuity must not be described as unlimited
meeting memory, nor inferred to outperform the vendor's long-context claim.
