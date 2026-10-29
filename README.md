[English](README.md) · [한국어](README.ko.md)

# remind

A CLI for macOS Reminders built on EventKit. It handles what AppleScript can't: recurrence rules, multiple alerts, and URLs.

```bash
make install   # ~/.local/bin/remind
remind add "Title" --list Work --on 2026-11-12 --at 10:00 --every mon --alert-before 1d --note memo --url https://...
remind list [--list name] [--done] [--json]
remind lists
remind done <id>... · remind delete <id>... · remind move <id> --list name
```

- Without `--list`, reminders go to the default list.
- Aliases: `personal`/`개인` → `미리 알림`, `work` → `업무`.
- A date without a time defaults to 10:00 for the `업무` list and 09:00 otherwise. A time without a date means today, or tomorrow if that time has passed.
- Adding a title that already exists as an incomplete reminder in the same list is refused (`--force` to override).
- On first run, your terminal app needs full access to Reminders.
- Sections, groups, tags, subtasks, and flags are not supported by EventKit.
