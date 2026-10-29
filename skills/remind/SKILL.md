---
name: remind
description: Add, list, complete, and move Apple Reminders on macOS with the `remind` CLI (synced to iPhone via iCloud). Use when the user says "remind me", asks to add, check, or complete reminders, or when a task needs a follow-up on a future date (offer it; don't add it unasked).
compatibility: Requires macOS 14+ and the remind CLI (https://github.com/3000-2/remind)
---

# remind

`remind` writes to the user's real Reminders, which sync to their iPhone and fire notifications. Run `remind help` for every option.

## Before adding

- Add only when the user asks, or after they confirm a reminder you proposed.
- Run `remind lists` to see list names. Use a list that matches the request; otherwise omit `--list` to use the default list.
- Prefer `--on today|tomorrow` and `--next mon..sun` over computing dates yourself.

## Commands

```bash
remind lists
remind list [--list name] [--done] [--json]
remind add "Title" [--list name] [--on YYYY-MM-DD|today|tomorrow] [--next mon..sun] [--at HH:MM]
                   [--every day|weekday|mon..sun|1st..31st] [--alert-before 30m|2h|1d]
                   [--note text] [--url url] [--priority high|medium|low]
remind done <id>...
remind delete <id>...
remind move <id> --list name
remind help
```

- Write the title as one actionable line. Put links in `--url` and details in `--note`.
- A date without `--at` uses the default time (09:00 unless configured). `--at` alone means today, or tomorrow if that time has passed.
- `--every` sets the due date to the first matching time after both `--on`/`--next` and now.
- `add` refuses a title that already exists as an incomplete reminder in the same list. Don't pass `--force` unless the user wants a duplicate.
- `remind list --json` gives IDs and ISO 8601 due dates.
- Run `done`, `delete`, and `move` only when the user asks. Before `delete`, show the matching reminder and confirm; if several match, ask which.

## Errors

- `command not found`: tell the user to install it from https://github.com/3000-2/remind.
- `No access to Reminders`: the app running the agent (Terminal, iTerm, editor) needs access in System Settings > Privacy & Security > Reminders. Tell the user; you can't grant it. In a sandboxed agent, run `remind` outside the sandbox.
- `List not found`: check `remind lists` and retry with an exact name.
