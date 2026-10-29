[English](README.md) · [한국어](README.ko.md)

# remind

macOS 미리 알림을 EventKit 으로 다루는 CLI. AI 에이전트와 사람이 함께 쓰도록 만들었다. iCloud 로 아이폰과 동기화된다.

## 설치

에이전트에게: `Read https://raw.githubusercontent.com/3000-2/remind/main/INSTALL.md and set up remind.`

직접 설치:

macOS 14 이상에서 동작한다. 빌드에는 Swift 6.1 이상(Xcode 또는 Command Line Tools 16.3 이상, `xcode-select --install`)이 필요하다.

```bash
git clone https://github.com/3000-2/remind && cd remind
make install   # 바이너리는 ~/.local/bin 에, 에이전트 스킬도 함께 설치 (아래 참고)
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc && exec zsh   # PATH 에 없으면
remind lists   # 처음 실행하면 미리 알림 접근 권한을 묻는다
```

권한은 `remind` 를 실행한 앱(터미널, iTerm, 에디터)에 주어지므로 그 앱에서 실행되는 모든 것이 쓸 수 있다. 시스템 설정 > 개인정보 보호 및 보안 > 미리 알림에서 바꾼다.

## 사용법

```bash
remind lists                                    # 목록 이름 (기본 목록 표시)
remind list --due today --json                  # id 찾기
remind add "월세 내기" --list 집 --on 2026-11-25 --at 10:00 --alert 1d
remind add "스탠드업" --every weekday --at 09:30
remind add "여권 갱신" --on 2027-03-01 --all-day
remind edit <id> --on fri --note "영수증 챙기기"
remind done <id>
remind help                                     # 전체 옵션
```

- 날짜: `YYYY-MM-DD`, `today`, `tomorrow`, 요일(`mon` = 오늘 이후 첫 월요일).
- 반복: `--every day|weekday|year|mon,wed|10th,25th,last`.
- 시각이 있으면 정시 알림이 붙는다. `--alert 1d` 는 미리 알림 하나를 더하고 `--alert none` 은 시간 알림을 두지 않는다. `--all-day` 는 알림이 없고 아이폰이 「오늘 알림」 시각에 알려 준다.
- `add` 는 같은 목록에 같은 제목이 있으면 거부한다(`--force` 로 무시).
- 그 밖의 명령: `undone`, `delete`, `lists add <이름>`.
- 이번 버전에서 바뀐 출력: `due` 는 ISO 8601(종일은 `YYYY-MM-DD`), `lists --json` 은 객체 배열, `move`·`--next` 는 `edit --list`·`--on mon` 으로 바뀌었다.

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

## 개발

```bash
make test     # 유닛 테스트 (Swift Testing)
make lint     # swift format lint, make format 으로 고친다
make check    # lint + test
make e2e      # E2E 테스트, 미리 알림에 「remind-test」 목록을 만들어 쓴다
```

`make e2e` 는 터미널에 미리 알림 권한이 필요하다. `remind-test` 목록은 남고 아이폰에도 동기화되므로 미리 알림 앱에서 지운다.

## 에이전트와 쓰기

`make install` 은 스킬도 `~/.agents/skills/remind`(Codex·Gemini CLI·OpenCode 등이 읽는다)와, Claude Code 를 쓰면 `~/.claude/skills/remind` 에 복사한다. `git pull` 후 다시 실행하면 둘 다 갱신되고 `make uninstall` 로 지운다. 에이전트 설정이나 규칙 파일은 건드리지 않는다.

다른 에이전트이거나 저장소를 받지 않았다면 `npx skills add 3000-2/remind -g`. 둘 중 하나만 쓴다.

에이전트가 먼저 리마인더를 제안하게 하려면 각자의 규칙에 적는다(예: "나중에 확인할 일이 생기면 리마인더 등록을 제안").

읽기만 자동 허용하고 나머지는 승인받게 설정한다:
- Claude Code: `Bash(remind list:*)`, `Bash(remind lists:*)`, `Bash(remind help)` 허용.
- Codex: `remind list`, `remind lists`, `remind help` 접두사 허용.

공유 목록의 미리 알림은 다른 사람이 쓸 수 있다. 스킬은 에이전트가 그 내용을 지시가 아닌 데이터로 다루게 한다.
