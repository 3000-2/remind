# AGENTS.md

remind is a Swift CLI over EventKit for macOS Reminders. People install it with `make install`; agents drive it through `skills/remind/SKILL.md`.

## Layout

- `Sources/RemindCore/Parse.swift`: pure parsing and date logic (unit-tested)
- `Sources/RemindCore/Store.swift`: EventKit access and output
- `Sources/RemindCore/CLI.swift`: commands and `runCLI`
- `Sources/remind/main.swift`: entry point
- `Tests/RemindCoreTests`: unit tests (Swift Testing), CLI output tests, and `EndToEnd`, which runs only with `REMIND_E2E=1`
- `skills/remind/SKILL.md`: the skill users install; keep it in sync with `remind help`
- `Package.swift`, `.swift-format`, `Makefile`: build, format and lint setup; `.agents/skills/ship`: the commit checklist

## Rules

- Every `remind` write reaches the user's real Reminders and iPhone. Write only to the `remind-test` list, and run `make e2e` or any write command only with the user's OK.
- Keep the interface small. New commands or flags need the user's approval.
- Every string the CLI prints goes through `sanitize`. `--url` stays http(s) only.
- English for code, commits, and docs. `README.ko.md` mirrors `README.md`.
- No comments unless the reason is not obvious from the code.

## Before every commit or push (required)

Follow `.agents/skills/ship/SKILL.md`. It covers format, lint, tests, docs, the commit message, and asking before push.
