# 레퍼런스

무엇이 어디에 있고 무엇이 설치되는가. 왜 그런지는 [결정 기록](decisions/)에 있다.

## 구조

```
flake.nix          기기 목록. 각 기기가 어떤 모듈을 조합할지만 정한다
lib/               플랫폼별 옵션 경로가 달라서 모듈이 아닌 순수 데이터로 둔 것
  caches.nix         substituter 와 공개키
  ssh-audit.nix      sshd 알고리즘 프로파일. 맥은 파일로, NixOS 는 settings 로
modules/           시스템 레벨
  common.nix         모든 OS 공통
  darwin.nix         모든 macOS
  nixos.nix          모든 NixOS
  orca.nix           `local.*` 옵션 선언. 광고 주소는 터널에서 읽는다
  camofox.nix        서버 맥의 VNC secret + WireGuard-only HTTPS noVNC 브리지
  wireguard.nix      서버 맥의 터널. 앱이 아니라 wg-quick 을 도는 루트 데몬
  auto-login.nix     kcpassword 생성 + FileVault 끄기. Aqua 서비스 때문에 있다
  mas-apps.nix       App Store 전용 앱이 없을 때 switch 가 알리게 한다
  roles/
    darwin-laptop.nix   랩탑 macOS
    darwin-server.nix   서버 macOS
hosts/             기기 고유
  bhyoo-macbook-air/
  bhyoo-macbook-pro/
  server/            + hardware-configuration.nix
home/              사용자 레벨 (home-manager)
  common.nix         모든 기기 공통 — 설정의 대부분이 여기 있다
  darwin.nix         모든 macOS
  linux.nix          NixOS 전용
  roles/
    darwin-laptop.nix   데스크톱 앱
    darwin-server.nix   Rust · 언어 서버
pkgs/              nixpkgs 에 없거나 쓸 수 없는 형태인 패키지 + overlay.nix
  pinentry-keychain/  키체인을 읽는 pinentry. 콘솔 없는 맥용
  camoufox/          고정한 macOS arm64 브라우저 코어
  camofox-browser/   @askjo/camofox-browser API 서버
.claude/skills/    이 레포에 대해 되풀이하는 절차
  ssh-audit/         sshd 권장값이 움직였는지 다시 대조한다
```

축이 셋(OS × 역할 × 기기)인데 상속이 아니라 **조합**으로 푼다
([0002](decisions/0002-compose-not-inherit.md)). 모든 설정은
`common + platform + role + host` 이고, 조합 지점은 `flake.nix` 한 곳뿐이다.

```nix
"bhyoo-macbook-air" = mkDarwin { hostname = "bhyoo-macbook-air"; role = "laptop"; };
"bhyoo-macbook-pro" = mkDarwin { hostname = "bhyoo-macbook-pro"; role = "server"; };
```

## 무엇이 어느 층에 속하나

**모든 macOS** (`modules/darwin.nix`와 그것이 import하는 파일들) — 맥이라면
무조건 같아야 하는 것. 키 리매핑과 단축키 전부(`keyboard.nix`), Finder 전부
(`finder.nix`), Liquid Glass·Spotlight(`appearance.nix`), WARP(`warp.nix`),
Dock, 트랙패드, 키 반복, 데스크탑 비우기, Determinate·캐시, Homebrew 기반과
그 위의 Orca, 그리고 [sshd 가 쓸 알고리즘과 호스트
키](decisions/0027-ssh-audit-profile-shared-by-every-host.md).

마지막 것이 역할이 아닌 이유는 아래 표의 sshd 줄과 갈리는 지점이기도 하다.
누가 들어올 수 있는지는 역할이 정하고, 들어올 때 무엇으로 말하는지는 맥이면 답이
같다. 랩탑에서 원격 로그인을 손으로 켰을 때 그 기계만 약한 편이 훨씬 나쁘다.

**역할 전용** — 역할 파일은 의도적으로 얇다. 맥은 어느 역할이든 같은 맥이라
겉모습 설정은 위층에 있고, 여기에는 진짜로 갈리는 것만 둔다.

| | 랩탑 | 서버 |
|---|---|---|
| 데스크톱 앱 (Firefox + cask 14개 + MAS 2개) | ✅ | ✖ |
| `nixpkgs-firefox-darwin` 오버레이 | ✅ | ✖ |
| Touch ID 로 sudo (`pam_tid`) | ✅ | ✖ |
| [sshd — 키 전용, root 금지](decisions/0026-sshd-on-the-server-mac.md) | ✖ | ✅ |
| [전원 연결 중엔 뚜껑을 닫아도 안 잠](decisions/0006-clamshell-only-while-on-power.md) · 전원별 유휴 타이머 | ✖ | ✅ |
| Rust · 언어 서버 | ✖ | ✅ |
| [Orca 런타임을 계속 띄우는 LaunchAgent](decisions/0028-orca-runtime-on-the-server-mac.md) · 자동 로그인 | ✖ | ✅ |
| [GPG pinentry](decisions/0030-gpg-passphrase-without-a-console.md) | pinentry-mac | 키체인 + tty |
| [WireGuard — 앱(랩탑) 대 루트 데몬(서버)](decisions/0029-wireguard-as-a-daemon-on-the-server-mac.md) | 앱 | 데몬 |
| [Camofox API · DeskPad/macVNC + noVNC](decisions/0031-camofox-native-macos-over-wireguard.md) | ✖ | ✅ |

두 맥 다 MacBook Pro 급 하드웨어이고 Touch ID 센서도 둘 다 달려 있다. 랩탑에만
있는 이유는 하드웨어가 아니라 역할이다 — 서버 맥은 뚜껑을 닫은 채 SSH 로만
들어가므로 `pam_tid` 가 프롬프트를 띄울 화면이 없다.

**기기 전용** (`hosts/<name>/`) — 정말 그 기계에만 해당하는 것. 지금은
`hostPlatform`과 서버의 `hardware-configuration.nix`뿐이다.

세 층 어디에도 안 맞는 것은 `extraModules` / `extraHomeModules`로 넘긴다 —
한 기계가 미디어 서버를 겸하는 식의 경우.

## OMP MCP registry (모든 호스트)

`home/common.nix`가 `~/.omp/agent/mcp.json` 전체를 Home Manager symlink로 만든다.
기본 registry에는 local stdio server인 `context-mode`와 Linear의 공식 remote MCP
server가 들어간다. 서버 역할에서 `local.camofox.enable`이 켜진 경우에만
session-aware `camofox` stdio bridge가 같은 registry에 추가된다.

| 이름 | transport | endpoint / command | 인증 |
|---|---|---|---|
| `context-mode` | stdio | Nix로 고정한 plugin bundle | 없음 |
| `linear` | streamable HTTP | `https://mcp.linear.app/mcp` | OAuth 2.1 |
| `camofox` | stdio | `camofox-browser-mcp-session omp` | loopback API |

Linear 항목에는 token을 넣지 않는다. OMP가 endpoint의 OAuth metadata를 발견하고,
승인 뒤 credential을 endpoint URL 기준의 auth storage에 별도로 저장한다. 따라서
Home Manager switch는 MCP server 정의만 갱신하고 로그인 상태를 지우거나 Nix
store에 비밀을 복사하지 않는다. 최초 인증과 검증 절차는
[운영](operations.md#linear-mcp-모든-호스트)에 있다.

## Camofox 원격 브라우저 (서버 맥)

`local.camofox.enable`이 Camofox API, DeskPad virtual display, macVNC, HTTPS
noVNC를 한 묶음으로 켠다
([0031](decisions/0031-camofox-native-macos-over-wireguard.md)). Camofox,
DeskPad 1.3.2, `LibVNC/macVNC`는 자동 로그인으로 생긴 `bhyoo`의 Aqua 세션에서
한 LaunchAgent가 감독하고, noVNC는 root LaunchDaemon이다. displayplacer 1.4.0이
DeskPad 화면을 1920×1080 main display로 정한 뒤 macVNC가 ScreenCaptureKit과
LibVNCServer로 내보낸다. Camofox의 Linux/Xvfb 플러그인과 macOS Screen Sharing은
최종 noVNC data path에 쓰지 않는다.

첫 open-source VNC 전환에서는 `retireScreenSharing = false`로 native Screen
Sharing job을 독립된 migration console로 남긴다. macVNC에 Screen Recording과
Accessibility 권한을 주고 noVNC 화면과 입력을 검증한 뒤 이 값을 `true`로 바꾼
다음 switch가 그 job을 disable·stop한다. legacy VNC 인증은 첫 switch에서 바로
꺼진다.

`userId`는 macOS 계정이 아니라 Camofox의 로그인 상태 identity다. 이 구성은
`CAMOFOX_USER_ID=omp`를 OMP, Claude Code, Codex가 함께 써서 쿠키와 웹 스토리지를
공유한다. 그 안의 `sessionKey`는 `camofox-browser-mcp-session` wrapper가 클라이언트
세션별로 정하며, 탭 목록과 조작 권한을 서로 다른 namespace로 가른다. OMP는 transcript
UUID, Claude Code는 `CLAUDE_CODE_SESSION_ID`를 쓰고, 세션 ID를 MCP 자식에게 주지
않는 클라이언트는 adapter 프로세스별 임시 UUID로 격리한다.
상류 1.13.1의 `sessionKey`는 생성 group만 정하고 list와 기존 탭 조작은 제한하지
않는다. 이 패키지는 MCP의 모든 탭 요청에 key를 전달하고 서버의 lookup과 list를
그 group으로 제한한다. wrapper의 UUID만으로 격리된 척하지 않는다.

각 `userId`의 BrowserContext는 쿠키와 웹 스토리지를 나누지만 Camoufox 프로세스와
Camofox 전용 가상 디스플레이는 공유한다. noVNC는 그 디스플레이 전체를 내보내며,
화면·포커스·키보드·마우스·클립보드도 공유한다. 따라서 noVNC는 신뢰된 운영자용
공용 관리 콘솔이지 사용자별 격리 경계가 아니다.

| 용도 | 주소 | 주체 |
|---|---|---|
| Camofox API listener | `127.0.0.1:9377` | `@askjo/camofox-browser` |
| OMP/Claude/Codex control bridge | session-aware stdio → `127.0.0.1:9377` | `camofox-browser-mcp-session` → `camofox-browser-mcp` |
| noVNC listener | `<WireGuard 주소>:6080` | nixpkgs `novnc`의 웹 frontend와 WebSocket proxy |
| noVNC의 VNC backend target | `127.0.0.1:5901` | `LibVNC/macVNC`의 LibVNCServer |

Camofox API와 macVNC는 loopback 전용이다. 각 MCP adapter는 기존 Camofox daemon으로
전달할 뿐 두 번째 브라우저를 실행하지 않는다. noVNC만
`/var/run/wireguard-addresses`의 첫 줄에 bind하며, 파일이나 주소가 아직 없으면
fallback 주소를 열지 않고 실패한다.

`/var/lib/nix-darwin/camofox-vnc-password`는 activation이 처음 한 번 만든 정확히
8자의 영숫자이고 `root:wheel 0600`이다. activation은 이를 표준 LibVNCServer
password-file 형식으로 변환해 `/var/lib/camofox/vnc-auth`에
`bhyoo:staff 0400`으로 원자적으로 교체한다. **noVNC가 아니라 loopback macVNC가 이
자격증명을 검사한다.** 짧은 VNCAuth 비밀번호를 허용하는 대신 backend를 loopback에
가두고 frontend는 WireGuard 주소 하나에만 연다. 조회와 검증 절차는
[운영](operations.md#camofox--novnc-서버-맥)에 있다.

## GUI 앱

nixpkgs 가 아니라 Homebrew 에서 온다
([0015](decisions/0015-gui-apps-come-from-homebrew.md)). `onActivation.upgrade` 가
켜져 있어 최신 유지도 Homebrew가 한다. 예외 셋:

- **Orca** (Stably) — homebrew-cask가 아니라 자체 tap에 있어서 `homebrew.taps`에
  `stablyai/orca`를 같이 선언한다. nix-homebrew가 tap을 기본적으로 mutable로
  두기 때문에 tap을 flake 인풋으로 고정하지 않고도 동작한다. tap 접두사는
  선택이 아니다 — homebrew-cask의 맨 `orca`는 plotly의 차트 렌더러로,
  Gatekeeper를 통과하지 못해 deprecated 된 무관한 패키지다.

  **여기서 유일하게 두 맥 모두에 깔리는 cask**라 `modules/darwin.nix`에 있다.
  Orca는 코딩 에이전트를 각자의 git worktree에서 병렬로 굴리는 도구이고,
  번들에 같이 들어오는 `orca` CLI가 헤드리스 기계에서 쓸모 있는 쪽이다.
  랩탑에만 있는 것은 Dock 타일뿐이다.
- **서버 맥의 Camoufox · DeskPad · macVNC** — Nix가 고정한 macOS 앱이다.
  Camoufox는 Camofox LaunchAgent가 store 안 실행 파일을 직접 가리키고, DeskPad와
  macVNC는 같은 LaunchAgent가 실행하면서 Home Manager Apps에도 노출해 privacy
  권한 대상을 안정된 경로로 제공한다
  ([0031](decisions/0031-camofox-native-macos-over-wireguard.md)).
- **KakaoTalk · WireGuard** — Mac App Store 전용이라 손으로 깐다
  ([0016](decisions/0016-mas-only-apps-installed-by-hand.md)). 둘 다 랩탑 전용이
  됐다: 서버 맥은 WireGuard 앱 대신 `wireguard-tools` 를 루트 데몬으로 돌린다
  ([0029](decisions/0029-wireguard-as-a-daemon-on-the-server-mac.md)). 선언한
  기계에 앱이 없으면 switch 가 매번 알린다 — `local.masApps`,
  `modules/mas-apps.nix`.

**1Password 는 나눠 담는다.** `op` CLI는 **모든 맥**에 (`home/darwin.nix`),
데스크톱 앱은 **랩탑에만** (`modules/roles/darwin-laptop.nix`). `op`는 시스템
통합이 없는 단일 바이너리라 nixpkgs에서 와도 되고, 그래서 `flake.lock`에
고정된다. 데스크톱 앱은 그렇지 않다 — nixpkgs의 darwin 분기는 dmg에서 `.app`만
복사하는데, 1Password 앱은 브라우저 연동과 SSH 에이전트 같은 시스템 통합에
의존하므로 cask로 설치한다.

**헤드리스 서버는 CLI만으로 충분하다.** 데스크톱 앱 없이도 서비스 계정 토큰
(`OP_SERVICE_ACCOUNT_TOKEN`, CLI 2.18.0+)으로 비대화형 인증이 되고, 이것이
1Password가 헤드리스 환경에 문서화해 둔 방식이다. 다만 **SSH 에이전트 기능은
데스크톱 앱을 요구**하므로, 서버에서 1Password의 SSH 에이전트를 쓰려면 그때는
`modules/roles/darwin-server.nix`에 cask를 추가해야 한다 — 그러면 GUI 세션이
필요해진다.

## 코딩 에이전트 — 작업이 있는 곳에서 돈다

`claude-code`, `codex`, `omp` 셋을 **모든 기기**에 둔다 (`home/common.nix`).
아래 두 CLI 묶음이 이 층에 있는 이유가 이것이라, 순서상 여기가 먼저다.

셋 다 nixpkgs 가 아니라 `llm-agents` 인풋에서 온다. nixpkgs-unstable 채널이
master 를 며칠씩 뒤따라오는 반면 이쪽은 매일 상류를 따라가고, aarch64-darwin 과
x86_64-linux·aarch64-linux 를 모두 빌드해서 리눅스 서버에서도 같은 줄이 통한다.

**Orca 는 여기 없다.** GUI 앱이라 cask 로 오고, 그래서 맥 둘에만 있다 —
위 [GUI 앱](#gui-앱) 을 보라.

### BearDrive — 실행 파일은 공통, 동기화 대상은 노드별

`bdrive` 0.15.0을 **모든 기기**에 둔다. nixpkgs에는 아직 없으므로
`pkgs/beardrive/package.nix`가 상류의 동일한 공식 release binary를 고정 hash로
가져오고, `pkgs/overlay.nix`가 `pkgs.beardrive`로 노출한다.

Nix가 하는 일은 CLI 설치까지다. `bdrive init`은 동기화할 로컬 directory와 hub
project를 고르고 로그인한 뒤 agent hook과 로그인 시 재개할 사용자 service를
등록하는 mutable onboarding이라, 모든 노드에 임의의 folder를 추측해서 실행하지
않는다. 실제 project를 연결할 때 각 노드에서 대상 directory를 정한 뒤 한 번씩
`bdrive init`을 실행한다.

### Agent Skills — 검토한 공개 소스는 Nix가 고정

`home/agent-skills.nix`는 검토한 공개 skill repository를 `flake = false` input으로
받고 `flake.lock`의 revision을 모든 노드에 동일하게 배포한다. switch 때 선택한
skill directory를 `skills add --global --agent amp --copy`와 같은 형태로
`~/.agents/skills/<name>`에 복사하므로, 하네스가 보는 파일 배치는 수동 설치와 같다.
업데이트와 rollback은 시스템 generation을 따른다.

이 이름들은 SkillClaw가 공유 backend로 push하지만 pull에서는 보호한다. 그래서
cloud의 이전 복사본이 방금 switch한 Nix revision을 덮지 못한다. mutable하게 생성한
나머지 스킬만 일반적인 pull-then-push 및 evolve 대상이다. 목록과 업데이트 절차는
[운영](operations.md#nix-고정-agent-skills-모든-노드)에 있다.


### SkillClaw — 로컬 클라이언트 셋, 공유 백엔드는 하나

`home/skillclaw.nix`가 `skillclaw` 0.4.0을 flake input의 고정한 소스에서 Python
application으로 빌드해 모든 노드에 둔다. 각 노드는 loopback proxy와 5분 주기
`skills sync`를 가지며, 동기화 대상은 하네스별 사본이 아니라 공통 Agent Skills
위치 `~/.agents/skills`다. Claude Code 전용 skill 위치는 대상에서 제외한다.

공유 저장소는 사용자가 이미 운영하는 외부 S3-compatible backend다. 이 repository는
object-store daemon을 설치하지 않는다. 모든 client와 서버 맥의 단일 evolve worker가
하나의 동일한 bucket과 `omp` group을 사용한다.

endpoint, bucket, region과 S3 자격증명은
`~/.config/skillclaw/shared.env`에, LLM 자격증명은 `llm.env`에 두며 둘 다 Nix store
밖에 남는다. evolve worker는 `home/roles/darwin-server.nix`에서 서버 맥에만
활성화한다. 파일 생성과 확인 절차는
[운영](operations.md#skillclaw-공유-스킬-모든-노드)에 있다.


## 관측 CLI — 에이전트가 직접 조회하게

`tempo-cli`, `promtool`, `sentry`, `posthog-cli`, `axiom`, `langfuse` 여섯을
**모든 기기**에 둔다 (`home/common.nix`). 코딩 에이전트가 대시보드 스크린샷을 받는
대신 텔레메트리를 직접 질의하라고 두는 것이라, `claude-code` 와 같은 층에 있다 —
에이전트는 작업이 있는 곳에서 돈다.

`promtool`과 `tempo-cli`는 nixpkgs package의 다른 output 또는 잘라낸 변형이고,
나머지 넷은 `pkgs/`에서 직접 패키징한다.

- **`promtool` 은 `pkgs.prometheus` 에 없다.** 상류가 `moveToOutput bin/promtool
  $cli` 로 별도 출력에 옮겨 두어서, `pkgs.prometheus` 를 설치하면 서버와 `migrate`
  만 들어오고 정작 원한 도구는 안 들어온다. `pkgs.prometheus.cli` 로 집는다.
- **`tempo-cli` 는 잘라서 쓴다.** nixpkgs 의 `tempo` 는 `subPackages` 로 명령
  넷을 모두 빌드하는데 셋은 여기서 돌리지 않는 트레이스 저장소의 서버 쪽이다.
  `cmd/tempo-cli` 만 남기면 클로저가 237 MiB 에서 72 MiB 로 줄고, 서버로 읽히는
  `tempo` 라는 이름의 바이너리가 PATH 에서 빠진다 (`pkgs/overlay.nix`).
- **`sentry` 는 `getsentry/cli`다.** `pkgs/sentry/package.nix`가 공식 release의
  npm bundle을 고정하고 `sentry` 바이너리를 설치한다.
- **`axiom` 은 `axiom-cli` 가 아니다.** 바이너리 이름이 `axiom` 이다. attribute 는
  여기 있는 다른 CLI 옆에서 찾을 수 있게 `axiom-cli` 로 두었다.

`langfuse` 는 nixpkgs 에 없어서 직접 담았다. nixpkgs 의 `langfuse` attribute 는
파이썬 SDK 이고 그 안에는 실행 파일이 없다 — 아래 [`pkgs/`](#pkgs) 를 보라.

## 서비스 CLI — 읽는 것에서 하는 것으로

`wrangler`, `stripe`, `gws`는 모든 노드의 같은 자리에 둔다(`home/common.nix`).
관측 CLI가 "무슨 일이 있었는지"를 읽는 쪽이라면 이쪽은 에이전트가 실제로
**손을 대는** 쪽이다 — Worker를 배포하고, 결제 이벤트를 찾고, 캘린더를 읽는다.
`agent-browser`는 `local.camofox.enable = false`인 노드에만 추가한다. 서버 맥은
공유 Camofox daemon과 session boundary를 우회하는 별도 Chrome/Chromium 프로세스가
생기지 않도록 이를 설치하지 않고 Camofox MCP만 쓴다.

이름이 다른 둘과 조건부 브라우저 CLI에는 다음 주의가 필요하다.

- **`gws`가 구글 워크스페이스 CLI다.** 상류 이름은 `@googleworkspace/cli`인데
  설치되는 바이너리는 `gws`이고, nixpkgs의 attribute도 `gws`다.
  `google-workspace-cli` 같은 attribute는 없다. 구글 저장소에 있지만
  "officially supported Google product가 아니다"라고 스스로 명시한다.
- **`stripe-cli`가 설치하는 바이너리는 `stripe`다.**
- **`agent-browser`는 테스트 러너가 아니다.** Vercel이 에이전트가 몰도록 만든
  헤드리스 브라우저 CLI지만, 이 구성에서는 Camofox가 없는 노드에서만 설치한다.
- **`wrangler` 는 클로저가 774 MiB 다.** 상류가 `workerd` 와 여러 플랫폼용
  `esbuild` 를 함께 담기 때문이고, 잘라낼 `subPackages` 같은 손잡이가 없다.
  `cache.nixos.org` 에서 그대로 받아오니 빌드 시간은 들지 않는다.

## 개발 도구 — 맥에만 있다

위의 두 CLI 묶음은 **모든 기기**에 있지만, 컴파일러와 개발 도구는 맥에만 둔다
(`home/darwin.nix`). 리눅스 서버는 서비스를 돌리는 기계라 컴파일할 것이 없다.

**언어 툴체인** — `go`, `nodejs_24` + `pnpm`, `bun`, `uv`. Rust 는 여기 없고
서버 맥에만 있다 (`home/roles/darwin-server.nix`) — 요청이 그 기계에 한정돼
있었다.

- **`go` 는 버전 없는 이름 그대로 쓴다.** nixpkgs 가 현재로 취급하는 것을 따라가는
  게 맞다고 봤다. **`nodejs_24` 는 반대로 버전을 박았다** — 오늘은 `nodejs` 와 같은
  파생이지만 nixpkgs 에 이미 25 와 26 이 있어서 기본값은 알아서 움직인다. 버전을
  적어 두면 그 이동이 이 줄을 고칠 때 일어난다.
- **pnpm 은 Corepack 에 맡기지 않고 패키지로 넣는다.** `corepack enable` 은 Node
  설치 디렉터리 안에 shim 을 쓰는데 여기서는 그게 읽기 전용 스토어 경로다. 게다가
  그 뒤로 받아오는 버전은 프로젝트의 `packageManager` 필드가 런타임에 정한다 —
  rustup 을 쓰지 않는 것과 정확히 같은 이유다. nixpkgs 패키지는 자기 `nodejs-slim`
  을 들고 오므로 위의 `nodejs_24` 를 가리지도, 의존하지도 않는다.
- **bun 은 이 목록에서 유일하게 nixpkgs 그대로가 아니다.** 필요한 버전이 1.3.14
  인데 nixpkgs 는 한 릴리스 뒤라 `pkgs/overlay.nix` 에서 덮어썼다. 노드를 대체하러
  온 게 아니라 옆에 선다 — 둘은 같은 `package.json` 을 읽고 서로를 대신하지 않는다.
- **uv 옆에 파이썬 인터프리터가 없는 건 빠뜨린 게 아니다.** uv 가
  `~/.local/share/uv` 밑에 자기 standalone CPython 을 받아 거기에 virtualenv 를
  만든다. 그건 의도적으로 nix 바깥이고 — 프로젝트마다 다르고 `pyproject.toml` 을
  따라 움직이니 시스템 클로저에 있을 것이 아니다 — 대신 이 설정이 놓지 않은
  바이너리가 생긴다는 뜻이기도 하다. 평범한 relocatable macOS 빌드라 NixOS 와
  달리 그냥 실행된다.

**린터 둘** — `golangci-lint`, `hadolint`. 둘 다 설정을 들고 오지 않는다.
프로젝트의 `.golangci.yml` 과 지목된 Dockerfile 을 읽을 뿐이라 이 레포에 넣을
것이 없다. 각각 하나가 아니라 묶음이라는 점이 같다 — golangci-lint 는 govet ·
staticcheck · errcheck 를 포함한 수십 개를 한 바이너리로 돌리고, hadolint 는 모든
`RUN` 본문을 ShellCheck 에 넘긴다 (그래서 결과가 `DL` 과 `SC` 두 접두사로 나온다).

**하나만 미리 알아둘 것: 핀 된 golangci-lint 는 2.x 다.** v1 형식의
`.golangci.yml` 은 무시되거나 부분 동작하는 게 아니라 실행 자체가 멈춘다 —
린트가 아니라 `unsupported version of the configuration` 이 나온다.
`golangci-lint migrate` 가 제자리에서 변환한다.

**쿠버네티스·클라우드** — `k9s`, `stern`, `kubernetes-helm`, `google-cloud-sdk`,
`terraform`. 셋은 이름이 함정이다.

- **`gcloud` 라는 attribute 는 없다.** `google-cloud-sdk` 의 mainProgram 이다.
  그냥 담으면 CLI 뿐인데, GKE 가 CLI 이상을 요구하는 유일한 항목이다 — 쿠버네티스가
  1.26 에서 in-tree GCP auth provider 를 뺐기 때문에 `gcloud container clusters
  get-credentials` 가 쓴 kubeconfig 는 외부 자격증명 플러그인을 지목한다.
  `gke-gcloud-auth-plugin` 이 PATH 에 없으면 kubectl 과 k9s 가 `no Auth Provider
  found` 로 죽는데, 이 메시지는 gcloud 도 플러그인도 언급하지 않는다. 구글의
  안내는 `gcloud components install` 이고 그건 패키지 자기 디렉터리에 쓰므로
  읽기 전용 스토어에서는 불가능하다. `withExtraComponents` 가 선언적인 형태이고,
  컴포넌트를 패키지 안에 빌드해 넣는다.
- **`helm` 은 전혀 다른 프로그램이다.** 0.9.0 짜리 GPL-3.0 도구로 쿠버네티스와
  무관하다. 차트 매니저는 `kubernetes-helm` 이고, 그런데 그것의 mainProgram 도
  `helm` 이라 잘못 담아도 조용히 설치되고 실행할 때만 이상해 보인다.
- **`stern` 은 k9s 의 빈자리다.** 정규식으로 여러 파드·컨테이너의 로그를 한꺼번에
  따라가는 쪽이라 k9s 가 어색한 딱 그 일을 한다. 둘 다 kubeconfig 를 스스로 읽으니
  여기에 클러스터 설정은 없다. 참고로 이 기계들의 `kubectl` 은
  `/usr/local/bin/kubectl` — nix 바깥에서 온 것이다. k9s 는 그걸 부르지 않지만,
  부르는 무언가는 핀 된 버전이 아니라 그쪽을 잡는다.

`terraform` 은 unfree 라 `modules/common.nix` 의 predicate 를 탄다.
`home-manager.useGlobalPkgs` 가 켜져 있어 시스템 패키지와 같은 규칙이 적용된다.

**플랫폼 CLI** — `gh`와 `slack-cli`는 `home/common.nix`에서 **모든 기기**에,
`vercel-cli`는 `home/darwin.nix`에서 맥에만 둔다. 셋 다 자기가 알아서 인증한다
(각각 키체인/`GH_TOKEN`, `slack login`, `vercel login`) 이라 계정에 관한 것은
이 레포에 없다. `gh`는 HTTPS 위의 REST API를 쓰므로 `git`이 push 하는 SSH
자격증명과 별개다. `slack-cli`와 `vercel-cli`는 nixpkgs에서 그대로 오지 않는다 —
아래 [`pkgs/`](#pkgs) 를 보라.

## 키보드와 트랙패드

모디파이어 회전은 `modules/keyboard.nix`에 hidutil로 들어 있다
([0008](decisions/0008-hidutil-not-karabiner.md)).

```
fn → left command → left option → left control → fn
right command → F18 → (단축키 60) 이전 입력 소스 선택 = 한/영
```

단축키는 `modules/keyboard.nix`가 activation 때 넣는다
([0009](decisions/0009-hangul-toggle-via-f18.md)).

| id | 기능 | 값 |
|----|------|-----|
| 60 | 이전 입력 소스 선택 (한/영) | F18 |
| 64 | Spotlight | ⌥Space |
| 79 / 80 | 이전 스페이스 / 느린 변형 | ⌘⌥← / ⌘⌥⇧← |
| 81 / 82 | 다음 스페이스 / 느린 변형 | ⌘⌥→ / ⌘⌥⇧→ |

id의 의미는 추측이 아니라 macOS 자신의 표에서 확인한 것이다 —
`KeyboardSettings.appex/Contents/Resources/ko.lproj/DefaultShortcutsTable.xml`이
79를 "Move to previous space", 81을 "Move to next space"로 적고 각각
`slow_sybmolichotkey`로 80, 82를 짝지어 둔다. 느린 변형은 같은 조합에 shift를 더한
것이라 한쪽만 바꾸면 짝이 어긋난다.

UserKeyMapping 값은 64비트다. 상위 32비트가 HID usage page, 하위가 usage다.
키보드/키패드는 page 0x07이고, **fn만 애플 벤더 top case page 0xFF에 있다**
(`0xFF00000003`).

**fn이 command가 되면서 F1–F12의 미디어 기능은 물리적 왼쪽 control로 옮겨간다.**
회전 후 그 키가 fn을 보내기 때문이다. `com.apple.keyboard.fnState = true`와 짝이다.

Caps Lock 은 Caps Lock 으로 두고 한/영은 오른쪽 command 가 맡는다
([0010](decisions/0010-caps-lock-stays-caps-lock.md)). Esc 아래 키의 ₩ 는
[0011](decisions/0011-won-sign-fixed-at-insertion.md) 에서 백틱이 된다.

스페이스는 만들어진 순서를 유지한다 (`dock.mru-spaces = false`). 기본값은 최근 사용
순으로 재배열하는 것인데, 방금 단축키로 이동한 스페이스가 그 아래에서 자리를 옮겨
버린다.

데스크탑에는 아무것도 두지 않는데, 이건 **주인이 둘**이다. 아이콘은 Finder가 그리고
위젯은 WindowManager가 그려서, 한쪽만 꺼서는 다른 쪽이 남는다.

- Finder: `CreateDesktop = false`가 파일을 포함해 모든 아이콘을 숨긴다.
  `Show*OnDesktop` 네 개는 어떤 볼륨을 보일지 정하는 것이라 아이콘을 다시 켜더라도
  비어 있도록 함께 꺼 둔다.
- WindowManager: `StandardHideWidgets`, `StandardHideDesktopIcons`. Stage Manager는
  같은 토글을 따로 들고 있어서 `StageManagerHideWidgets`, `HideDesktop`도 같이 끈다.

트랙패드는 `modules/darwin.nix`에서 세 손가락 끌기를 켜고, 충돌하는 세 손가락
스와이프 제스처를 네 손가락으로 옮긴다. nix-darwin이 `com.apple.AppleMultitouchTrackpad`와
`com.apple.driver.AppleBluetoothMultitouch.trackpad` 양쪽에 쓰므로 내장 트랙패드와
Magic Trackpad가 모두 적용된다.

`system.defaults` 의 plist 는 쓰기만 해서는 반영되지 않으므로 `modules/keyboard.nix`
가 activation 끝에 `activateSettings` 를 직접 부른다
([0012](decisions/0012-call-activate-settings-directly.md)).

## 터미널 Ghostty

랩탑의 터미널 ([0013](decisions/0013-ghostty-because-config-is-a-file.md)).
quake 스타일 드롭다운이 내장이고, 전역 단축키에는 **접근성 권한**이 필요하다 —
선언으로 없앨 수 없는 한 번의 GUI 단계다.

| 키 | 동작 |
|---|---|
| `F12` | 드롭다운 토글 (전역) |
| `⌘⌥T` | 일반 창 (전역). `new_window`는 포커스가 없으면 앱을 앞으로 가져오므로 "실행"도 겸한다 |
| `⌘⌥D` / `⌘⌥R` | 하단 / 우측 분할 |
| `⇧⌥W` / `⇧⌥A` / `⇧⌥S` / `⇧⌥D` | 위 / 왼쪽 / 아래 / 오른쪽 분할로 이동 (WASD) |

이동은 WASD, 분할은 방향의 첫 글자를 따르므로 `⌘⌥D`(아래로 분할)와
`⇧⌥D`(오른쪽으로 이동)에서 같은 글자가 다른 방향을 가리킨다.

폰트는 `nerd-fonts.jetbrains-mono` + `nerd-fonts.d2coding` 폴백 체인이다. darwin에서
home-manager는 `home.packages`의 폰트를 `~/Library/Fonts/HomeManager`로 rsync한다.
패밀리 이름은 각각 `JetBrainsMono Nerd Font` 와 `D2CodingLigature Nerd Font` 이고,
같은 패키지의 NL·Mono 변형은 별도 패밀리다. D2Coding 은 한글 글자 폭이 ASCII 의
정확히 두 배라 터미널 격자가 안 깨진다.

`xterm-ghostty` terminfo 를 sudo·ssh 너머까지 옮기는 방법은
[0014](decisions/0014-xterm-ghostty-terminfo.md).

## `pkgs/`

`posthog-cli`, `axiom-cli`, `langfuse-cli`, `vercel-cli`, `camoufox`,
`camofox-browser`는 nixpkgs 에 아예 없다. `slack-cli` 는 있는데 **다른 프로그램**이고
([0020](decisions/0020-slack-cli-attribute-replaced.md)), `tempo-cli` 는 nixpkgs
것을 잘라 쓴다. `pkgs/overlay.nix` 가 오버레이로 얹으므로, 이 디렉터리를 볼 일 없는
모듈에서도 그냥 `pkgs.posthog-cli`나 `pkgs.camofox-browser`로 쓴다.

| attribute | 출처 | 메모 |
|---|---|---|
| `posthog-cli` | crates.io | 모노레포라 git 대신 배포된 크레이트 |
| `axiom-cli` | GitHub 타르볼 | 평범한 Go 모듈. 바이너리 이름은 `axiom` |
| `langfuse-cli` | npm 타르볼 | lock 을 직접 만들어 함께 담았다 |
| `vercel-cli` | npm 타르볼 | manifest 를 `postPatch` 에서 편집 |
| `slack-cli` | GitHub 타르볼 | nixpkgs 의 동명 attribute 를 갈아끼운다 |
| `bun` | nixpkgs override | 필요한 버전이 한 릴리스 앞 |
| `tempo-cli` | nixpkgs override | `subPackages` 를 하나로 줄인다 |
| `camoufox` | GitHub macOS arm64 zip | 152.0.4-beta.28 코어. aarch64-darwin 전용 |
| `camofox-browser` | npm 타르볼 | `@askjo/camofox-browser` 1.13.1 + package-time headful opt-out |

CLI 패키징 결정과 각 패키지의 함정은
[0019](decisions/0019-package-from-published-artifacts.md), Camofox 쪽 결정은
[0031](decisions/0031-camofox-native-macos-over-wireguard.md)에 있다. 앞의 CLI
여섯만 [Cachix 로 올린다](operations.md#캐시-푸시). 브라우저 둘은 고정한 상류
아티팩트에서 풀고 서버 맥 하나만 소비하므로 cache-push 대상에서 뺐다.

## 이 레포를 패키지 저장소로 쓰기

`pkgs/` 는 내부용으로만 쓰이지 않고 **플레이크 출력으로 노출**된다. 다른 기기나
다른 사람이 디렉터리를 복사하는 대신 인풋으로 가져갈 수 있게 하려는 것이다.

```nix
inputs.bhyoo.url = "github:isac322/nix-config";
# 이후
nixpkgs.overlays = [ inputs.bhyoo.overlays.default ];
# 또는
environment.systemPackages = [ inputs.bhyoo.packages.${system}.posthog-cli ];
```

`overlays.default` 와 `packages.<system>` 둘 다 `pkgs/overlay.nix` **같은 파일**을
읽는다. 여기 있는 설정들도 같은 파일을 import 하므로 정의가 둘로 갈라져 어긋날
일이 없다. 공통 패키지는 `aarch64-darwin`, `aarch64-linux`, `x86_64-linux` 셋에
제공하고, `camoufox`와 `camofox-browser`는 `packages.aarch64-darwin`에만 제공한다.

Nix 에서 "저장소" 는 AUR 처럼 중앙 집중이 아니다. 레포가 이 두 출력을 갖는 순간
그것이 곧 패키지 저장소이고, 등록 절차도 심사도 없다. 남이 **발견**하게 하려면
그때 [NUR](https://github.com/nix-community/NUR) 의 `repos.json` 에 PR 을 올리면
되는데, NUR 은 코드를 담지 않고 레포 목록만 관리한다.
