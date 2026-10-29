[English](README.md) · [한국어](README.ko.md)

# remind

macOS 미리 알림을 EventKit 으로 다루는 CLI. 반복 일정·여러 알림·URL 처럼 AppleScript 로 안 되는 것까지 쓴다.

## 설치

macOS 14 이상과 Xcode Command Line Tools(`xcode-select --install`)가 필요하다.

```bash
git clone https://github.com/3000-2/remind && cd remind
make install   # ~/.local/bin 에 설치
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc && exec zsh   # PATH 에 없으면
remind lists   # 처음 실행하면 미리 알림 접근 권한을 묻는다
```

권한은 `remind` 를 실행한 앱(터미널, iTerm, 에디터)에 주어진다. 시스템 설정 > 개인정보 보호 및 보안 > 미리 알림에서 바꾼다.

## 사용법

```bash
remind add "제목" --list 업무 --on 2026-11-16 --at 10:00 --every mon --alert-before 1d --note 메모 --url https://...
remind list [--list 업무] [--done] [--json]
remind lists
remind done <id>...
remind delete <id>...
remind move <id> --list 개인
remind help
```

- 목록을 안 주면 기본 목록.
- 날짜만 주면 09:00 (설정 참고). 시각만 주면 오늘(지났으면 내일).
- 같은 목록에 같은 제목의 미완료 항목이 있으면 거부한다(`--force` 로 무시).
- 섹션·그룹·태그·하위 항목·깃발은 EventKit 이 지원하지 않는다.

## 설정

선택 사항. `~/.config/remind/config.json` (또는 `$XDG_CONFIG_HOME/remind/config.json`):

```json
{
  "aliases": { "개인": "미리 알림", "w": "업무" },
  "defaultTime": "09:00",
  "listDefaultTimes": { "업무": "10:00" }
}
```

- `aliases`: `--list` 에 쓸 별칭.
- `defaultTime`: 날짜만 줬을 때 쓸 시각.
- `listDefaultTimes`: 목록별 `defaultTime`. 키는 목록 이름이나 별칭.

## 에이전트와 쓰기

스킬을 설치한다. Claude Code·Codex·Cursor 등 스킬을 지원하는 에이전트에서 동작한다:

```bash
npx skills add 3000-2/remind
```

또는 `AGENTS.md` / `CLAUDE.md` 에 아래를 넣는다:

```markdown
## 미리 알림

macOS 미리 알림(아이폰 동기화)은 `remind` CLI 로 다룬다. 전체 옵션은 `remind help`.
- 목록 이름은 `remind lists`, 조회는 `remind list --json`.
- 등록은 `remind add "제목" --list <이름> --on YYYY-MM-DD --at HH:MM`.
- `done` / `delete` / `move` 는 사용자가 말할 때만.
```

아니면 에이전트에게 "remind CLI 써 (`remind help`)" 라고만 해도 된다.
