# Newston — Architecture

This document describes the technical architecture of Newston. See [CONCEPT.md](CONCEPT.md) for the product concept.

## Platform

- **iOS** app (iPhone + iPad), Swift 5, SwiftUI.
- Deployment target: iOS 26.4.
- Persistence: **SwiftData**.
- Audio: **AVFoundation** (`AVSpeechSynthesizer`, `AVAudioSession`).
- Speech recognition: **Speech** framework (`SFSpeechRecognizer`, on-device where supported).
- Web rendering for extraction: **WebKit** (`WKWebView`, off-screen).

## Current State

The repo is an Xcode SwiftUI + SwiftData template. The scaffolding is:

- `Newston/NewstonApp.swift` — `@main` app, sets up a `ModelContainer` with the `Item` schema.
- `Newston/ContentView.swift` — placeholder `NavigationSplitView` listing `Item`s.
- `Newston/Item.swift` — placeholder `@Model` with a `timestamp: Date`.
- `NewstonTests/`, `NewstonUITests/` — empty test targets.

Everything below describes the target architecture; the template files (`Item`, list UI) will be replaced as we build.

## High-Level Structure

The app is organized into layers, each with a clear responsibility. Lower layers do not depend on higher ones.

```
┌─────────────────────────────────────────────────────────┐
│  UI (SwiftUI Views)                                     │
│   ├─ TabView                                            │
│   │   ├─ Now Listening (current source/headline,        │
│   │   │                  transport controls)            │
│   │   └─ Sources (list, refresh-status badges,          │
│   │              add/remove, optional drill-in)         │
│   └─ Add-source flow (URL entry + visible WKWebView     │
│                       for consent / login)              │
├─────────────────────────────────────────────────────────┤
│  App State (ObservableObject / @Observable)             │
│   ├─ NavigationState (source, headline, mode)           │
│   └─ PlaybackState (idle/speaking/paused)               │
├─────────────────────────────────────────────────────────┤
│  Services                                               │
│   ├─ SpeechSynthesizerService   (TTS)                   │
│   ├─ SpeechRecognizerService    (STT)                   │
│   ├─ CommandParser              (text → Command)        │
│   ├─ FeedService                (RSS/Atom + HTML        │
│   │                              fallback)              │
│   └─ ArticleExtractor           (WKWebView + JS)        │
├─────────────────────────────────────────────────────────┤
│  Persistence (SwiftData)                                │
│   ├─ Source                                             │
│   ├─ Headline                                           │
│   └─ Article (cached body)                              │
└─────────────────────────────────────────────────────────┘
```

## Domain Model (SwiftData)

```swift
@Model final class Source {
    var name: String
    var url: URL          // homepage / feed URL
    var feedURL: URL?     // resolved RSS/Atom feed, if any
    var order: Int        // user-controlled ordering
    var headlines: [Headline]
}

@Model final class Headline {
    var title: String
    var articleURL: URL
    var publishedAt: Date?
    var fetchedAt: Date
    var source: Source?
    var article: Article?
}

@Model final class Article {
    var headline: Headline?
    var bodyText: String      // extracted, plain text for TTS
    var extractedAt: Date
    var extractor: String     // "readability" | "llm" | …
}
```

The placeholder `Item` model is removed once `Source` lands.

## Services

### SpeechSynthesizerService (TTS)
Wraps `AVSpeechSynthesizer`. Owns an `AVAudioSession` configured for `.playback` so audio continues with the screen locked. Exposes `speak(_:)`, `stop()`, `pause()`, `resume()` and publishes a `PlaybackState`.

### SpeechRecognizerService (STT)
Wraps `SFSpeechRecognizer` with `SFSpeechAudioBufferRecognitionRequest`. Continuous listening with on-device recognition where the locale supports it. Emits recognized utterances as a stream. Coordinates with the TTS service so the mic does not pick up the synthesizer's own voice (either pause STT during speech, or apply echo suppression).

### CommandParser
Pure function: `String -> Command?`. Maps recognized phrases to a small enum:

```swift
enum Command {
    case nextSource, previousSource, goToSource(String)
    case nextHeadline, previousHeadline, openCurrent
    case stop, pause, resume, backToHeadlines
}
```

Matching is keyword-based with reasonable variants ("next", "skip", "go on" → `nextHeadline`). Unit-testable in isolation.

### FeedService
- Resolves a source URL to a feed (RSS/Atom auto-discovery via `<link rel="alternate">`).
- Parses feeds with `XMLParser` (or `FeedKit` if we take the dependency).
- Fallback: scrape headline links from the homepage when no feed is available.
- Persists `Headline` rows under their `Source` and dedupes by `articleURL`.

### ArticleExtractor
- Loads the article URL in an off-screen `WKWebView`.
- After `didFinish`, injects a Readability-style script via `evaluateJavaScript(_:)` to extract title + body text from the rendered DOM.
- Returns plain text suitable for TTS (paragraph breaks preserved as natural pauses).
- LLM fallback (out of scope for v1) sits behind the same protocol so the call site does not change.
- Shares a `WKWebsiteDataStore` with the source consent/login flow (below) so cookies and authenticated sessions captured at source-add time apply to article fetches.

### Source consent / login flow
When the user adds a source, the homepage is loaded in a **visible** `WKWebView` (sheet) so they can dismiss cookie/GDPR consent banners and, if needed, log into paywalled sites. The user dismisses with a manual "Done" button — we do not auto-click consent banners or scrape login forms. Cookies and session storage are persisted via a shared `WKWebsiteDataStore` (created once at app launch) so the off-screen `ArticleExtractor` reuses the same authenticated session for every later fetch from that source.

## Reactive Flow

1. User opens the app. `NavigationState` selects the first `Source`.
2. The view subscribes to `NavigationState` and triggers `FeedService.refresh(source:)` if headlines are stale.
3. TTS reads "from {source}, headline 1: {title}" then pauses briefly. STT is listening.
4. User says "read this". `SpeechRecognizerService` emits the utterance; `CommandParser` returns `.openCurrent`.
5. `NavigationState` transitions to `.reading(headline)`. If `headline.article` is nil, `ArticleExtractor` runs; otherwise the cached body is used.
6. TTS speaks the article body. User says "stop" → `PlaybackState.idle`, `NavigationState` returns to headline mode.

State transitions live in `NavigationState`; services do not mutate each other directly.

## Concurrency

- Services are `actor`s where they own mutable resources (the `WKWebView` pool, the audio session).
- Public APIs are `async` and return values or `AsyncStream`s (STT utterances, feed refresh progress).
- UI uses Swift Concurrency via `.task { … }` modifiers; no Combine unless a specific need appears.

## Permissions & Capabilities

- Microphone (`NSMicrophoneUsageDescription`).
- Speech recognition (`NSSpeechRecognitionUsageDescription`).
- Background audio capability so TTS keeps playing when the screen is off.
- Network access for feeds and articles (no special entitlement needed).

## Testing Strategy

- **Unit**: `CommandParser` (phrase matrix), feed parsing fixtures, extractor against saved HTML pages.
- **Service**: `SpeechSynthesizerService`/`SpeechRecognizerService` behind protocols so tests inject fakes.
- **UI**: a small set of `XCUITest`s for the source list and headline navigation; voice flows are covered at the service layer rather than via UI tests.

## Open Questions

- Echo cancellation between TTS and STT — does pausing recognition during speech suffice, or do we need active mic gating?
- Continuous on-device recognition battery cost — push-to-talk wake phrase as an alternative?
- Article extraction quality threshold for triggering the LLM fallback — heuristic on text length / paragraph count?
- Multi-language sources (Danish, English, …) — per-source `AVSpeechSynthesisVoice` and `SFSpeechRecognizer` locale.
