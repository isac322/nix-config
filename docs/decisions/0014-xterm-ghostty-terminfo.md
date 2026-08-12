# 0014. `xterm-ghostty` — 터미널 이름을 모르는 상대들

**결정** — Ghostty 의 셸 통합 기능 셋을 켜고, 우리 소유의 리눅스 서버는 terminfo
엔트리를 자기가 들고 있게 한다.

Ghostty 는 자신을 `xterm-ghostty` 로 소개한다. 그런데 그 이름의 terminfo 엔트리는
이 맥에서 **Ghostty.app 안에 한 곳**밖에 없고, 셸은 Ghostty 가 넣어준 `TERMINFO`
환경변수로만 그것을 찾는다. 그래서 환경을 비우는 쪽에서는 전부 깨진다.

- `sudo` 는 `env_reset` 으로 `TERMINFO` 를 지운다 → root 로 띄운 TUI 가 색을 잃는다
- `ssh` 는 `TERM` 만 넘기고 `TERMINFO` 는 안 넘긴다 → 반대편에서
  `Error opening terminal: xterm-ghostty`

애플의 `/usr/share/terminfo` 에도, nixpkgs 의 ncurses 6.6 에도 이 이름은 없다.
ncurses 가 담고 있는 것은 `ghostty` 라는 **다른 이름**이라 대신 응답하지 않는다.

해법은 두 층이다.

1. `shell-integration-features = sudo,ssh-terminfo,ssh-env` — Ghostty 가 제공하는
   기본 해법이고, 셋 다 기본값이 꺼짐이다(각각 명령을 셸 함수로 가리기 때문).
   이 값은 기본 집합을 **덮어쓰지 않고 병합**하므로 `cursor,title,path` 는 적지
   않아도 유지된다. `ssh-terminfo` 는 첫 접속 때 원격에 `tic` 으로 엔트리를 심고
   `ghostty +ssh-cache` 에 기억해 둔다.
2. NixOS 서버는 `environment.systemPackages = [ pkgs.ghostty.terminfo ]` 로 엔트리를
   **자기가 들고 있는다**. 1번은 어디까지나 `ssh` 를 가린 셸 함수라서 프롬프트에
   직접 친 `ssh` 만 거친다 — `git`, `scp`, `rsync -e ssh`, Makefile 안의 것들은
   바이너리를 직접 부르므로 해당이 없다. 우리 소유의 기계라면 접속 경로에
   의존하지 않는 쪽이 맞다. 2 kB 이고 cache.nixos.org 에 있다.

남의 기계라 둘 다 못 쓸 때는 한 줄로 밀어넣는다:

```
infocmp -x xterm-ghostty | ssh HOST -- tic -x -
```
