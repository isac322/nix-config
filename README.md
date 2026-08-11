# nix config

`bhyoo`의 기기 전부를 담는 단일 flake. macOS 두 대와 NixOS 서버 한 대.

**레포를 하나로 두는 이유는 `flake.lock`이다.** lock 하나가 nixpkgs 리비전부터
home-manager, llm-agents까지 전부 고정한다. 기기별로 레포를 나누면 lock도 나뉘고,
맥북의 vim과 서버의 vim이 서로 다른 버전으로 갈라진다. "대부분의 설정을 공유"라는
전제가 거기서 깨진다.

## 구조

```
flake.nix          기기 목록. 각 기기가 어떤 모듈을 조합할지만 정한다
lib/caches.nix     플랫폼별 옵션 경로가 달라서 모듈이 아닌 순수 데이터로 둔 것
modules/           시스템 레벨
  common.nix         모든 OS 공통
  darwin.nix         모든 macOS
  nixos.nix          모든 NixOS
  roles/
    darwin-laptop.nix   랩탑 macOS
    darwin-server.nix   서버 macOS
hosts/             기기 고유
  bhyoo-macbook-air/
  bhyoo-mac-mini/
  server/            + hardware-configuration.nix
home/              사용자 레벨 (home-manager)
  common.nix         모든 기기 공통 — 설정의 대부분이 여기 있다
  darwin.nix         모든 macOS
  linux.nix          NixOS 전용
  roles/
    darwin-laptop.nix   데스크톱 앱
    darwin-server.nix
```

축이 셋(OS × 역할 × 기기)인데 상속이 아니라 **조합**으로 푼다. 모든 설정은
`common + platform + role + host`이고, 조합 지점은 `flake.nix` 한 곳뿐이다.

```nix
"bhyoo-macbook-air" = mkDarwin { hostname = "bhyoo-macbook-air"; role = "laptop"; };
"bhyoo-mac-mini"    = mkDarwin { hostname = "bhyoo-mac-mini";    role = "server"; };
```

### 무엇이 어느 층에 속하나

**모든 macOS** (`modules/darwin.nix`와 그것이 import하는 파일들) — 맥이라면
무조건 같아야 하는 것. 키 리매핑과 단축키 전부(`keyboard.nix`), Finder 전부
(`finder.nix`), Liquid Glass·Spotlight(`appearance.nix`), WARP(`warp.nix`),
Dock, 트랙패드, 키 반복, 데스크탑 비우기, Determinate·캐시, Homebrew 기반.

**역할 전용** — 역할 파일은 의도적으로 얇다. 맥은 어느 역할이든 같은 맥이라
겉모습 설정은 위층에 있고, 여기에는 진짜로 갈리는 것만 둔다.

| | 랩탑 | 서버 |
|---|---|---|
| 데스크톱 앱 (Firefox + cask 12개 + MAS 2개) | ✅ | ✖ |
| `nixpkgs-firefox-darwin` 오버레이 | ✅ | ✖ |
| 잠들지 않음 / 정전 후 자동 복구 | ✖ | ✅ |

GUI 앱은 nixpkgs가 아니라 Homebrew에서 온다. 대부분은 nixpkgs에 darwin 빌드가
아예 없고, 있는 것도 특권 구성요소가 빠진 앱 번들 복사본이다 — WARP과 Karabiner를
cask로 두는 것과 같은 이유다. `onActivation.upgrade`가 켜져 있어 최신 유지도
Homebrew가 한다.

셋은 예외적인 경로를 쓴다.

- **Orca** (Stably) — homebrew-cask가 아니라 자체 tap에 있어서 `homebrew.taps`에
  `stablyai/orca`를 같이 선언한다. nix-homebrew가 tap을 기본적으로 mutable로
  두기 때문에 tap을 flake 인풋으로 고정하지 않고도 동작한다.
### SSH 와 GPG — 열쇠 하나로 셋 다

둘 다 **모든 맥** 공통이다 (`home/darwin.nix`). 목적은 같다 — 매번 암호를 치지
않는 것. 그런데 필요한 서명이 셋이었다: SSH 접속 인증, git 커밋 서명, 그리고 Arch
패키징(`makepkg --sign`)이다.

**셋을 GPG 키 하나로 한다.** `makepkg --sign` 과 PKGBUILD 의 `validpgpkeys` 는 PGP
전용이라 SSH 서명이 대신할 수 없다 — pacman 의 신뢰 모델이 PGP 이기 때문이다.
(AUR 자체는 커밋 서명을 보지 않는다. `aur-dev` 에서 SSH 서명 검증이 논의된 적은
있으나 구현되지 않았고, AUR 은 푸시 인증에만 SSH 를 쓴다.) 즉 GPG 키는 어차피
있어야 한다. 그렇다면 SSH 키쌍을 따로 두는 대신 GPG 의 **인증(authentication)
서브키**를 gpg-agent 가 ssh-agent 프로토콜로 내주게 하면 — `enableSshSupport` 가
하는 일이다 — 기계마다 만들고 백업하고 등록할 키가 하나로 준다. 키를 옮기면 셋이
같이 옮겨간다.

**대가는 macOS 가 자기 ssh-agent 를 가리키고 있다는 것이다.** macOS 는 gpg-agent 를
내장하지 않지만 ssh-agent 는 `com.openssh.ssh-agent.plist` 로 띄우고, launchd 가
그 소켓 경로를 `SSH_AUTH_SOCK` 으로 **로그인 세션 전체**에 — GUI 앱 포함 — 심는다.
그래서 방향을 돌리는 데 서로 독립적인 조치가 둘 필요하다. 하나만 맞히면 가장
알아채기 어려운 곳에서 조용히 실패한다.

1. `~/.ssh/config` 의 `IdentityAgent` — ssh 바이너리는 누가 실행하든 이 파일을
   읽는다. 셸을 거치지 않는 GUI 앱이 ssh 를 호출하는 경우까지 덮는다.
2. `launchctl setenv SSH_AUTH_SOCK` LaunchAgent — home-manager 는 이 변수를 셸
   초기화에서만 내보내는데, 그건 터미널까지만 닿는다. launchd 로 뜬 앱은 셸
   프로파일을 읽지 않으므로, 변수를 직접 읽는 쪽을 위해 세션 전역으로 심는다.

`enableDefaultConfig` 는 꺼 두었다. 자체 `*` 블록이 위 설정과 충돌하기 때문이고,
기본값들은 그대로 옮겨 적되 `AddKeysToAgent` 와 `UseKeychain` 은 뺐다 — 둘 다
macOS ssh-agent 의 옵션인데 그게 더는 경로에 없다.

**패스프레이즈는 평생 한 번.** nixpkgs 의 `pinentry_mac` 은 GPGTools
빌드(`org.gpgtools.pinentry-mac`)라 패스프레이즈를 로그인 키체인에 저장할 수 있고,
GPGTools 는 "always allow" 로 저장한다. 그래서 캐시 TTL 은 관측되지 않는다:
만료될 때마다 pinentry 가 키체인에서 조용히 꺼내오므로 묻는 것은 최초 한 번뿐이다.
키가 하나이므로 이 한 번이 SSH 와 서명 양쪽을 덮는다. `UseKeychain` 과
`DisableKeychain = false` 가 둘 다 필요하다 — 후자의 기본값이 참이고, 그것이 켜져
있는 한 "Save in Keychain" 체크박스 자체가 나타나지 않는다.

**커밋 서명에 `user.signingkey` 를 쓰지 않는다.** 키가 지정되지 않고 형식이 기본값
openpgp 이면 git 은 커미터 신원을 그대로 gpg 에 넘긴다 (`-u "Name <email>"`,
`gpg-interface.c` 의 `get_signing_key`). 즉 **커밋이 누구 것이라고 말하는가로 키를
찾는다.** 키 ID 를 적어두면 기계마다 다르고 교체할 때마다 설정을 고쳐야 하는데,
이렇게 두면 그럴 일이 없다. 대신 조건이 붙는다 — 키의 사용자 ID 를
`Byeonghoon Yoo <bhyoo@bhyoo.com>` 으로, `home/common.nix` 의 이름과 이메일에
정확히 맞춰 만들어야 한다. 이메일만 같고 이름이 다르면 git 이 키를 찾지 못한다.

**키는 자동 생성하지 않는다.** 패스프레이즈를 거는 것이 위 키체인 설정의 목적인데
activation 은 프롬프트를 띄울 수 없어, 자동 생성은 곧 패스프레이즈 없는 키를
디스크에 두는 것이 된다. 그리고 애초에 키 하나를 여러 기계가 공유하는 구성이라
기계마다 새로 만드는 것은 목적에 어긋난다. 그래서 없으면 가져오는 법만 알려주고
끝낸다. 커밋 서명이 켜져 있으므로 키가 없으면 커밋이 실패하고, activation 이 그
사실과 아래 명령을 함께 출력한다.

```sh
gpg --import secret.asc            # 개인키
gpg --import-ownertrust trust.asc  # 선택. 신뢰 설정 복원
gpg --edit-key bhyoo@bhyoo.com     # trust, 5, y, quit — 내 키로 표시

gpg-ssh-authorize                  # 인증 서브키를 SSH 에 노출시킨다
ssh-add -L                         # 키가 뜨면 성공
```

**한 단계가 더 필요한 이유는** gpg-agent 가 비밀키를 다 갖고 있어도 그중 무엇을 SSH
로 내줄지는 따로 지정해야 하기 때문이다. 서명키까지 통째로 노출하지 않으려는
설계다. 그런데 지정에 쓰는 값이 **keygrip** — 키가 이 기계에 들어온 뒤에야 생기는
값이라 설정 파일에 미리 적어둘 수가 없다. 그래서 흔히 보이는 안내가 `gpg
--list-secret-keys --with-keygrip` 을 눈으로 읽어 `~/.gnupg/sshcontrol` 에 붙여넣는
것인데, 사람이 화면에서 옮겨 적는 단계는 이 저장소의 전제와 어긋난다.

`gpg-ssh-authorize` (`home/darwin.nix` 에서 정의) 는 그 값을 키링에서 직접
읽어낸다. `--with-colons` 출력에서 sec/ssb 레코드의 12번째 필드가 그 키의 용도이고
`a` 가 인증이므로, 그 뒤에 따라오는 `grp` 레코드가 곧 찾던 keygrip 이다. 즉 **볼
것도 고를 것도 없이** 인증 가능한 키 전부가 대상이 된다. switch 때마다 자동으로
돌고, 이미 표시된 키는 건드리지 않으므로 두 번 돌아도 조용하다. 키를 switch 사이에
가져왔다면 PATH 에도 있으니 그 자리에서 실행하면 된다.

표시가 저장되는 곳은 `~/.gnupg/sshcontrol` 이 아니라 **개인키 파일 안의
`Use-for-ssh` 속성**이고, `gpg-connect-agent` 의 `KEYATTR` 로 쓴다. GnuPG 매뉴얼이
2.3.7 부터 sshcontrol 을 두고 *"deprecated in favor of the `Use-for-ssh` attribute
in the key files"* 라고 명시하고 있다. 동작은 둘 다 하지만, 남는 쪽을 쓴다.

키가 아직 없다면 인증 서브키를 붙여서 만들고, 다른 기계로 내보낸다.

```sh
# 사용자 ID 는 반드시 Byeonghoon Yoo <bhyoo@bhyoo.com>
gpg --full-generate-key            # ed25519
gpg --edit-key bhyoo@bhyoo.com     # addkey → ECC → Authenticate

gpg --armor --export-secret-keys bhyoo@bhyoo.com > secret.asc
gpg --export-ownertrust > trust.asc
```

GitHub 에는 공개키를 GPG key 로 등록하면 커밋 검증이 되고, 접속용으로는 인증
서브키를 SSH key 로 따로 등록한다 (`gpg --export-ssh-key bhyoo@bhyoo.com`).
`allowed_signers` 는 SSH 서명 전용 파일이라 이제 없다 — GPG 검증은 키링이 한다.

**OrbStack 충돌.** OrbStack 은 `~/.ssh/config` 맨 위에 자기 `Include` 를 넣고
지우면 다시 넣는다. `programs.ssh.includes` 로 선언해 두면 home-manager 가 그
줄을 직접 맨 앞에 쓰므로 서로 싸우지 않는다. OrbStack 이 랩탑 전용이라 이 선언도
랩탑 역할에만 있다.

### Ghostty — 설정이 파일이라서 골랐다

랩탑의 터미널. quake 스타일 드롭다운(Ghostty가 "quick terminal"이라 부르는 것)이
내장이고, `⌃\``로 어느 앱 위에서든 내려온다.

같은 기능을 Warp, iTerm2, Tabby도 내장으로 갖고 있다. Ghostty를 고른 이유는
**설정이 평범한 텍스트 파일**(`~/.config/ghostty/config`)이기 때문이다. 나머지
셋은 GUI 환경설정 저장소에 값이 들어가서, 레포로 관리하려면 스냅샷을 뜨고 토글한
뒤 diff로 키를 찾아내는 짓을 해야 한다 — 이 레포에서 Liquid Glass와 Caps Lock에
실제로 했던 그것이다.

앱은 cask다. nixpkgs의 `ghostty`는 `meta.platforms`에 darwin이 없다. home-manager
모듈이 이 경우를 문서화해 두었으므로 `programs.ghostty.package = null`로 두고
설치만 Homebrew에 맡긴다.

**전역 단축키에는 접근성 권한이 필요하다.** `global:` 접두사가 붙은 키바인딩은
다른 앱이 포커스를 가진 상태에서도 동작해야 하므로 macOS가 승인을 요구한다.
선언으로 없앨 수 없는 한 번의 GUI 단계다.

단축키는 전역 두 개와 앱 내부 네 개다.

| 키 | 동작 |
|---|---|
| `F12` | 드롭다운 토글 (전역) |
| `⌘⌥T` | 일반 창 (전역). `new_window`는 포커스가 없으면 앱을 앞으로 가져오므로 "실행"도 겸한다 |
| `⌘⌥D` / `⌘⌥R` | 하단 / 우측 분할 |
| `⇧⌥W` / `⇧⌥A` / `⇧⌥S` / `⇧⌥D` | 위 / 왼쪽 / 아래 / 오른쪽 분할로 이동 (WASD) |

키를 고를 때는 macOS 자체 단축키 표(`DefaultShortcutsTable.xml`)와 이 기계의
`symbolichotkeys`를 대조해 충돌을 확인했다. F12(키코드 111)와 `⌘⌥R`은 비어
있었고, `⇧⌥` 조합은 시스템이 전혀 쓰지 않아 WASD 네 개가 모두 자유롭다.

이동은 WASD, 분할은 방향의 첫 글자를 따르므로 `⌘⌥D`(아래로 분할)와
`⇧⌥D`(오른쪽으로 이동)에서 같은 글자가 다른 방향을 가리킨다.

**`⌘⌥D`만 충돌했다.** macOS의 "Dock 자동 숨기기 켜기/끄기"(단축키 52번)가 그
조합이고, **시스템 단축키는 앱 단축키보다 우선**이라 Ghostty가 이벤트를 아예 받지
못한다. 그래서 52번을 꺼 두었다 — `system.defaults.dock.autohide`를 여기서
고정하고 있으므로 그 토글은 어차피 다음 activation에 되돌려질 뿐이다.

**전역 단축키는 앱이 떠 있어야 동작한다.** 키를 듣는 주체가 실행 중인 앱이라,
Ghostty가 꺼져 있으면 F12도 `⌘⌥T`도 아무 일도 하지 않는다. macOS에는 키에 앱
실행을 묶는 기본 기능이 없다 — 키보드 단축키 설정은 이미 실행 중인 앱의 메뉴
항목에만 닿는다. 그래서 두 가지를 함께 건다.

- `launchd.user.agents.ghostty` (`modules/roles/darwin-laptop.nix`)가 로그인 때
  `open -g -a Ghostty --args --initial-window=false`로 띄운다. `-g`는 포커스를
  뺏지 않고, `--initial-window=false`는 그 실행에만 적용되므로 손으로 열 때는
  평소대로 창이 뜬다.
- `quit-after-last-window-closed = false`로 마지막 창을 닫아도 프로세스가 남는다.
  macOS 기본값이지만 이 구조 전체가 여기에 의존하므로 명시해 둔다.

**드롭다운 창에는 탭이 없다.** macOS 네이티브 탭 구현상의 제약으로 quick terminal
과 non-native fullscreen 둘 다 탭을 지원하지 않는다 (ghostty #2888, #3629).
분할은 되므로 위 키들이 그 자리를 메운다. 일반 창(`⌘⌥T`)에서는 `⌘T`로 탭이
정상 동작한다.

폰트는 `nerd-fonts.jetbrains-mono`. darwin에서 home-manager는 `home.packages`의
폰트를 `~/Library/Fonts/HomeManager`로 rsync한다. 패밀리 이름은
`JetBrainsMono Nerd Font`이고, 같은 패키지의 NL·Mono 변형은 별도 패밀리다.

**한글은 폴백 체인으로 처리한다.** `font-family`를 여러 번 적으면 Ghostty가 위
폰트에 없는 코드포인트를 만났을 때 아래로 내려간다. JetBrains Mono에 한글이 없어서
두 번째 항목이 없으면 macOS가 아무 폰트나 고른다 — 그래서 한글만 어색해 보인다.

짝으로 D2Coding을 쓴다 (`nerd-fonts.d2coding`, 패밀리 이름
`D2CodingLigature Nerd Font`). 한글 글자 폭이 ASCII의 정확히 두 배라서 터미널
격자가 안 깨진다. 비례 한글 폰트는 이 조건을 만족하지 않고, 터미널에서는 그게
바로 티가 난다.

### 관측 CLI — 에이전트가 직접 조회하게

`tempo-cli`, `promtool`, `sentry-cli`, `posthog-cli`, `axiom` 다섯을 **모든 기기**에
둔다 (`home/common.nix`). 코딩 에이전트가 대시보드 스크린샷을 받는 대신 텔레메트리를
직접 질의하라고 두는 것이라, `claude-code` 와 같은 층에 있다 — 에이전트는 작업이
있는 곳에서 돈다.

셋은 nixpkgs 에서 바로 오지만 **어느 것도 이름 그대로의 attribute 가 아니다.**

- **`promtool` 은 `pkgs.prometheus` 에 없다.** 상류가 `moveToOutput bin/promtool
  $cli` 로 별도 출력에 옮겨 두어서, `pkgs.prometheus` 를 설치하면 서버와 `migrate`
  만 들어오고 정작 원한 도구는 안 들어온다. `pkgs.prometheus.cli` 로 집는다.
- **`tempo-cli` 는 잘라서 쓴다.** nixpkgs 의 `tempo` 는 `subPackages` 로 명령
  넷을 모두 빌드하는데 셋은 여기서 돌리지 않는 트레이스 저장소의 서버 쪽이다.
  `cmd/tempo-cli` 만 남기면 클로저가 237 MiB 에서 72 MiB 로 줄고, 서버로 읽히는
  `tempo` 라는 이름의 바이너리가 PATH 에서 빠진다 (`pkgs/overlay.nix`).
- **`axiom` 은 `axiom-cli` 가 아니다.** 바이너리 이름이 `axiom` 이다. attribute 는
  여기 있는 다른 CLI 옆에서 찾을 수 있게 `axiom-cli` 로 두었다.

### 이 레포를 패키지 저장소로 쓰기

`pkgs/` 는 내부용으로만 쓰이지 않고 **플레이크 출력으로 노출**된다. 다른 기기나
다른 사람이 디렉터리를 복사하는 대신 인풋으로 가져갈 수 있게 하려는 것이다.

```nix
inputs.bhyoo.url = "github:bhyoo/nix-darwin";   # 리모트가 생기면
# 이후
nixpkgs.overlays = [ inputs.bhyoo.overlays.default ];
# 또는
environment.systemPackages = [ inputs.bhyoo.packages.${system}.posthog-cli ];
```

`overlays.default` 와 `packages.<system>` 둘 다 `pkgs/overlay.nix` **같은 파일**을
읽는다. 여기 있는 설정들도 같은 파일을 import 하므로 정의가 둘로 갈라져 어긋날
일이 없다. 제공 시스템은 `aarch64-darwin`, `aarch64-linux`, `x86_64-linux` 셋이다.

Nix 에서 "저장소" 는 AUR 처럼 중앙 집중이 아니다. 레포가 이 두 출력을 갖는 순간
그것이 곧 패키지 저장소이고, 등록 절차도 심사도 없다. 남이 **발견**하게 하려면
그때 [NUR](https://github.com/nix-community/NUR) 의 `repos.json` 에 PR 을 올리면
되는데, NUR 은 코드를 담지 않고 레포 목록만 관리한다.

### 세 기기가 같은 것을 세 번 컴파일하지 않게 — Cachix

AUR 과 정말 다른 지점은 여기다. 배포 방식이 아니라 **빌드**가 아프다.
`pkgs/` 의 셋은 어떤 공개 캐시에도 없다 — 둘은 nixpkgs 에 존재하지 않고,
`tempo-cli` 는 오버라이드라 `cache.nixos.org` 가 빌드한 `tempo` 와 파생이 다르다.
그래서 기기마다 새로 컴파일한다. 나머지는 상류 캐시가 덮으므로, 올릴 가치가 있는
것은 정확히 이 셋뿐이다.

FlakeHub Cache 는 Determinate 를 이미 쓰는 만큼 자연스러워 보이지만 두 번 막힌다 —
유료 플랜 전용이고, 애드혹 push 를 의도적으로 금지해 신뢰된 빌더(GitHub Actions,
Semaphore, Buildkite)에서만 올릴 수 있다. 랩탑에서 빌드해 올리는 방식과 맞지 않는다.
Cachix 는 오픈소스에 5 GB 무료이고 어디서든 push 된다.

처음 한 번:

```sh
nix run nixpkgs#cachix -- authtoken <token>   # cachix.org 로그인 후 발급
nix run nixpkgs#cachix -- create <cache>      # 만들면 공개키가 출력된다
```

그 URL 과 공개키를 `lib/caches.nix` 의 표시된 자리에 넣는다. **미리 채워두지
않았다.** 키가 틀린 항목은 없는 것보다 나쁘다 — substituter 로 접속은 하면서
받아온 답을 매번 버리기 때문이다.

이후 패키지가 바뀔 때마다:

```sh
nix run /etc/nix-darwin#cache-push -- <cache>
```

푸시 대상 경로는 스크립트에 **박혀 있다**. 실행 시점에 `.#` 를 해석하지 않으므로
다른 디렉터리에서 불러도 맞고, 앱을 빌드하는 것이 곧 올릴 것을 빌드하는 것이다.
`cachix` 는 클로저가 344 MiB 라 홈 패키지에 상주시키지 않고 이 앱에만 매달아
두었다 — 쓸 때만 받아온다.

### nixpkgs 에 없어서 직접 담은 것 — `pkgs/`

`posthog-cli` 와 `axiom-cli` 는 nixpkgs 에 아예 없다. `pkgs/overlay.nix` 가
오버레이로 얹으므로, 이 디렉터리를 볼 일 없는 home-manager 모듈에서도 그냥
`pkgs.posthog-cli` 로 쓴다.

**posthog-cli 는 crates.io 에서 가져온다.** GitHub 이 아니라 crates.io 인 이유는,
이 CLI 가 PostHog 모노레포 안에 살아서 git 체크아웃을 하면 작은 바이너리 하나
만들자고 거대한 트리를 받아오기 때문이다. 배포된 크레이트는 같은 코드에 Cargo.lock
까지 들어 있다. 두 가지를 미리 확인했다 — 의존성이 rustls 로 풀려 Cargo.lock 어디에도
`openssl-sys` 가 없어서 맥과 리눅스가 같은 표현식으로 빌드되고, `build.rs` 가 심는
텔레메트리 토큰은 디버그 빌드 전용에 소비 측이 `option_env!` 이라 릴리스 빌드는 CI
시크릿 없이도 컴파일되고 토큰도 안 들어간다.

`fetchCrate` 의 해시는 파일 해시가 아니라 **압축을 푼 트리의 NAR 해시**다.
`nix store prefetch-file` 로 받은 값을 그대로 넣으면 어긋난다.

**axiom-cli 는 평범한 Go 모듈이다.** goreleaser 가 박는 변수 중 `version.release`
만 옮겨 심었다. 나머지 둘(`revision`, `buildDate`)은 체크아웃의 git 메타데이터를
요구하는데 받아온 타르볼에는 없다. 최소한 `release` 는 있어야 `axiom version` 이
빈 문자열을 뱉지 않는다. 셸 완성은 방금 빌드한 바이너리를 실행해서 만들므로
`stdenv.buildPlatform.canExecute` 로 감쌌다 — 크로스 빌드에서는 완성만 빠지고
빌드는 실패하지 않는다. posthog-cli 는 clap 정의에 완성 생성 서브커맨드가 없어
넣지 않았다.

### 1Password — GUI 와 CLI 를 나눠 담는다

`op` CLI는 **모든 맥**에 (`home/darwin.nix`), 데스크톱 앱은 **랩탑에만**
(`modules/roles/darwin-laptop.nix`) 들어간다.

`op`는 시스템 통합이 없는 단일 바이너리라 nixpkgs에서 와도 되고, 그래서
`flake.lock`에 고정된다. 데스크톱 앱은 그렇지 않다 — nixpkgs의 darwin 분기는
dmg에서 `.app`만 복사하는데(Firefox·WARP와 같은 모양), 1Password 앱은 브라우저
연동과 SSH 에이전트 같은 시스템 통합에 의존하므로 cask로 설치한다.

**헤드리스 서버는 CLI만으로 충분하다.** 데스크톱 앱 없이도 서비스 계정 토큰
(`OP_SERVICE_ACCOUNT_TOKEN`, CLI 2.18.0+)으로 비대화형 인증이 되고, 이것이
1Password가 헤드리스 환경에 문서화해 둔 방식이다. 다만 **SSH 에이전트 기능은
데스크톱 앱을 요구**하므로, 서버에서 1Password의 SSH 에이전트를 쓰려면 그때는
`modules/roles/darwin-server.nix`에 cask를 추가해야 한다 — 그러면 GUI 세션이
필요해진다.

- **KakaoTalk**, **WireGuard** — **선언적으로 설치할 방법이 없다.** 둘 다 Mac
  App Store 전용이다.

  KakaoTalk은 Homebrew 전체에 cask가 없고, nixpkgs에도 없으며, 직접 다운로드도
  없다 (카카오 CDN 경로는 브라우저 헤더를 붙여도 전부 403). WireGuard도 공식
  클라이언트는 App Store 전용이고, cask에서 WireGuard를 언급하는 것들
  (`defguard-client`, `firezone`, `passepartout`, `tailscale-app`)은 전부 다른
  회사의 다른 앱이다. nixpkgs의 `wireguard-tools`/`wireguard-go`는 CLI지 그 앱이
  아니다.

  `homebrew.masApps`도 답이 아니다: activation 중 `brew bundle`이 sudo로 도는데
  App Store의 `installd`는 로그인한 사용자 세션 안에서만 응답해서 `mas`가 닿지
  못한다 (mas-cli 이슈 #1221). 조용히 실패하지도 않는다 — 이 두 항목이
  `brew bundle`을 실패시키고 `set -e`가 activation 나머지를 끊는다.

  그래서 둘 다 App Store에서 손으로 설치한다. 기계당 한 번.

오버레이가 랩탑에만 있는 이유는 무해하지 않기 때문이다. `firefox-bin` 외에
`librewolf`, `floorp-bin`, `zen-browser-bin`도 정의해서 같은 이름의 nixpkgs
패키지를 가린다. 검증: 맥북에서 `librewolf.pname`은 `Librewolf`(오버레이),
맥미니에서는 `librewolf`(nixpkgs).

**기기 전용** (`hosts/<name>/`) — 정말 그 기계에만 해당하는 것. 지금은
`hostPlatform`과 서버의 `hardware-configuration.nix`뿐이다.

세 층 어디에도 안 맞는 것은 `extraModules` / `extraHomeModules`로 넘긴다 —
한 기계가 미디어 서버를 겸하는 식의 경우.

## 기기별 명령

속성 이름은 각 기기의 호스트명과 같다. 이름이 맞으면 속성을 생략해도 되고,
아니면 명시한다.

```sh
# 맥 (해당 기기에서)
sudo darwin-rebuild switch --flake ~/nix-config#bhyoo-macbook-air
sudo darwin-rebuild switch --flake ~/nix-config#bhyoo-mac-mini

# 서버 (해당 기기에서)
sudo nixos-rebuild switch --flake ~/nix-config#server

# 서버 (맥에서 원격으로). --build-host 를 같이 주는 것이 핵심이다:
# 맥은 aarch64-darwin 이라 aarch64-linux 파생물을 realise 할 수 없다.
# 이렇게 하면 빌드가 서버에서 일어나므로 맥에 리눅스 빌더가 필요 없다.
nixos-rebuild switch --flake ~/nix-config#server \
  --target-host root@server --build-host root@server
```

레포 경로는 기기마다 달라도 된다. flake 경로는 `--flake`로 지정하는 값일 뿐이라
설계에 영향이 없다.

### 기기 간 독립성

각 기기는 자기 설정을 스스로 빌드하고 전환한다. 서버는 맥에 전혀 의존하지 않는다.
다만 두 가지를 기억할 것.

**`flake.lock`은 공유 상태다.** `switch`는 lock을 건드리지 않지만
`nix flake update`는 다시 쓴다. 기기마다 각자 update를 돌리면 lock이 갈라지고,
단일 레포로 묶은 의미가 사라진다. 한 기기에서 update → commit → push 하고
나머지는 pull → switch 한다.

**평가는 크로스 플랫폼이지만 빌드는 아니다.** 맥에서 `nixosConfigurations.server`를
평가해 drv 를 얻는 것은 되지만 realise 는 안 된다 (`extra-platforms` 가 비어 있고
`/etc/nix/machines` 도 없다). 맥에서 서버를 직접 빌드하고 싶다면 Determinate 의
네이티브 리눅스 빌더를 켠다. `system-features` 에 `apple-virt` 가 이미 있으므로
Apple Silicon 에서는 aarch64-linux 가 나온다 — 서버와 같은 아키텍처다.

```nix
# modules/darwin.nix 또는 특정 호스트에서
determinateNixd.builder = {
  state = "enabled";
  memoryBytes = 8589934592;  # 8 GiB
  cpuCount = 4;
};
```

## 새 기기에 올리기

선언적으로 되지 않는 부트스트랩이 남아 있다.

### 맥

1. **Determinate Nix 설치.** nix-darwin 모듈은 설치해주지 않는다.
   <https://install.determinate.systems/determinate-pkg/stable/Universal>
2. **레포 clone.**
3. **바이너리 캐시 부트스트랩** (선택, 강력 권장). 첫 `switch`는 `nix.custom.conf`가
   적용되기 전에 빌드한다. 건너뛰면 `omp`를 소스에서 빌드한다 — Rust 툴체인 + zig
   461 MiB를 받고 cargo vendor부터 전부 컴파일한다.
   ```sh
   printf '\nextra-substituters = https://cache.numtide.com\nextra-trusted-public-keys = niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g=\n' \
     | sudo tee -a /etc/nix/nix.custom.conf
   sudo launchctl kickstart -k system/systems.determinate.nix-daemon
   ```
   activation이 같은 내용을 선언적으로 다시 깔아주므로 이후에는 신경 쓸 필요 없다.
4. `sudo darwin-rebuild switch --flake <path>#<hostname>`
5. **App Management 권한 승인.** `home.stateVersion >= 25.11`이라
   `targets.darwin.copyApps`가 켜져 있고 Firefox.app을
   `~/Applications/Home Manager Apps/`로 복사한다. 거부하면 activation이 실패한다.
   시스템 설정 → 개인정보 보호 및 보안 → 앱 관리.

### 서버

1. NixOS 설치 후 `nixos-generate-config --show-hardware-config`를 실행해
   `hosts/server/hardware-configuration.nix`를 **통째로 교체한다.** 지금 들어 있는
   건 맥에서 flake가 평가되도록 하기 위한 자리표시자이고 부팅되지 않는다.
2. `services.openssh.settings.PasswordAuthentication = false`이므로 설치 시
   `users.users.bhyoo.openssh.authorizedKeys.keys`를 넣어두거나 콘솔로 접근한다.
3. `sudo nixos-rebuild switch --flake <path>#server`

## 업데이트

버전은 전부 `flake.lock`에 고정돼 있다. lock을 갱신해야 올라간다.

```sh
nix flake update                    # 전체
nix flake update nixpkgs            # 특정 인풋만
# 그리고 각 기기에서 switch
```

flake 밖에서 관리되는 것:

- **Nix 자체 (맥)** — `sudo determinate-nixd upgrade`
- **Homebrew** — `onActivation.{upgrade,autoUpdate}`가 켜져 있어 switch 때 같이 올라간다

## 설계 메모

### 공유 모듈에 넣으면 안 되는 것

- **`system.stateVersion`** — nix-darwin은 정수(`7`), NixOS는 문자열(`"26.05"`).
  타입이 달라서 공통 모듈에 두면 평가가 깨진다. 각 플랫폼 모듈에 따로 있다.
- **`nixpkgs-firefox-darwin` 오버레이** — `firefox-bin` 외에 `librewolf`,
  `floorp-bin`, `zen-browser-bin`도 정의한다. Linux에 걸면 nixpkgs 원본을 가려버린다.
  그래서 `modules/darwin.nix`에만 있다. 검증: 맥에서 `librewolf.pname`은
  `Librewolf`(오버레이), 서버에서는 `librewolf`(nixpkgs).
- **공유 기본값은 `lib.mkDefault`로** — `modules/darwin.nix`의 `system.defaults`가
  그렇다. 없으면 호스트가 같은 옵션을 정의할 때 동일 우선순위로 충돌한다.

### Nix 설정을 맥에서는 nix-darwin이 소유하지 않는 이유

nix-darwin의 nix 모듈은 Nix 패키지, `/etc/nix/nix.conf`,
`org.nixos.nix-daemon` launchd 데몬을 관리하려 한다. 맥에서는 셋 다 Determinate
Nix(`systems.determinate.nix-daemon`)가 이미 소유하고 있어 정면으로 충돌한다.
그래서 `determinateNix.enable = true`로 `nix.enable`을 강제로 끄고, Determinate가
`nix.conf`에 남겨둔 `!include nix.custom.conf` 확장 지점만 `customSettings`로 채운다.

NixOS에는 이 문제가 없다. Nix가 시스템 클로저의 일부라서 `nix.settings`로 직접
쓴다. 같은 캐시 설정이 플랫폼마다 다른 옵션 경로로 들어가는 이유이고,
`lib/caches.nix`가 순수 데이터인 이유다.

### Firefox 정책을 두 경로로 넣는 이유

`firefox-bin`은 오버레이가 제공하는 순수 `.app` 번들이라 home-manager가 wrap할 수
없다. 그래서 정책을 두 군데에 넣는다.

1. 번들 안 `Contents/Resources/distribution/policies.json` — 오버레이의 `extraFiles`
2. `~/Library/Preferences/org.mozilla.firefox.plist` — home-manager의 `policies`

`home/roles/darwin-laptop.nix`에서 `let policies = ...`로 한 번만 정의해 양쪽에
`inherit`한다.
Linux 데스크톱이 생기면 같은 `policies`를 `pkgs.firefox`에 그냥 넘기면 된다 —
"같은 옵션, 다른 구현"의 전형적인 사례다.

### 맥 키보드 · 트랙패드

모디파이어 회전은 `modules/keyboard.nix`에 hidutil로 들어 있다.

```
fn → left command → left option → left control → fn
right command → F18 → (단축키 60) 이전 입력 소스 선택 = 한/영
```

단축키는 `modules/keyboard.nix`가 activation 때 넣는다.

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

**Karabiner-Elements를 쓰지 않는다.** 콘솔에 사람이 없으면 올릴 수 없기 때문이다.
DriverKit 확장을 시스템 설정에서 승인해야 하고, grabber에 입력 모니터링 권한이
필요한데 그 권한을 기록하는 TCC 데이터베이스는 SIP로 보호된다 — CLI도, defaults 키도
없다. MDM 프로파일만이 미리 허가할 수 있다.

hidutil은 그런 게 하나도 필요 없다. root로 IOKit 안에서 remap하고, 내장 키보드를
포함한 모든 키보드에 적용되며, `org.nixos.activate-system` LaunchDaemon이 부팅마다
다시 실행하므로 로그인 항목 없이 재부팅을 견딘다. 대가는 1:1 리매핑만 된다는 것 —
조건부·코드 규칙은 못 한다. 여기서 필요한 건 그 이상이 아니다.

UserKeyMapping 값은 64비트다. 상위 32비트가 HID usage page, 하위가 usage다.
키보드/키패드는 page 0x07이고, **fn만 애플 벤더 top case page 0xFF에 있다**
(`0xFF00000003`).

### 한/영 전환은 왜 F18을 거치는가

오른쪽 command를 `lang1`(0x90, 애플 한국어 키보드의 한/영 키가 보내는 usage)로
매핑하는 것은 hidutil이 받아들이기는 하지만 **macOS가 반응하지 않는다.** 동작하는
방법은 쓰지 않는 키를 보내고 그것을 입력 소스 단축키에 묶는 것이다.

```
오른쪽 command → F18 (hidutil)
F18 → 단축키 60번 "이전 입력 소스 선택" (com.apple.symbolichotkeys)
```

라틴 소스 하나와 한국어 소스 하나만 있으면 "이전 입력 소스"는 곧 한/영 토글이다.

단축키는 `system.defaults.CustomUserPreferences`가 아니라 activation 스크립트에서
`defaults write ... -dict-add`로 넣는다. `AppleSymbolicHotKeys`는 시스템의 모든
단축키를 담은 **하나의 딕셔너리**인데 nix-darwin은 키를 통째로 덮어쓰기 때문에,
그대로 쓰면 여기 적지 않은 스무 개 남짓이 사라진다. `-dict-add`는 병합한다.

`parameters`는 (ASCII 문자, 가상 키코드, 모디파이어 마스크)이고 65535는 대응하는
ASCII가 없다는 뜻이다. 마스크는 shift 131072, control 262144, option 524288,
command 1048576. Spotlight(64번)를 ⌥Space로 바꾸는 것도 같은 경로다.

### Caps Lock 한/영 전환 끄기 — `roman-switch`

macOS Sierra 이후, 한국어 입력 소스가 있으면 **Caps Lock이 기본적으로 한/영
전환**이고 길게 누르면 본래의 대문자 잠금이 된다. 여기서는 Caps Lock을 Caps Lock으로
두고 한/영은 오른쪽 command가 맡는다.

**이 설정에는 defaults 키가 없다.** 토글을 움직여도 어느 plist에도 나타나지 않는다.
시스템 설정이 HIToolbox의 비공개 함수를 호출하기 때문이다. Keyboard 설정 확장
바이너리의 임포트 심볼을 보면 드러난다.

```
_TISIsRomanSwitchAllowed
_TISIsRomanSwitchEnabled
_TISSetRomanSwitchState
```

"Roman switch"가 이 기능의 내부 이름이다. `modules/keyboard.nix`가 이 셋을
Carbon.framework에서 `dlsym`으로 찾아 호출하는 작은 C 프로그램을 빌드해서 activation
때 실행한다. 왕복 테스트로 확인했다 — `off` → `enabled=0`, `on` → `enabled=1`.

비공개 API라 macOS 업데이트로 사라질 수 있다. 그래서 심볼을 못 찾으면 경고만 남기고
0으로 종료해 activation을 막지 않는다. `TISIsRomanSwitchAllowed()`가 거짓이면
(비라틴 입력 소스가 없으면) 아무것도 하지 않고, 이미 원하는 상태면 건너뛴다.

키 리매핑으로는 우회할 수 없다는 점도 적어 둔다. macOS가 caps lock 이벤트 자체를
가로채므로, 다른 키를 caps lock으로 보내면 그 키도 똑같이 한/영 전환이 된다.

**fn이 command가 되면서 F1–F12의 미디어 기능은 물리적 왼쪽 control로 옮겨간다.**
회전 후 그 키가 fn을 보내기 때문이다. `com.apple.keyboard.fnState = true`와 짝이다.

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

### `activateSettings` 를 직접 부르는 이유

nix-darwin은 `system.defaults`의 plist를 쓰기만 하고 macOS에 다시 읽으라고 말하지
않는다. 그래서 키보드·트랙패드 설정이 파일에는 들어갔는데 다음 로그인까지 반영되지
않는다. `modules/keyboard.nix`가 activation 끝에 시스템 설정 앱이 하는 것과 같은
새로고침을 부른다. 사용자 도메인의 defaults라 사용자 권한으로 실행한다.

### Esc 아래 키의 ₩ 문제

`~/Library/KeyBindings/DefaultKeyBinding.dict`로 해결한다.

```
{
    "₩" = ("insertText:", "`");
}
```

키 리매핑으로는 풀 수 없다. ₩는 2벌식 레이아웃이 그렇게 정한 결과이고 그 레이아웃은
hidutil이나 Karabiner보다 하류에 있어서, 어떤 키가 도착하는지는 바꿀 수 있어도
레이아웃이 무엇을 만들지는 못 바꾼다. 입력 소스를 잠깐 빠져나갔다 돌아오는 우회가
있지만 upstream이 그걸 막는다 —
"switching to input sources which have input_mode_id (Chinese, Japanese, **Korean**,
Vietnamese) may be failed due to an macOS issue."

그래서 문자가 실제로 삽입되는 지점에서 고친다. Cocoa 텍스트 시스템이 이 파일을 읽고,
₩를 넣으려던 자리에 백틱을 넣는다. 한글 모드·영문 모드 모두 해당된다.

**한계:** Cocoa 메커니즘이라 자체 텍스트 스택을 그리는 앱(Electron, JetBrains, 일부
터미널)에는 적용되지 않는다. 앱은 실행 시점에 이 파일을 읽으므로 첫 적용 후 재시작이
필요하다.

### Cloudflare WARP

두 맥이 **완전히 같다.** 같은 클라이언트, 같은 Zero Trust 조직(`runbear`). WARP는
아웃바운드 클라이언트라, 책상에 놓인 기계든 들고 다니는 기계든 내부 전용 서비스에
닿기 위해 쓰는 방식이 동일하다. 그래서 `modules/warp.nix`는 호스트 분기가 없다.

**Homebrew cask로 설치한다.** nixpkgs도 `cloudflare-warp`를 aarch64-darwin으로
빌드하지만, darwin 분기는 `.pkg` payload에서 `Cloudflare WARP.app`만 꺼내 복사하고
`warp-cli`를 심볼릭 링크할 뿐이다. 정작 클라이언트가 올라타는 특권 데몬
`/Library/LaunchDaemons/com.cloudflare.1dot1dot1dot1.macos.warp.daemon.plist`는
`.pkg` 자신이 설치하고, 그 `.pkg`를 실제로 실행하는 건 cask뿐이다. Karabiner와 같은
모양의 문제 — 실체가 시스템 서비스인 패키지는 스토어에서 설치할 수 없다.

조직 등록은 선언적으로 들어간다. macOS는
`/Library/Application Support/Cloudflare/mdm.xml`을 읽고, 서비스가 로그인 전에 이를
적용하므로 기계마다 team 이름을 입력할 필요가 없다. 여기 적은 값이 대시보드의 기기
설정을 덮어쓰므로, 레포에 둘 만한 것만 적는다.

`service_mode`는 `warp`(전체 터널)다. 내부 전용 서비스에 닿으려면 이게 필요하고,
`1dot1`은 DNS만 암호화한다. `onboarding = false`는 최초 실행 화면을 건너뛰고,
`auto_connect = 1`은 누가 스위치를 켜주길 기다리지 않는다 — 둘 다 헤드리스에서 의미가
있다.

### 헤드리스 등록 — service token

service token이 없으면 등록이 브라우저를 열어 Access 로그인을 요구한다. 사람이 없는
기계에서는 그게 막힌다. 토큰을 넣으면 상호작용 없이 등록된다.

만드는 곳: Zero Trust > Access controls > Service credentials > Service Tokens.
그리고 Team & Resources > Devices > Management 에서 **Service Auth** 기기 등록
정책으로 그 토큰을 허용해야 한다.

**비밀은 레포에 들어가지 않는다.** activation 스크립트가
`/var/lib/cloudflare-warp/service-token`을 읽고, 있으면 `auth_client_id` /
`auth_client_secret`을 mdm.xml에 넣은 뒤 파일 권한을 `0600`으로 조인다. 없으면 그
두 키 없이 쓰고 경고만 남긴다 — 설정이 깨지지 않는다.

```sh
sudo install -d -m 0700 /var/lib/cloudflare-warp
sudo tee /var/lib/cloudflare-warp/service-token >/dev/null <<'EOF'
CLIENT_ID=<...>.access
CLIENT_SECRET=<...>
EOF
sudo chmod 0600 /var/lib/cloudflare-warp/service-token
```

agenix나 sops-nix로 레포에 암호화해 넣으면 이 한 단계도 사라진다.

### Vim이 vim-sensible 위에 얹히는 방식

nixpkgs는 sensible의 `s:MaySet`에 패치를 넣어, 옵션이 이미 `/nix/store` 경로에서
설정됐으면 건드리지 않게 한다. 우리 vimrc가 거기 있으므로 겹치면 우리 설정이 이긴다.
그래서 sensible이 이미 주는 것(backspace, smarttab, incsearch, ruler, laststatus,
wildmenu, autoread ...)은 `home/common.nix`에 다시 쓰지 않는다.

예외가 하나 있다. `history`는 vimrc 2번 줄의 `set nocompatible`이 이미 값을
바꿔놓고, 그 줄이 `/nix/store`에 있어서 sensible이 자기 `history=1000`을 건너뛴다.
그래서 명시적으로 설정한다.

### `follows`를 일부러 안 붙인 인풋

- `llm-agents` — `shared-nixpkgs` 오버레이가 `bun`을 자기 nixpkgs에서 고정한다.
  follows를 걸면 세트 전체의 store path가 바뀌어 캐시가 전부 빗나간다.
- `determinate` — upstream이 FlakeHub 캐시 미스를 이유로 권장하지 않는다.

### `environment.etc."nix/nix.custom.conf".knownSha256Hashes`

Determinate 설치 프로그램이 만들어둔 `nix.custom.conf`를 determinate 모듈이 덮어쓰려
하는데, nix-darwin은 정체불명 파일을 만나면 activation을 중단한다. 설치 프로그램이
쓴 파일의 해시를 화이트리스트에 넣어 첫 activation이 통과하게 한다. 설치 옵션이
다르면 해시도 달라지므로, 그때는 새 해시를 목록에 추가한다.
