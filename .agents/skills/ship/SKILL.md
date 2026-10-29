---
name: ship
description: Required checklist before any git commit or git push in the remind repository. Use whenever you are about to commit, amend, or push here.
metadata:
  internal: true
---

# ship

Run every step in order. Stop and report if one fails; don't commit around a failure.

1. `make format`, then `make check` (lint + unit tests). Both must pass with no lint output.
2. If `Sources/`, `Package.swift`, or `Tests/RemindCoreTests/EndToEndTests.swift` changed, ask the user before `make e2e` (it writes to the `remind-test` list in their Reminders). Run it once they agree; if they decline, say it was skipped.
3. If commands, flags, defaults, or output changed, update together: `help` in `CLI.swift`, `README.md`, `README.ko.md`, `skills/remind/SKILL.md`. If files moved, update the layout in `AGENTS.md`.
4. Stage with `git add` after formatting, then review `git diff --staged` for secrets, personal data, and stray files.
5. Commit in English as `<type>: <description>` (feat, fix, refactor, docs, test, chore, perf). No AI attribution or Co-Authored-By lines.
6. Push only when the user explicitly says so. Never force-push without their explicit OK.
