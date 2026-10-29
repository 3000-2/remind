[English](README.md) · [한국어](README.ko.md)

# remind

A CLI for macOS Reminders built on EventKit. It handles what AppleScript can't: recurrence rules, multiple alerts, and URLs.

## Install

Requires macOS 14+ and Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/3000-2/remind && cd remind
make install   # installs to ~/.local/bin
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc && exec zsh   # if not on PATH yet
remind lists   # first run asks for Reminders access
```

Access is granted to the app that runs `remind` (Terminal, iTerm, your editor). Change it in System Settings > Privacy & Security > Reminders.

## Usage

```bash
remind add "Title" --list Work --on 2026-11-16 --at 10:00 --every mon --alert-before 1d --note memo --url https://...
remind list [--list name] [--done] [--json]
remind lists
remind done <id>...
remind delete <id>...
remind move <id> --list name
remind help
```

- Without `--list`, reminders go to the default list.
- A date without a time defaults to 09:00 (see Config). A time without a date means today, or tomorrow if that time has passed.
- Adding a title that already exists as an incomplete reminder in the same list is refused (`--force` to override).
- Sections, groups, tags, subtasks, and flags are not supported by EventKit.

## Config

Optional. `~/.config/remind/config.json` (or `$XDG_CONFIG_HOME/remind/config.json`):

```json
{
  "aliases": { "p": "Reminders", "w": "Work" },
  "defaultTime": "09:00",
  "listDefaultTimes": { "Work": "10:00" }
}
```

- `aliases`: short names for `--list`.
- `defaultTime`: time used when only a date is given.
- `listDefaultTimes`: per-list override of `defaultTime`, keyed by list name or alias.

## Use with an agent

Install the skill. It works with Claude Code, Codex, Cursor, and other agents that support skills:

```bash
npx skills add 3000-2/remind
```

Or add this to `AGENTS.md` / `CLAUDE.md`:

```markdown
## Reminders

Use the `remind` CLI for macOS Reminders (synced to iPhone). Run `remind help` for all options.
- `remind lists` for list names, `remind list --json` to read.
- `remind add "title" --list <name> --on YYYY-MM-DD --at HH:MM` to add.
- Run `done` / `delete` / `move` only when the user asks.
```

Or just tell your agent: "use the remind CLI (`remind help`)".
