[English](README.md) · [한국어](README.ko.md)

# remind

macOS 미리 알림을 EventKit 으로 다루는 CLI. 반복 일정·여러 알림·URL 처럼 AppleScript 로 안 되는 것까지 쓴다.

```bash
make install   # ~/.local/bin/remind
remind add "제목" --list 업무 --on 2026-11-12 --at 10:00 --every mon --alert-before 1d --note 메모 --url https://...
remind list [--list 업무] [--done] [--json]
remind lists
remind done <id>... · remind delete <id>... · remind move <id> --list 개인
```

- 목록을 안 주면 기본 목록.
- 별칭: `개인`/`personal` → 「미리 알림」, `work` → `업무`.
- 날짜만 주면 `업무` 목록은 10:00, 그 외 09:00. 시각만 주면 오늘(지났으면 내일).
- 같은 목록에 같은 제목의 미완료 항목이 있으면 거부한다(`--force` 로 무시).
- 처음 실행할 때 터미널 앱에 미리 알림 전체 접근 권한이 필요하다.
- 섹션·그룹·태그·하위 항목·깃발은 EventKit 이 지원하지 않는다.
