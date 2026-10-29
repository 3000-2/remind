[English](README.md) · [한국어](README.ko.md)

# remind

A CLI for macOS Reminders built on EventKit, made for AI agents and people. Reminders sync to iPhone via iCloud.

## Install

Requires macOS 14+ and Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/3000-2/remind && cd remind
make install   # installs to ~/.local/bin
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc && exec zsh   # if not on PATH yet
remind lists   # first run asks for Reminders access
```

Access is granted to the app that runs `remind` (Terminal, iTerm, your editor), so anything run from that app can use it. Change it in System Settings > Privacy & Security > Reminders.

## Usage

```bash
remind lists                                    # list names; the default list is marked
remind list --due today --json                  # find ids
remind add "Pay rent" --list Home --on 2026-11-25 --at 10:00 --alert 1d
remind add "Standup" --every weekday --at 09:30
remind add "Passport renewal" --on 2027-03-01 --all-day
remind edit <id> --on fri --note "bring receipt"
remind done <id>
remind help                                     # every option
```

- Dates: `YYYY-MM-DD`, `today`, `tomorrow`, or a weekday (`mon` = the next Monday after today).
- Repeat: `--every day|weekday|year|mon,wed|10th,25th,last`.
- A due time gets an on-time alarm; `--alert 1d` adds one early alarm, `--alert none` removes alarms. `--all-day` has no alarm; iPhone notifies at its "Today Notification" time.
- `add` refuses a title that already exists in the list (`--force` to add anyway).
- Other commands: `undone`, `delete`, `lists add <name>`.
- JSON output changed in this version: `due` is ISO 8601 (all-day: `YYYY-MM-DD`), `lists --json` returns objects, `move` and `--next` became `edit --list` and `--on mon`.

## Config

Optional. `~/.config/remind/config.json` (or `$XDG_CONFIG_HOME/remind/config.json`):

```json
{
  "aliases": { "w": "Work" },
  "defaultTime": "09:00",
  "listDefaultTimes": { "Work": "10:00" }
}
```

- `aliases`: short names for `--list`.
- `defaultTime`: time used when only a date is given.
- `listDefaultTimes`: per-list `defaultTime`, keyed by list name or alias.

## Use with an agent

Install the skill (Claude Code, Codex, Cursor, and other agents that support skills):

```bash
npx skills add 3000-2/remind
```

Let the agent read freely and ask before anything else:
- Claude Code: allow `Bash(remind list:*)`, `Bash(remind lists:*)` and `Bash(remind help)`.
- Codex: allow the prefixes `remind list`, `remind lists`, `remind help`.

Reminders on shared lists can be written by other people. The skill tells the agent to treat their text as data, not instructions.
