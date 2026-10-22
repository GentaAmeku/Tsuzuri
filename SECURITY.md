# Security

Tsuzuri is a Mac app you build, sign and run yourself. There is no server and no account; the only service it talks to is Soniox, and only in Soniox mode.

## What it can reach

- **Microphone.** Recording starts when you press the recording key and stops when you stop it. It does not start while macOS has secure input on (a password field, for example). When the key turns out to be part of a shortcut such as ⌘C, the moment of audio already captured is thrown away without being sent or saved.
- **Accessibility.** Used for three things: a `CGEventTap` that looks at key codes to see the recording key, Esc and Return (it never reads characters or stores what you type); reading the role of the focused element to decide whether there is a text field to paste into; and posting ⌘V and Return.
- **Network.** In Soniox mode, audio is streamed to `wss://stt-rt.soniox.com` while you record, with the dictionary words chosen as hints. In on-device mode, nothing leaves the Mac. The models are downloaded only when you run `swift run tsuzuri-eval fetch-model`, from Hugging Face over HTTPS.
- **Keychain.** The Soniox API key is a generic password in your login keychain (service `Tsuzuri.Soniox`). It is sent only in the `Authorization` header of the Soniox connection and is never written to a file or a log.
- **Files.** `~/Library/Application Support/Tsuzuri` holds the dictionary, the candidates (with up to 20 characters around each word), the last 100 texts and, unless you turn it off, the last 7 days of audio. They are plain files, readable only by your account (and encrypted at rest if FileVault is on); the app does not encrypt them itself.

## Decisions made for safety

- **Pasting goes where you stopped.** If a different app comes to the front between stopping and pasting, the text is left on the clipboard instead of being typed (and Return sent) into, say, a terminal.
- **The clipboard is borrowed, not kept.** The pasted text is marked `org.nspasteboard.TransientType` so clipboard-history apps skip it, and the previous contents are put back 0.3 seconds later. Contents marked concealed by a password manager are never copied or put back.
- **Hardened runtime, one entitlement.** The build script signs the app with the hardened runtime and only `com.apple.security.device.audio-input`, so other code cannot be injected into it to borrow its permissions. It is not sandboxed: synthetic key events and Accessibility are not available to sandboxed apps.
- **No debug entry points in the release build.** The launch arguments used to check the screens (`--render-hud` and others) exist only in debug builds.
- **Pinned dependencies.** `Package.resolved` pins every Swift package to a revision, and CI pins its GitHub Action to a commit and runs with read-only permissions.
- **Suggestions are only suggestions.** The on-device model that proposes dictionary words reads your own pasted text, and nothing it says is acted on until you add it in the candidate window.

## Reporting a vulnerability

Please report security issues through [GitHub's private vulnerability reporting](https://github.com/GentaAmeku/Tsuzuri/security/advisories/new) rather than a public issue, so a fix can go out before the details are public. Include what you found, how to reproduce it, and its impact if you can.
