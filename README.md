<p align="center"><img src="docs/images/icon.png" width="128" alt="Tsuzuri app icon: a stitch-bound notebook whose binding thread turns into a voice waveform"></p>

# Tsuzuri

A menu-bar voice input app for Japanese on macOS. Press a key, speak, and the text is typed into whatever app you are in — with live captions while you talk, a personal dictionary that writes tech terms the way you write them, and an on-device LLM that points out which words to add to it.

[![CI](https://github.com/GentaAmeku/Tsuzuri/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/GentaAmeku/Tsuzuri/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![macOS 26](https://img.shields.io/badge/macOS-26-black.svg)](#install)
[![Swift 6.2](https://img.shields.io/badge/Swift-6.2-F05138.svg)](Package.swift)

English | [日本語](README.ja.md)

Japanese dictation is good at Japanese and bad at the words a developer actually says. *Claude Code* comes out as クロードコード, *TanStack Query* as タンスタッククエリ, *Vitest* as B テスト, and every prompt to a coding agent needs a round of fixing before you can send it. Tsuzuri is for people who talk to Claude Code and Codex, write Slack messages and draft documents by voice all day: the words you use come out spelled the way you spell them, and it gets better at your words the more you use it.

<img src="docs/images/hud-demo.gif" alt="The recording display: a small pill with a red stop button grows upward into a card as live captions arrive, new characters fade in from a blur, then it turns into a spinner and a check mark after pasting" width="864">

*Press, speak, and watch it type. New characters fade in as you talk; a check mark when it is pasted.*

## Start in two lines

```bash
git clone https://github.com/GentaAmeku/Tsuzuri.git && cd Tsuzuri
claude   # then type /tsuzuri-setup   (Codex CLI: codex, then $tsuzuri-setup)
```

Any other agent? Paste this: *"Clone https://github.com/GentaAmeku/Tsuzuri and set it up by following SETUP.md."*

The setup is a game book: it opens with a checklist, your agent runs `doctor`, reads the section it points to, and repeats until everything checks out — Xcode, the signing certificate, building the app, the models and the permissions. It asks you only whether to use Soniox or stay on the Mac, whether to download the on-device models, and whether to launch at login. You type your API key and grant the permissions yourself; the agent never sees the key. When it is done, press the right ⌘ key and speak.

## What you get

### Press, speak, and it is typed where you are

Tap the right ⌘ key to start and again to stop, or hold it while you talk. The display appears the moment you press, captions stream in while you speak, and the text lands in the app you were typing in — a chat box, an agent prompt, a document. Press Return while recording to paste and send in one go.

![The recording display in the blue-and-white theme and the black theme, showing a dictated sentence with tech terms](docs/images/hud-themes.png)

*Two themes, blue and white or black. Words the recognizer may still change are shown lighter.*

### Tech terms come out the way you write them

Add a word once and Tsuzuri listens for it: the recognizer is told to expect it, and when it still comes out in katakana, Tsuzuri fixes it before pasting — クロードコード becomes Claude Code, even in the captions while you are still talking. Fillers like えーと disappear, and a space goes between Japanese and English words.

![The dictionary window: a one-line field to add a word with Return, an optional field for misheard spellings, and a table of words and their misheard spellings](docs/images/dictionary.png)

Adding a word is one line: type it and press Return. *Suggest readings* proposes the katakana it might be misheard as.

### It tells you what to add

After each paste, Tsuzuri quietly looks for words that were probably misheard and asks Apple's on-device model what you meant. The candidates wait in a window; keep the ones you want, fix the spelling if needed, and the next time you say them they come out right. Nothing is added without you, and pairs you discard never come back.

![The candidate window: misheard words struck through in red, an arrow to the suggested spelling in an editable field, the sentence they appeared in, and buttons to discard or add each one](docs/images/candidates.png)

### Fast in the cloud, private on the Mac

With [Soniox](https://soniox.com), the text is ready about 0.2 seconds after you stop. Switch to *On-device* in the menu and nothing leaves the Mac: Whisper writes the text and Apple's speech model shows the captions. If Soniox ever fails, Tsuzuri transcribes the recording on the Mac instead (when the on-device model is installed), so the sentence is not lost.

## How to use

| Key | What it does |
| --- | --- |
| Right ⌘, tap | Start recording; tap again to stop and paste |
| Right ⌘, hold | Record while held; let go to paste |
| Esc while recording | Cancel |
| Return while recording | Stop, paste, then send |
| ⌃⌥⌘V | Paste the last text again |

From the menu-bar icon:

| Menu | What it does |
| --- | --- |
| 認識 | Choose Soniox or on-device (Mac 内) |
| 直前の録音を認識し直す | Transcribe the last recording again, with Soniox or on the Mac |
| 履歴 | The last texts; pick one to copy it |
| 辞書の候補(N件)… | The words Tsuzuri suggests adding |
| 辞書を編集… | Add and fix your own words |
| 設定… | The recording key (right ⌘, right ⌥ or fn), tap or hold, the theme, launch at login, and the Soniox API key |

The menu also shows how much Soniox you used this month, with an estimated cost.

## Install

You need a Mac with Apple silicon on macOS 26, Xcode 26, and an Apple Development certificate (a free Apple ID is enough; the setup shows how to make one). A Soniox account is optional — without it, Tsuzuri runs on the Mac only. The app's screens are in Japanese.

Run the setup above with Claude Code or Codex. Every step is also written in [SETUP.md](SETUP.md) ([SETUP.ja.md](SETUP.ja.md) in Japanese) if you prefer to do it by hand. To update, `git pull` and run the setup again; it rebuilds the app and leaves the rest as it is. To uninstall, see Appendix B of SETUP.md.

What the app can reach — the microphone, Accessibility, the network — and how to report a vulnerability are in [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE). Tsuzuri uses [WhisperKit](https://github.com/argmaxinc/WhisperKit) (MIT), [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) (MIT) and [swift-argument-parser](https://github.com/apple/swift-argument-parser) (Apache 2.0).
