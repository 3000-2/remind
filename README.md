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
- A date without a time defaults to 09:00. A time without a date means today, or tomorrow if that time has passed.
- Adding a title that already exists as an incomplete reminder in the same list is refused (`--force` to override).
- On first run, your terminal app needs full access to Reminders.
- Sections, groups, tags, subtasks, and flags are not supported by EventKit.

## Config

Optional. `~/.config/remind/config.json` (or `$XDG_CONFIG_HOME/remind/config.json`):

```json
{
  "aliases": { "personal": "Reminders", "work": "Work" },
  "defaultTime": "09:00",
  "listDefaultTimes": { "Work": "10:00" }
}
```

- `aliases`: short names for `--list`.
- `defaultTime`: time used when only a date is given.
- `listDefaultTimes`: per-list override of `defaultTime`.
