# Newston — Concept

## Summary

Newston is a hands-off iOS news reader. The user adds news websites (primarily) as sources, and the app reads headlines and articles aloud using Text-to-Speech (TTS). The user navigates entirely by voice via Speech-to-Text (STT) — no tapping required while listening.

The target use case is consuming news while the hands and eyes are busy: driving, walking, cooking, exercising, commuting.

## Core Idea

- **Hands-off**: every primary action is voice-driven.
- **Eyes-off**: the user does not need to look at the screen during normal use.
- **Source-driven**: the user curates a list of news websites; the app pulls headlines from each.
- **Linear listening**: the app reads headlines, the user picks one, the app reads the article. Simple and predictable.

## User Flow

1. User opens the app (or activates it via voice / shortcut).
2. App announces the current source and starts reading headlines.
3. User issues a voice command at any time to navigate.
4. When the user picks a headline, the app reads the full article aloud.
5. User can stop, skip, or move between sources with voice.

## Voice Navigation

The voice command surface is intentionally small. There are three navigation axes:

### 1. Sources (news websites)
- "Next source" — move to the next news site in the list.
- "Previous source" — move to the previous one.
- "Go to {source name}" — jump directly to a source.

### 2. Headlines (within current source)
- "Next headline" — skip to the next headline.
- "Previous headline" — go back one headline.
- "Read this" / "Open" — read the full article for the current headline.

### 3. Reading control
- "Stop" — stop reading.
- "Pause" / "Resume" — pause and resume playback.
- "Back to headlines" — leave the article and return to headline list.

The exact wording is not fixed — the STT layer should accept reasonable variations.

## Sources

- The user adds news sources by URL (or picks from a starter list).
- The app fetches headlines from each source. RSS/Atom feeds are the preferred mechanism; HTML scraping is a fallback when no feed is available.
- Article bodies are extracted for TTS (reader-mode style content extraction).

## Components

- **TTS engine** — reads headlines and article bodies aloud. Uses iOS `AVSpeechSynthesizer` initially.
- **STT engine** — listens for voice commands. Uses iOS `Speech` framework (`SFSpeechRecognizer`) with on-device recognition where possible.
- **Source manager** — stores the user's list of news websites and fetches headlines.
- **Article extractor** — pulls clean article text from a page URL. Renders the page in `WKWebView` and extracts the body via a Readability-style script against the fully rendered DOM. An LLM-based extractor is reserved as a fallback for sites where the deterministic extractor produces poor results.
- **Navigation state** — tracks current source, current headline, and playback state.
- **Command parser** — maps recognized speech to one of the navigation commands above.

## Out of Scope (for the initial concept)

- Social features, sharing, comments.
- Multi-user accounts or cloud sync.
- Non-news content (podcasts, video, long-form).
- Background/lockscreen control beyond what TTS naturally provides.
- Translation between languages.
