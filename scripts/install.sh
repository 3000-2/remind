#!/bin/sh
set -eu

cd "$(dirname "$0")/.."
action=${1:-install}
bin_dir=${2:-}
bin_dir=${bin_dir%/}
source_file="skills/remind/SKILL.md"
marker="github.com/3000-2/remind"

case $action in
  install | uninstall) ;;
  *) echo "usage: scripts/install.sh install|uninstall [bin dir]" >&2; exit 2 ;;
esac
[ -n "${HOME:-}" ] || { echo "HOME is not set" >&2; exit 1; }
[ -f "$source_file" ] || { echo "missing $source_file" >&2; exit 1; }

lock="${XDG_STATE_HOME:-}"
if [ -n "$lock" ]; then lock="$lock/skills/.skill-lock.json"; else lock="$HOME/.agents/.skill-lock.json"; fi

skip_reason() {
  if [ -L "$1" ] || { [ -f "$lock" ] && grep -q '"remind": *{' "$lock"; }; then
    if [ "$action" = install ]; then echo "managed by npx skills; run: npx skills update"; else
      echo "managed by npx skills; run: npx skills remove remind -g"
    fi
  elif [ -f "$1/SKILL.md" ] && ! grep -q "$marker" "$1/SKILL.md"; then
    echo "another skill named remind"
  fi
}

set -- "$HOME/.agents/skills/remind"
if [ -d "$HOME/.claude" ]; then set -- "$@" "$HOME/.claude/skills/remind"; fi

status=0
for target do
  reason=$(skip_reason "$target")
  if [ -n "$reason" ]; then
    echo "skipped $target ($reason)"
  elif [ "$action" = uninstall ]; then
    if [ -f "$target/SKILL.md" ]; then
      if rm "$target/SKILL.md"; then
        rmdir "$target" 2>/dev/null || true
        echo "removed $target"
      else
        status=1
      fi
    fi
  else
    result=installed
    if [ -f "$target/SKILL.md" ]; then result=updated; fi
    if mkdir -p "$target" && cp "$source_file" "$target/SKILL.md"; then echo "$result $target"; else status=1; fi
  fi
done

if [ "$action" = install ] && [ -n "$bin_dir" ]; then
  case ":$PATH:" in
    *":$bin_dir:"*) ;;
    *) echo "note: $bin_dir is not on PATH" ;;
  esac
fi
exit "$status"
