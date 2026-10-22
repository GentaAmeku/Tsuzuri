# Setup

This file is written for a coding agent (Claude Code, Codex CLI, or any agent that can run shell commands). To install, start in one of these ways:

- **Claude Code:** clone the repository, start Claude Code in it, and type `/tsuzuri-setup`.
- **Codex CLI:** clone the repository, open it, and type `$tsuzuri-setup`.
- **Other agents:** clone the repository, open it, and ask: **"Set this up by following SETUP.md."**
- **Before cloning:** ask your agent: "Clone https://github.com/GentaAmeku/Tsuzuri and set it up by following SETUP.md."

The setup is a game book. `scripts/doctor.sh` checks the state and tells you which section to read next. The section numbers are the same in [SETUP.ja.md](SETUP.ja.md) (Japanese).

You can run the setup again at any time, for example after an update (Appendix A). Sections that are done stay done: doctor stops only where something is missing or not decided yet.

## 1. Introduction (for the agent)

First, in the repository root, run `scripts/doctor.sh --checklist` and show its output to the user as it is. It is a Markdown checklist with one line per section: what is done, what is left and which section comes next.

Then repeat this loop until `ok` is `true`:

1. In the repository root, run `scripts/doctor.sh --json`. It uses only what macOS ships with, so it works before Xcode is installed.
2. Read the section named by `next.section`. `next.reason` says what is missing. The exit code is 1 until the setup is complete.
3. Do what that section says, then run doctor again.

When `ok` is `true`, show the checklist again if you finished any section in this run.

`checks` lists every item with `status`: `ok`, `missing` (not there, or a choice not made yet), `outdated` (there, but built from an older version) or `skipped` (something the user declined).

Promises to the user:

- Speak the user's language. Ask only about the choices: Soniox or on-device only (section 5), downloading the on-device models (section 6) and launching at login (section 8). Decide everything else yourself. Do not ask again about what doctor reports as `ok` or `skipped`.
- **Never ask for the Soniox API key in the conversation, and never type, print or store it yourself.** The user enters it in the app or in their own terminal (section 5).
- Ask before downloading a model. Say how big it is.
- Never change System Settings yourself (privacy permissions, login items). Tell the user where to click.
- Never use `sudo`. When a step needs it, show the command and ask the user to run it.
- Do not change anything a section does not mention.

## 2. Prerequisites

doctor checks macOS 26 or later, Apple silicon, and Xcode with Swift 6.2 or later.

- **macOS older than 26, or an Intel Mac:** stop. Tsuzuri uses frameworks that exist only on macOS 26 on Apple silicon. Tell the user.
- **No Xcode, or `xcode-select` points to the Command Line Tools:** ask the user to install Xcode 26 or later from the App Store, open it once to finish installing its components, and then run in their terminal:

  ```bash
  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
  ```

- **Swift is found but too old, or Xcode's license is not accepted yet:** ask the user to update Xcode, or to run `sudo xcodebuild -license accept`.

## 3. Signing certificate

doctor checks that the keychain holds an *Apple Development* signing certificate (or that `TSUZURI_SIGNING_IDENTITY` names one). macOS ties the microphone and Accessibility permissions to the app's signature: without a stable certificate, every rebuild would lose them.

If there is none, ask the user to create one (a free Apple ID is enough):

1. Open Xcode, then **Xcode > Settings… > Accounts**, and add their Apple ID if it is not there.
2. Select the account, press **Manage Certificates…**, press **+** and choose **Apple Development**.

Then run doctor again. If the keychain has several identities and the user wants a specific one, set `TSUZURI_SIGNING_IDENTITY` to its full name (as `security find-identity -v -p codesigning` prints it) for the commands in section 4.

## 4. Build and install the app

doctor checks that `/Applications/Tsuzuri.app` exists, that its signature verifies, and that it was built from the repository's current commit (`outdated` after a `git pull`).

```bash
scripts/build-app-bundle.sh --install
```

- The first build downloads the Swift packages (WhisperKit, KeyboardShortcuts, swift-argument-parser) and takes several minutes. Later builds are quicker.
- The script quits a running Tsuzuri, replaces `/Applications/Tsuzuri.app`, signs it, and opens it.
- If macOS asks whether `codesign` may use the signing key in the keychain, the user should press **Always Allow**.
- Tsuzuri lives in the menu bar (a microphone icon), not in the Dock. On first launch its Settings window opens and asks for permissions; that is section 7, so tell the user they can leave it open for now.

## 5. Recognizer

doctor checks that either a Soniox API key is in the Keychain (service `Tsuzuri.Soniox`; doctor checks that the item exists and never reads it) or the user chose on-device only.

Ask the user which they want, and explain the difference:

| | Soniox (recommended for accuracy) | On-device only |
| --- | --- | --- |
| Accuracy on tech terms | Highest | Lower |
| Live captions while talking | Yes | Yes (with Apple's model, section 6) |
| Text pasted after you stop | About 0.2 s | About 2 s |
| Network and cost | Audio and hint words go to Soniox; paid (about $0.12 per hour of audio) | Nothing leaves the Mac; free |
| Needs | A Soniox account and API key | The WhisperKit model (section 6) |

The user can switch at any time from the menu (**認識**).

- **Soniox:** the user creates an API key in the Soniox console (https://soniox.com). Then they enter it themselves, in one of two ways:
  - In Tsuzuri: menu bar icon > **設定…** > **Soniox と辞書** tab, paste it into **新しいキーを貼り付け** and press **保存**. (Recommended: the app creates the Keychain item, so it is never asked for access.)
  - Or in their own terminal, from the repository: `swift run tsuzuri-eval set-key` (the input is hidden). The first time the app reads a key stored this way, macOS asks for Keychain access; press **Always Allow**.

  Wait for the user to say they did it, then run doctor again. Do not run `set-key` yourself and do not ask for the key.
- **On-device only:** record the choice and restart the app so it reads it:

  ```bash
  defaults write work.ameku.Tsuzuri localOnly -bool true
  pkill -x TsuzuriApp; sleep 1; open -a Tsuzuri
  ```

## 6. On-device models

doctor checks two models. Ask about both at once, with their sizes.

- **WhisperKit** (Whisper large-v3, about 600 MB in `~/Library/Caches/Tsuzuri/models`): writes the text in on-device mode, and is the fallback when Soniox fails. Required for on-device only; recommended with Soniox.
- **Apple's Japanese speech model** (installed by macOS; its size is decided by the system): shows live captions while you talk in on-device mode. Optional.

If the user agrees to both:

```bash
swift run -c release tsuzuri-eval fetch-model --apple
```

For WhisperKit only, leave out `--apple`. The download takes a few minutes. Then restart the app so it loads the model: `pkill -x TsuzuriApp; sleep 1; open -a Tsuzuri`.

Record what the user declined, so doctor stops asking (declining WhisperKit is possible only with Soniox):

```bash
defaults write work.ameku.Tsuzuri setupWhisperModel declined
defaults write work.ameku.Tsuzuri setupAppleModel declined
```

To be asked again later, delete the key: `defaults delete work.ameku.Tsuzuri setupWhisperModel`.

## 7. Permissions

doctor reads `~/Library/Application Support/Tsuzuri/setup-status.json`, which the app rewrites within a few seconds whenever its permissions change. It checks that the app is running, that the microphone is allowed, and that Accessibility is allowed and the recording key is being watched.

- **Not running:** `open -a Tsuzuri`.
- **Microphone:** in Tsuzuri's Settings window (it opens by itself while a permission is missing, or menu bar icon > **設定…** > **一般**), the user presses **許可する** next to **マイク** and allows it in the macOS dialog. If it was denied before, the button opens **System Settings > Privacy & Security > Microphone**, where the user turns on Tsuzuri.
- **Accessibility:** the user presses **許可する** next to **アクセシビリティ**. **System Settings > Privacy & Security > Accessibility** opens; the user turns on Tsuzuri (macOS may ask for their password).

Tsuzuri needs Accessibility to see the recording key, to catch Esc and Return while recording, and to paste with ⌘V. It looks only at key codes and never reads or stores what the user types ([SECURITY.md](SECURITY.md)). Tell the user this before they grant it.

Wait a few seconds after the user grants each one, then run doctor again. If Accessibility is on in System Settings but doctor still says it is not granted, the entry belongs to an older signature: ask the user to select Tsuzuri in the list, remove it with **−**, and turn it on again with **+** (choose `/Applications/Tsuzuri.app`).

## 8. Launch at login

Optional. Ask whether Tsuzuri should start when the user logs in.

- **Yes:** the user turns on **ログイン時に起動する** in Settings > **一般**. If macOS asks for approval, it is in **System Settings > General > Login Items**.
- **No:** record it:

  ```bash
  defaults write work.ameku.Tsuzuri setupLoginItem declined
  ```

## 9. Try it

doctor checks that the history has at least one dictated text.

Ask the user to try it:

1. Click into any text field — Notes, a chat box, a prompt.
2. Press the right ⌘ key briefly. A small pill with a red stop button appears at the bottom of the screen.
3. Say a sentence, for example 「Claude Code で TanStack Query のキャッシュを無効にして」.
4. Press the right ⌘ key again. The text is pasted where they were typing.

Then run doctor again. When it reports `ok`, tell the user what to try next: holding the right ⌘ key instead of tapping it, Return while recording to paste and send, ⌃⌥⌘V to paste the last text again, **辞書を編集…** to add their own words, and **辞書の候補** in the menu for the words Tsuzuri suggests.

## Appendix A. Update

```bash
git pull
```

Then run the setup again: `/tsuzuri-setup` in Claude Code, `$tsuzuri-setup` in Codex CLI, or ask other agents "Set this up by following SETUP.md." It starts with the checklist. Section 4 reports the app as `outdated` and rebuilds it; the other sections stay done.

## Appendix B. Uninstall

Ask before each step; the second one deletes the user's dictionary and history.

1. Quit Tsuzuri (menu bar icon > **Tsuzuri を終了**) and delete `/Applications/Tsuzuri.app`.
2. Delete the data and models: `~/Library/Application Support/Tsuzuri` and `~/Library/Caches/Tsuzuri`.
3. Delete the Soniox API key: `security delete-generic-password -s Tsuzuri.Soniox`.
4. Delete the preferences: `defaults delete work.ameku.Tsuzuri`.
5. Ask the user to remove Tsuzuri from **System Settings > Privacy & Security > Microphone** and **Accessibility**, and from **Login Items** if they turned it on.

Apple's Japanese speech model belongs to macOS and stays.

## Appendix C. Troubleshooting

- **Nothing happens when pressing the right ⌘ key:** check section 7 again. If the key is set to fn in Settings > **キー**, the system setting **Keyboard > Press 🌐 key to** must be **Do Nothing**.
- **The build fails with a signing error:** run `security find-identity -v -p codesigning` and check that an Apple Development identity is listed and valid (section 3).
- **Soniox fails:** Tsuzuri transcribes the recording on the Mac instead (if the WhisperKit model is there) and stays on-device for five minutes. Check the API key and the Soniox account's balance.
