# Install remind

Run these on the user's Mac. Ask before changing anything not listed here.

1. Check `sw_vers -productVersion` is 14+ and `swift --version` is 6.1+. If not, ask the user to install or update the Command Line Tools (`xcode-select --install`, or Software Update), then stop.
2. Clone `https://github.com/3000-2/remind` to `~/remind`, or run `git pull --ff-only` there if it exists. Run `make install` in it. It writes `~/.local/bin/remind` and the agent skill (`~/.agents/skills/remind`, plus `~/.claude/skills/remind` if `~/.claude` exists).
3. Tell the user a macOS dialog will ask for Reminders access, and that it applies to everything run from this app. Then run `~/.local/bin/remind lists`. On "No access to Reminders", or if your sandbox blocks it, ask the user to allow this app in System Settings > Privacy & Security > Reminders (or run the command in their terminal), then retry.
4. If `command -v remind` is not `~/.local/bin/remind`, offer to put `~/.local/bin` first on PATH in their shell profile.
5. Report the result, including any "skipped" lines from `make install`.
