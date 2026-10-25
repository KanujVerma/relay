# Cluely 2.1.24 renderer measurements

Research date: 2026-10-23. These are inert shipped-source measurements, not observations of a running application. The Mac is locked. No target renderer, bootstrap, native addon, account or inference was executed. Use original Relay artwork and native font/assets; this packet supplies functional geometry and style proportions only.

Artifact: `/Applications/Cluely (New).app/Contents/Resources/app.asar`, 28,442,561 bytes, SHA256 `5ed201e85fc9de452b338887bffadca2a5dd1eef1f12fd101db81be02b0b28a0`, package version 2.1.24. Source ranges below are UTF-8 byte offsets, end exclusive. Line/column in the local AST index use Babel's line/UTF-16 column convention.

## Surface hierarchy

| Surface | Measured source configuration | Boundary |
|---|---|---|
| Floating control pill | 163 x 50; separate window; rounded pill, transparent outer space | main.js lines15368,15425-15450 |
| Chat | Width690 fixed; collapsed104 or120 in invisible state; expanded500; dashboard760 high | main.js lines15469-15554 |
| Settings | 920 x 670, minwidth760; native hiddenInset titlebar | main.js lines15614-15642 |
| Onboarding | 1100 x 720, fixed | main.js lines15706-15728 |
| Upcoming meeting alert | 360 x 300,15px inset from primary workarea top/right | main.js lines15667-15681 |

The prompt is at the TOP of the chat, followed by answer content. The bottom48px navigation holds audio/session controls, mode and view actions. User messages are right bubbles; assistant responses are open rich text. Dashboard uses the same690px-wide window with a larger height. Settings has a TOP horizontal tab strip, not a left sidebar.

## Type, color and spacing

Global body: Geist Variable, sans-serif, normal100-900. Inter is also bundled but is not the body declaration. Base spacing is0.25rem, normally4px; normal400, medium500, semibold600. Native SF with the measured sizes is a Relay adaptation, not identical typography.

Main theme base radius0.625rem, normally10px. Dark general theme: background `oklch(14.1% .005 285.823)`, foreground `oklch(98.5% 0 0)`, card/popover `oklch(21% .006 285.885)`, muted `oklch(27.4% .006 286.033)`, muted foreground `oklch(70.5% .015 286.067)`, borderwhite10%, inputwhite15%. Live widget uses many direct white-opacity values, so the generic theme alone does not reproduce it.

CSS: `dist/assets/index-DTminr0K.css`, SHA256 `e40f543237590e5efede33aa3b6b4bb13e4165218b10204646983f030c64cb2b`; body declaration10276..10497, transparent html/body/app10042..10108, font faces189287..190190, theme192094..194356. CSS values describe source CSS pixels; runtime scale, font rasterization and compositing remain unobserved.

## Control pill

Source `dist/assets/control-gAeWfF8s.js`, positions1533..3173 and3173..7905:

- Outerpadding2; main fullround with overflowhidden; backdrop `hsla(252,10%,10%,0.8)`.
- Logo26px square,12px from left. Rightcontrols gap6, rightpadding9, leftpadding8.
- Ask/Hide is66 x 32, fullround,12px semibold white. It toggles chat visibility. Hover scale1.05/brightness1.25,150ms.
- Separate32px round Stop session and Start session controls. Dark gradient `#2e3039` to `#272a31`;150ms hover. Start invokes the actual create-session hook, Stop the end-session hook. Loading disables appropriate controls. Source aria-labels confirm roles at6200 and6775.
- Background drag target has aria-label Drag control window; mouse movement sends drag updates and a terminal drag-end event. Double-click resets position. It is distinct from Ask and session actions.

## Chat input and answers

`dist/assets/chat-DIvku-qQ.js`, SHA256 `805ede5bfe6f1ec47678f9f814534c727427f71bd9fd2a95d4eab13a0804b137`:

| Element | Measured renderer values | Byte range |
|---|---|---|
| Top input | Minheight56;15px/20px; verticalpadding18, right8; rounded top16 | 764365..766290 |
| Empty placeholder |15px medium white50%; top row, not a bottom composer |786307..786520 |
| User bubble | Max78%width; radius17 exceptBR6; padding14x10;13px medium/20; white92% |296454..297621 |
| Assistant response | Unboxed selectable richtext; horizontal12; bottom14 |295934..296454 |
| Answer scrollarea | Horizontal6, bottommask fade; overlay scroll-to-latest button28round |292958..295934 |
| Answer copy/action |24square,14glyph;white38% to74%hover |289452..290339 |
| Provenance | Viewed screen / Viewed files in12px muted text; screenshot preview has loading/error states |290910..292866 |
| Footer |48height,3columns1fr/auto/1fr,bgblack13%;left/rightpadding12,gap8 |768477..775640 |
| Footer view actions |40high,radius12,horizontal12,12px semiboldwhite72%,hoverwhite14.5% |773193..775489 |

The rich text module uses prose-sm, whose CSS is0.875rem (normally14px) with1.71429 lineheight (normally24px); do not assume the dashboard summary's16px override applies to every assistant answer. Main source displays Ask or search anything, Uses Screen/Does not use screen, Pause/Resume Audio Session, Stop recording, Start Audio Session, New Chat, Transcript and History. Static JSX labels do not show the old guide's Assist/Say next/Recap action row. A runtime or server-driven alternative remains unobserved.

## Transcript and history

Transcript header12px semibold white34%, uppercase, letterspacing0.14em. Bodypadding16; gridtimestampcolumn52 plus12gap; timestamp11px mediumwhite34%/20px/tabular; speaker11px semiboldwhite36% uppercase0.14em. Talkingplaceholder13px mediumwhite42%/20. Empty transcript15pxwhite38%/24. Source776049..779200.

History rows minheight56,radius12,horizontal12/vertical8,gap12. Icon40square, round or8pxradius,bgwhite7%. Title14px medium; detail/date12pxwhite42%; date tabular. Group labels11px semibold uppercasewhite38%,0.14em tracking. Row actions menu minwidth176,radius12,bgRGB25/27/27,padding6; items36high/13px mediumwhite78%. Source725710..746382.

## Settings

Source `settings-BgaBVBD_.js`, SHA256 `02fd9a84b165010e1f12ac6aac38837c992e2bfa1d1cd5b889947cbc494ec4f6`, root204539..207683. Navigation schema is `settings-B6FV2ZqQ.js`9867..10408.

- Top horizontal icon+label tabs: General, Calendar, Notifications, Modes, Keybinds, Profile, Security, Billing, About. Avoid a nine-item sidebar that does not match this source hierarchy.
- Main dark backgroundRGB9/12/13,outerpadding4. Inner fullheightrounded6,borderwhite8%.
- Drag headerbgwhite3.5%,bottomwhite7%; title13px semiboldwhite72%,28px row. Nav maxwidth860, centered, gap4,horizontal20,bottom12. On Mac top4; otherplatform top8.
- ContentRGB12/15/16,maxwidth760center,horizontal32,vertical28; scrollcolumn for ordinary settings. Profile/Security render a separate embedded settings surface.
- General: update status/action, appversion, undetectability, launchatlogin, meetingusage, transcription/output languages, microphone source and microphone test. Audio test has connecting, input-level guidance, denied/error states. Modes has meeting context, editable name, attached file processing and active-mode controls.
- About source announces complete 2.0 rewrite, dated April 3, 2026. This is strong evidence that Sep-Dec 2025 guide screenshots are a different design generation.

No proprietary logo, icon path, font file, image, prompt, renderer component or stylesheet was copied into Relay. This packet is a sanitized functional specification.
