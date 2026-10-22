---
name: tsuzuri-setup
description: Tsuzuri をこの Mac に入れる。更新のあとに流し直してもよい(SETUP のゲームブックを doctor に沿って進め、最初に進み具合のチェックリストを見せる)
---

Set up Tsuzuri on this Mac by following the setup game book. Speak the user's language throughout. Running it again later (for example after `git pull`) is safe: doctor stops only at what is missing or not decided yet.

1. In the repository root, run `scripts/doctor.sh --checklist` and show its output to the user as it is (a Markdown checklist: one line per section, what is done and which section comes next). Do this first, before anything else.
2. Run `scripts/doctor.sh --json`.
3. If `ok` is `true`: if you finished any section in this run, show the checklist again (step 1). Tell the user the setup is complete, mention each `warn` check with its detail, and stop.
4. Otherwise, read the section numbered `next.section` in `SETUP.md` (in `SETUP.ja.md` if the user speaks Japanese) and do what it says. `next.reason` says what is missing.
5. At the end of the section, go back to step 2.

Keep the promises in section 1 of SETUP.md: ask only about the choices doctor reports as `missing`, never ask for or handle the Soniox API key yourself (the user types it in), get the user's consent before downloading a model, never change System Settings yourself, and never use `sudo`. SETUP.md is the only source of what each section does, so read it instead of guessing.
