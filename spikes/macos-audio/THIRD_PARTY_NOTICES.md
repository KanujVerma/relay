# Third-party attribution for the experimental audio spike

## SystemAudioKit (mic capture design adaptation)

Upstream: https://github.com/pieralukasz/SystemAudioKit

**Exact source revision reviewed and adapted:** `ccc6ab1e53b27e16b2eb4c01890560568a73d38c` (2026-10-17).

Source reference: https://github.com/pieralukasz/SystemAudioKit/blob/ccc6ab1e53b27e16b2eb4c01890560568a73d38c/Sources/SystemAudioKit/MicrophoneCapture.swift

Relay's `MicrophoneCapture.swift` borrows the general AVAudioEngine input-tap and permission/device-format approach, adapted to in-memory, callback-owned PCM. **No original WAV-writer source is used.** The upstream project is MIT licensed; the full applicable notice follows.

MIT License

Copyright (c) 2026 Lukasz Piera

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Selected-app Core Audio process tap adaptation

Relay's `SelectedAppProcesses.swift`, `CoreAudioHelpers.swift`, and `SelectedAppProcessTap.swift` adapt narrow public Core Audio process enumeration, property helpers and tap/aggregate lifecycle designs from these same **MIT-licensed SystemAudioKit files**, pinned to the **same revision** above:

- https://github.com/pieralukasz/SystemAudioKit/blob/ccc6ab1e53b27e16b2eb4c01890560568a73d38c/Sources/SystemAudioKit/AudioProcesses.swift
- https://github.com/pieralukasz/SystemAudioKit/blob/ccc6ab1e53b27e16b2eb4c01890560568a73d38c/Sources/SystemAudioKit/CoreAudioProperty.swift
- https://github.com/pieralukasz/SystemAudioKit/blob/ccc6ab1e53b27e16b2eb4c01890560568a73d38c/Sources/SystemAudioKit/ProcessTapCapture.swift

Changes for Relay: **explicit one-app-only selection**, no global capture path, callbacks transfer only bounded owned PCM into TPCircularBuffer, no recording files, no private TCC API, and listener/IOProc lifecycle serialization. The upstream MIT notice above applies.

## TPCircularBuffer (SwiftPM dependency)

Upstream: https://github.com/michaeltyson/TPCircularBuffer

Pinned source revision: `cc520397504bb72bc6df79ff03eb72988a6dc50d`.

Original author/copyright: Copyright (C) 2012–2013 A Tasty Pixel / Michael Tyson. The library uses a permissive zlib-style license preserved in its original source headers and README.

Relay **depends on the unmodified upstream SwiftPM product** `TPCircularBuffer` / `CTPCircularBuffer` rather than vendoring or claiming authorship of it. Follow the original upstream notice and modification requirements before redistributing its source.

## FluidAudio

The Apache-2.0 FluidAudio project is an evaluated *future* ASR candidate but is **not linked or imported in this slice**. Model weights and their licenses must be reviewed separately before integration.
