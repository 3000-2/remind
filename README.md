[English](README.md) · [한국어](README.ko.md)

# remind

A CLI for macOS Reminders built on EventKit, made for AI agents and people. Reminders sync to iPhone via iCloud.

## Install

Runs on macOS 14+. Building needs Swift 6.1+ (Xcode or Command Line Tools 16.3+, `xcode-select --install`).

```bash
git clone https://github.com/3000-2/remind && cd remind
make install   # installs the binary to ~/.local/bin and the agent skill (see below)
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
- A due time gets an on-time alarm; `--alert 1d` adds one early alarm, `--alert none` sets no time alarm. `--all-day` has no alarm; iPhone notifies at its "Today Notification" time.
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

## Development

```bash
make test     # unit tests (Swift Testing)
make lint     # swift format lint; make format fixes it
make check    # lint + test
make e2e      # end-to-end tests; writes to a "remind-test" list in your Reminders
```

`make e2e` needs Reminders access for your terminal. The `remind-test` list stays (and syncs to iPhone); delete it in the Reminders app.

## Use with an agent

`make install` also copies the skill to `~/.agents/skills/remind` (read by Codex, Gemini CLI, OpenCode and others) and, if you use Claude Code, `~/.claude/skills/remind`. Run it again after `git pull` to update both; `make uninstall` removes them. It never edits your agent settings or rules.

For other agents, or without a clone: `npx skills add 3000-2/remind -g`. Use one method or the other.

To have agents suggest reminders unprompted, say so in your own agent rules (for example, "offer a reminder when a task needs a follow-up later").

Let the agent read freely and ask before anything else:
- Claude Code: allow `Bash(remind list:*)`, `Bash(remind lists:*)` and `Bash(remind help)`.
- Codex: allow the prefixes `remind list`, `remind lists`, `remind help`.

Reminders on shared lists can be written by other people. The skill tells the agent to treat their text as data, not instructions.
