# Newston

Hands-off iOS news reader. The user adds news websites, the app reads headlines and articles aloud (TTS), and the user navigates entirely by voice (STT). Designed for eyes-busy/hands-busy use: driving, walking, cooking.

## Read These First

- [`docs/CONCEPT.md`](docs/CONCEPT.md) — product concept, user flow, voice command surface, scope.
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — layers, services, SwiftData domain model, reactive flow, open questions.

These are the source of truth. If a request conflicts with them, surface the conflict before changing code.

## Current State

The repo is **still the Xcode SwiftUI + SwiftData template**. `Newston/Item.swift` and the list UI in `Newston/ContentView.swift` are placeholders — they will be replaced by `Source` / `Headline` / `Article` models and the voice-driven UI from ARCHITECTURE.md. Don't build features on top of `Item`; replace it.

## Stack

- iOS 26.4 deployment target, Swift 5, SwiftUI.
- **SwiftData** for persistence.
- **AVFoundation** (`AVSpeechSynthesizer`, `AVAudioSession`) for TTS.
- **Speech** (`SFSpeechRecognizer`) for STT, on-device where supported.
- **WebKit** (`WKWebView`) for article extraction (off-screen + Readability-style JS).
- Bundle ID: `com.foss.Newston`.

## Locked Design Decisions

Don't relitigate these without an explicit ask:

- **Article extraction**: render in `WKWebView`, extract via injected Readability-style JS against the rendered DOM. LLM extraction is reserved as a fallback for sites where the deterministic extractor fails — not the default path.
- **Voice is primary**: every navigation action must have a voice command. UI affordances exist but should never be the only way to do something during listening.
- **Three navigation axes only**: source, headline, reading control. Resist adding a fourth.

## Build / Test

Open in Xcode (`Newston.xcodeproj`) for normal development. CLI:

```bash
# Build for the iOS Simulator
xcodebuild -project Newston.xcodeproj -scheme Newston \
  -destination 'platform=iOS Simulator,name=iPhone 16' build

# Run unit tests
xcodebuild -project Newston.xcodeproj -scheme Newston \
  -destination 'platform=iOS Simulator,name=iPhone 16' test
```

If the named simulator isn't installed, list available destinations with:

```bash
xcodebuild -project Newston.xcodeproj -scheme Newston -showdestinations
```

## Layout

```
Newston/                  app target — replace template files here
  NewstonApp.swift        @main, ModelContainer setup
  ContentView.swift       template list UI (to be replaced)
  Item.swift              placeholder @Model (to be replaced by Source/Headline/Article)
  Assets.xcassets/
NewstonTests/             unit tests (currently empty)
NewstonUITests/           UI tests (currently empty)
docs/
  CONCEPT.md
  ARCHITECTURE.md
```

## Conventions

- Service layer goes behind protocols (`SpeechSynthesizing`, `SpeechRecognizing`, `ArticleExtracting`, …) so tests inject fakes. Voice flows are tested at the service layer, not via XCUITest.
- Use Swift Concurrency (`async`/`await`, `actor`, `AsyncStream`). No Combine unless there's a concrete reason.
- Services that own mutable shared resources (audio session, WKWebView pool) are `actor`s.
- New SwiftData models are added to the `Schema` in `NewstonApp.swift`.

## Permissions (when adding voice features)

Adding TTS/STT requires Info.plist keys and capabilities — `GENERATE_INFOPLIST_FILE = YES` is on, so set these via build settings (`INFOPLIST_KEY_*`) rather than a hand-written Info.plist:

- `NSMicrophoneUsageDescription`
- `NSSpeechRecognitionUsageDescription`
- Background Modes → Audio (so TTS continues with the screen locked).

## Gotchas

- TTS and STT can hear each other. Pause `SFSpeechRecognizer` while `AVSpeechSynthesizer` is speaking, or the app will recognize its own voice as commands.
- On-device `SFSpeechRecognizer` support depends on locale; check `supportsOnDeviceRecognition` per source language.
- `WKWebView` must be retained while extraction runs and lives on the main actor — wrap it in an actor that hops to `@MainActor` for the `WKWebView` calls.
