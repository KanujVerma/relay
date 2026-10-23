# Screen context source and reuse record

Reviewed 2026-10-23. This package invokes Apple's public ScreenCaptureKit, Vision, CoreGraphics, CryptoKit and SwiftUI frameworks. It does not bundle an OCR/capture model or a third-party package. SDK/platform licenses apply to the installed Apple frameworks. Apple's [macOS capture sample](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos), [WWDC23 screenshot/picker session](https://developer.apple.com/videos/play/wwdc2023/10136/) and [Vision recognition example](https://developer.apple.com/documentation/vision/recognizing-text-in-images) were inspected as API usage references. No Apple sample file is copied or redistributed. Actual SDK headers in Xcode 27 establish macOS 14 screenshot/picker availability and macOS 15.2 filter window identity availability.

## Muesli source reference

Repository: https://github.com/Muesli-HQ/muesli
Exact inspected revision: `cb0ceb9da89a2d95b17d26d149c2865e43f7e54e`.
Inspected source: `native/MuesliNative/Sources/MuesliNativeApp/ScreenContextCapture.swift` (blob `d8395309ea0c6bf6ad7a1f6643d7064830a57699`). Matching window-binding tests are in `native/MuesliNative/Tests/MuesliTests/ModelsTests.swift`. License: MIT, Copyright (c) 2026 Pranav Hari, [exact license](https://github.com/Muesli-HQ/muesli/blob/cb0ceb9da89a2d95b17d26d149c2865e43f7e54e/LICENSE).

Reference only, no copied Muesli implementation. Learned: OCR must be bound to the intended source before asynchronous work; raw images can remain transient; move synchronous Vision work off the UI actor. Rejected: automatic frontmost-app selection, AX/title/frame fallback, deprecated `CGWindowListCreateImage`, language correction for code, periodic context persistence, and text/error logging. Relay instead uses explicit system single-window selection, original native request fences, bounded single-flight work and cancellation, no AX permission, local OCR line boxes/confidence and a bounded publication recheck. Importing Muesli's full app/model dependencies is unnecessary.

## Competitor research

Cluely 2.1.24 static research is a product-pattern reference only. No competitor code, prompts, assets, native binaries or implementation is copied. Its client does not establish backend vision capability. Sanitized findings: `docs/SCREEN_CONTEXT.md`.
