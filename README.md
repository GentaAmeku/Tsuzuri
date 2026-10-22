<p align="center"><img src="docs/images/icon.png" width="128" alt="Tsuzuri app icon: a stitch-bound notebook whose binding thread turns into a voice waveform"></p>

# Tsuzuri

A menu-bar voice input app for Japanese on macOS. Press a key, speak, and the text is typed into whatever app you are in — with live captions while you talk, a personal dictionary that writes tech terms the way you write them, and an on-device LLM that points out which words to add to it.

[![CI](https://github.com/GentaAmeku/Tsuzuri/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/GentaAmeku/Tsuzuri/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![macOS 26](https://img.shields.io/badge/macOS-26-black.svg)](#install)
[![Swift 6.2](https://img.shields.io/badge/Swift-6.2-F05138.svg)](Package.swift)

English | [日本語](README.ja.md)

Japanese dictation is good at Japanese and bad at the words a developer actually says. *Claude Code* comes out as クロードコード, *TanStack Query* as タンスタッククエリ, *Vitest* as B テスト, and every prompt to a coding agent needs a round of fixing before you can send it. Tsuzuri is the app I built to dictate prompts to Claude Code and Codex, Slack messages and documents all day: streaming recognition with Soniox, an on-device fallback with WhisperKit, and a dictionary that both hints the recognizer and fixes what it still gets wrong.

<img src="docs/images/hud-demo.gif" alt="The recording display: a small pill with a red stop button grows upward into a card as live captions arrive, new characters fade in from a blur, then it turns into a spinner and a check mark after pasting" width="864">

*The recording display, captured from the real window. New characters fade in; the card grows upward without moving its bottom edge.*

## What you get

### Press, speak, and it is typed where you are

Press the right ⌘ key briefly to start and again to stop, or hold it and let go. The display appears the moment you press, captions stream in while you talk, and when you stop the text is pasted with ⌘V into the app you were typing in — your clipboard is borrowed and put back 0.3 seconds later. Press Return while recording to paste and send in one go (Slack, a chat box, an agent prompt), Esc to cancel, and ⌃⌥⌘V to paste the last text again. The key, the mode (tap, hold or both) and the long-press time can be changed in Settings.

![The recording display in the blue-and-white theme and the black theme, showing a dictated sentence with tech terms](docs/images/hud-themes.png)

*Two themes: blue and white (default) and black. Text that the recognizer may still change is shown lighter.*

### Tech terms come out the way you write them

The dictionary does two jobs. Its words are passed to the recognizer as hints (Soniox context terms, the Whisper prompt, Apple's contextual strings) — pinned words first, then words added in the last two weeks and the ones you use most — and entries with *misheard* spellings are replaced after recognition: クロードコード becomes Claude Code. Replacement only fires on whole words, decided by character class, so a katakana spelling inside a longer katakana word is left alone, and kanji spellings are never replaced (homophones are too common). The same rules also drop fillers (えーと, あのー) and put a space between Japanese and Latin words, and they run on the live captions too, so what you see while talking is close to what gets pasted.

![The dictionary window: a one-line field to add a word with Return, an optional field for misheard spellings, and a table of words and their misheard spellings](docs/images/dictionary.png)

Adding a word is one line: type it and press Return; it is saved at once. *Suggest readings* asks the on-device model for katakana spellings it might be misheard as.

### It tells you what to add

After each paste, Tsuzuri looks at the text in the background for words that were probably misrecognized — katakana that reads like a dictionary word, a technical term written out phonetically — and asks Apple's on-device Foundation Models for the spelling you most likely meant. Nothing is added on its own: the candidates wait in a window where you pick the ones to keep, fix the spelling, and choose whether to replace the word or only hint it. Pairs you discard never come back.

![The candidate window: misheard words struck through in red, an arrow to the suggested spelling in an editable field, the sentence they appeared in, and buttons to discard or add each one](docs/images/candidates.png)

### Works offline too

Choose *On-device* in the menu and nothing leaves the Mac: WhisperKit (Whisper large-v3, 626 MB) writes the text after you stop, and Apple's SpeechAnalyzer shows live captions while you talk. If Soniox cannot connect within 2 seconds or takes more than 3 seconds to finish, Tsuzuri transcribes the recording it kept on the Mac instead and stays on-device for five minutes. The menu also shows this month's Soniox usage with an estimated cost, and can re-transcribe the last recording.

## How it works

![How Tsuzuri works: the right ⌘ key starts a recording that is kept on the Mac; audio streams to Soniox in the cloud, or to the on-device WhisperKit on failure; the text goes through shaping, which uses the dictionary for replacement while the dictionary also sends hints to Soniox; the shaped text is pasted into your app, and a candidate scan with rules and Foundation Models feeds a candidate window where you choose words to add to the dictionary](docs/images/architecture.png)

The code is a Swift package with no Xcode project. `TsuzuriCore` holds everything without side effects — the hotkey state machine, assembling streamed text, the shaping and replacement rules, choosing hints, picking and filtering candidates — and carries the tests (134, written with swift-testing). `TsuzuriEngines` talks to the outside world: the Soniox WebSocket, WhisperKit, SpeechAnalyzer, Foundation Models, the microphone and the Keychain. `TsuzuriApp` is the menu-bar app in SwiftUI and AppKit, and `tsuzuri-eval` is the command-line tool used to measure every decision.

## Measured, not guessed

Before writing the app, I recorded 40 sentences of my own speech (prompts to coding agents, Slack messages, document sentences full of tech terms) and ran them through four recognizers. The app's choices come from this table.

| Recognizer | Dictionary hints | Character error rate | Tech terms right | Wait after you stop (median) | Memory |
| --- | --- | ---: | ---: | ---: | ---: |
| Soniox (cloud) | yes | **5.2%** | **85.5%** | **0.19 s** | — |
| WhisperKit large-v3 | yes | 10.9% | 59.7% | 2.08 s | ~0.2 GB |
| Qwen3-ASR 1.7B | yes | 12.6% | 59.7% | 0.85 s | ~7.2 GB |
| Apple DictationTranscriber | yes | 20.7% | 33.9% | 0.34 s | — |

Hints helped every recognizer the most, so Soniox with hints became the main path and WhisperKit the on-device one. Adding the shaping rules and a dictionary of ordinary misreadings on top of Soniox brought the character error rate to 3.1% and tech terms to 91.9%; with the two entries I added after seeing the errors, 2.3% and 95.2% (optimistic, since those two came from the same 40 sentences).

The candidate scan was measured the same way, on 160 saved transcripts: it points out 54% of the misrecognized words with 2.1 wrong candidates per 10 sentences. The spelling the small on-device model proposes is right only about a quarter of the time — it does not know most product names — which is why every candidate is shown with an editable spelling instead of being added automatically.

## How it was made

Tsuzuri was designed and built in conversation with [Claude Code](https://www.anthropic.com/claude-code), in five stages: measure, a minimum app, the dictionary and fallback, the candidate scan, and polish. Each stage started from a design document and ended with a check against it, and every open decision — which recognizer, how strict the candidate scan should be, which of four recording displays, which app icon — was asked as a question sheet with comparison tables and mock-ups, made with my other project, [AI Handout Studio](https://github.com/GentaAmeku/ai-handout-studio). The app icon was drawn with Codex's image generation. The idea came from a video by クウキデザイン showing a Soniox-plus-dictionary voice input setup; Tsuzuri is my own take on it for Japanese tech work.

## What it touches

- **Permissions:** the microphone, and Accessibility to see the recording key (a `CGEventTap`), to catch Esc and Return while recording, and to paste with ⌘V. The key monitor looks only at key codes — it never reads or stores what you type — and it does not record while a password field has secure input on. The app is signed with the hardened runtime and asks for no entitlement other than audio input; it is not sandboxed, because pasting with synthetic key events and reading the focused field through Accessibility are not available to sandboxed apps.
- **Network:** in Soniox mode, audio is streamed to Soniox over TLS while you record, together with the dictionary words chosen as hints — keep that in mind before adding names you would not send to a cloud service. In on-device mode nothing is sent. The Soniox API key is kept in the Keychain (service `Tsuzuri.Soniox`), never in a file or a log.
- **Pasting:** the text goes to the app that was in front when you stopped. If another app has come to the front by the time the text is ready, Tsuzuri does not paste (or send Return) there; it leaves the text on the clipboard and tells you.
- **Clipboard:** borrowed to paste and restored 0.3 seconds later, marked so clipboard-history apps skip it — unless you copied something else in the meantime, or the old contents were marked as concealed by a password manager.
- **Files:** the dictionary, the candidates, the last 100 texts, monthly Soniox usage and (by default) the last 7 days of audio are in `~/Library/Application Support/Tsuzuri`. The on-device models are in `~/Library/Caches/Tsuzuri/models`. The app never downloads a model by itself; `fetch-model` downloads WhisperKit's model from Hugging Face over HTTPS. The app does not write what you said to the system log.

## Install

You need a Mac with Apple silicon on macOS 26, Xcode 26 (Swift 6.2), and an *Apple Development* certificate in your keychain — macOS ties the microphone and Accessibility permissions to the app's signature, so the build script signs it. For the candidate scan and reading suggestions, turn on Apple Intelligence. A [Soniox](https://soniox.com) API key is optional; without one, use on-device mode.

```bash
git clone https://github.com/GentaAmeku/Tsuzuri.git && cd Tsuzuri
swift run tsuzuri-eval fetch-model --apple   # on-device models: WhisperKit (~600 MB) and Apple's Japanese model
swift run tsuzuri-eval set-key               # optional: store your Soniox API key in the Keychain
scripts/build-app-bundle.sh --install        # build, sign and put Tsuzuri.app in /Applications
```

On first launch the Settings window opens; allow the microphone and Accessibility there (the Soniox API key can also be pasted there instead of using `set-key`). Then press the right ⌘ key and speak.

| Key | What it does |
| --- | --- |
| Right ⌘, short press | Start recording; press again to stop and paste |
| Right ⌘, hold (0.5 s or longer) | Record while held; let go to paste |
| Right ⌘ with another key within 0.2 s | Treated as a shortcut such as ⌘C; nothing happens |
| Esc while recording | Cancel |
| Return while recording | Stop, paste, then send Return |
| ⌃⌥⌘V | Paste the last text again |

## Known limits

- Built for Japanese with English tech terms. The app's screens are in Japanese only.
- macOS 26 and Apple silicon only. There is no prebuilt or notarized download: you build and sign it yourself.
- Soniox is a paid API (about $0.12 per hour of audio, plus text tokens for the hints). The menu shows an estimate for the month; check the exact amount on Soniox's dashboard.
- On-device mode pastes about 2 seconds after you stop, and its live captions come from a different recognizer than the pasted text, so the two can differ.
- It is a personal tool: the defaults, timings and starter dictionary are tuned for one person's work.

## Security

How to report a vulnerability, and what the app can reach: [SECURITY.md](SECURITY.md).

## Read more

- How each stage was built, and how to run the evaluation CLI (in Japanese): [docs/development.ja.md](docs/development.ja.md)
- `swift build` and `swift test` check everything; `Tools/Qwen3Eval` is a separate package used only for the evaluation.

## License

[MIT](LICENSE). Tsuzuri uses [WhisperKit](https://github.com/argmaxinc/WhisperKit) (MIT), [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) (MIT) and [swift-argument-parser](https://github.com/apple/swift-argument-parser) (Apache 2.0).
