# nix config

`bhyoo`의 기기 전부를 담는 단일 flake. macOS 두 대와 NixOS 서버 한 대.

**레포를 하나로 두는 이유는 `flake.lock`이다.** lock 하나가 nixpkgs 리비전부터
home-manager, llm-agents까지 전부 고정한다. 기기별로 레포를 나누면 lock도 나뉘고,
맥북의 vim과 서버의 vim이 서로 다른 버전으로 갈라진다. "대부분의 설정을 공유"라는
전제가 거기서 깨진다.

## 새 기기에 올리기

선언적으로 되지 않는 부트스트랩이 남아 있다.

### 맥

1. **Determinate Nix 설치.** nix-darwin 모듈은 설치해주지 않는다.
   <https://install.determinate.systems/determinate-pkg/stable/Universal>
2. **레포 clone.**
3. **호스트명을 이 기기의 flake 속성 이름으로 맞춘다.** 이 이름이 어느 설정을
   고를지의 입력이다 — 안 맞으면 그냥 실패한다. 목록은 레포가 갖고 있으므로 물어보면
   된다.
   ```sh
   nix eval --json .#darwinConfigurations --apply builtins.attrNames
   NAME=<위 목록에서 이 기기>
   sudo scutil --set ComputerName  "$NAME"   # 공유 화면에 보이는 이름
   sudo scutil --set LocalHostName "$NAME"   # Bonjour, .local — 이게 결정한다
   sudo scutil --set HostName      "$NAME"   # 셸 프롬프트, hostname(1)
   ```
   셋 중 `LocalHostName` 만 설정 선택에 관여하지만, 셋이 갈라져 있으면 나중에
   기계를 헷갈리므로 같이 세운다. nix-darwin 에 맡길 수도 있지만
   (`networking.hostName` 등) 일부러 두지 않았다 — 이름이 곧 입력이라 설정 안에
   두면 잘못된 기기 설정을 한 번 적용해야 이름이 고쳐지는 순환이 된다.
4. **바이너리 캐시 부트스트랩** (선택, 강력 권장). 첫 `switch`는 `nix.custom.conf`가
   적용되기 전에 빌드한다. 건너뛰면 `omp`를 소스에서 빌드한다 — Rust 툴체인 + zig
   461 MiB를 받고 cargo vendor부터 전부 컴파일한다.
   ```sh
   printf '\nextra-substituters = https://cache.numtide.com\nextra-trusted-public-keys = niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g=\n' \
     | sudo tee -a /etc/nix/nix.custom.conf
   sudo launchctl kickstart -k system/systems.determinate.nix-daemon
   ```
   activation이 같은 내용을 선언적으로 다시 깔아주므로 이후에는 신경 쓸 필요 없다.
5. **첫 `switch`.** 이때는 `darwin-rebuild` 가 아직 PATH 에 없다 — 그 명령 자체가
   nix-darwin 이 깔아주는 것이고, 설치 프로그램은 따로 없다. 시스템을 한 번 빌드하면
   결과물 안에 들어 있으므로 그걸로 자기 자신을 설치한다. 레포 루트에서:
   ```sh
   nix build .#darwinConfigurations.$(scutil --get LocalHostName).system
   sudo ./result/sw/bin/darwin-rebuild switch --flake .
   ```
   업스트림이 안내하는 `sudo nix run nix-darwin/master#darwin-rebuild -- switch` 도
   되지만 그건 nix-darwin 을 **master 에서** 끌어온다. 위 방식은 `flake.lock` 에
   핀 고정된 리비전을 쓰므로 두 번째 switch 부터와 같은 버전이다.

   두 번째부터는 `darwin-rebuild` 가 PATH 에 있으므로 아래
   [기기별 명령](#기기별-명령) 대로 하면 된다.
6. **App Management 권한 승인.** `home.stateVersion >= 25.11`이라
   `targets.darwin.copyApps`가 켜져 있고 Firefox.app을
   `~/Applications/Home Manager Apps/`로 복사한다. 거부하면 activation이 실패한다.
   시스템 설정 → 개인정보 보호 및 보안 → 앱 관리.
7. **GPG 키 가져오기.** 커밋 서명과 SSH 인증이 둘 다 이 키를 쓰므로 없으면 둘 다
   먹통이다. activation 이 없다는 걸 알아채고 절차를 그 자리에서 안내한다 —
   아래 [SSH 와 GPG](#ssh-와-gpg--열쇠-하나로-셋-다) 와 같은 내용이다.
8. **WARP service token** — 서버 역할의 맥만. 아래
   [헤드리스 등록](#헤드리스-등록--service-token) 을 보라.

### 서버

1. NixOS 설치 후 `nixos-generate-config --show-hardware-config`를 실행해
   `hosts/server/hardware-configuration.nix`를 **통째로 교체한다.** 지금 들어 있는
   건 맥에서 flake가 평가되도록 하기 위한 자리표시자이고 부팅되지 않는다.
2. `services.openssh.settings.PasswordAuthentication = false`이므로 설치 시
   `users.users.bhyoo.openssh.authorizedKeys.keys`를 넣어두거나 콘솔로 접근한다.
3. `sudo nixos-rebuild switch --flake <path>#server`

## 기기별 명령

**맥에서는 기기 이름을 칠 일이 없다.** `darwin-rebuild` 는 `#` 이 없으면
`scutil --get LocalHostName` 을 속성 이름으로 쓰고(핀 고정된
`pkgs/nix-tools/darwin-rebuild.sh`), `--flake` 자체가 없으면
`/etc/nix-darwin/flake.nix` 를 따라간다 — 심링크여도 된다.
[부트스트랩 3번](#맥) 에서 이름을 세워 두면 그 뒤로는 아래 한 줄이 전부다.
`nixos-rebuild` 는 이 편의가 없어서 서버만 `#server` 를 붙인다.

```sh
# 맥 (해당 기기에서). 이름이 맞으면 이게 전부다
sudo darwin-rebuild switch --flake ~/nix-config
sudo darwin-rebuild switch                      # 레포가 /etc/nix-darwin 일 때

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
```

축이 셋(OS × 역할 × 기기)인데 상속이 아니라 **조합**으로 푼다. 모든 설정은
`common + platform + role + host`이고, 조합 지점은 `flake.nix` 한 곳뿐이다.

```nix
"bhyoo-macbook-air" = mkDarwin { hostname = "bhyoo-macbook-air"; role = "laptop"; };
"bhyoo-macbook-pro" = mkDarwin { hostname = "bhyoo-macbook-pro"; role = "server"; };
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
| 데스크톱 앱 (Firefox + cask 15개 + MAS 2개) | ✅ | ✖ |
| `nixpkgs-firefox-darwin` 오버레이 | ✅ | ✖ |
| Touch ID 로 sudo (`pam_tid`) | ✅ | ✖ |
| [전원 연결 중엔 뚜껑을 닫아도 안 잠](#전원-연결-중에만-뚜껑을-닫아도-안-자게) · 정전 후 자동 복구 | ✖ | ✅ |
| 크롬(agent-browser 용) · Rust · 언어 서버 | ✖ | ✅ |

두 맥 다 MacBook Pro 급 하드웨어이고 Touch ID 센서도 둘 다 달려 있다. 랩탑에만
있는 이유는 하드웨어가 아니라 역할이다 — 서버 맥은 뚜껑을 닫은 채 SSH 로만
들어가므로 `pam_tid` 가 프롬프트를 띄울 화면이 없다.

GUI 앱은 nixpkgs가 아니라 Homebrew에서 온다. 대부분은 nixpkgs에 darwin 빌드가
아예 없고, 있는 것도 특권 구성요소가 빠진 앱 번들 복사본이다 — WARP과 Karabiner를
cask로 두는 것과 같은 이유다. `onActivation.upgrade`가 켜져 있어 최신 유지도
Homebrew가 한다.

둘은 예외적인 경로를 쓴다.

- **Orca** (Stably) — homebrew-cask가 아니라 자체 tap에 있어서 `homebrew.taps`에
  `stablyai/orca`를 같이 선언한다. nix-homebrew가 tap을 기본적으로 mutable로
  두기 때문에 tap을 flake 인풋으로 고정하지 않고도 동작한다.
- **서버 맥의 크롬** — 위 문단의 유일한 반례로, nixpkgs 에서 온다. 사람이 쓰는
  브라우저가 아니라 `agent-browser` 가 몰 대상이라 자동 업데이트가 장점이 아니고,
  캐스크가 아니면 activation 중 root 도 필요 없다. 자동 탐지에 걸리지 않는
  경로에 설치되므로 환경변수를 같이 세운다 — [agent-browser 에게 브라우저를
  쥐여주는 두 가지 방법](#agent-browser-에게-브라우저를-쥐여주는-두-가지-방법).

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
그래서 방향을 돌리는 데 조치가 셋 필요하다. 이건 이 저장소가 고안한 게 아니라 이
설정을 다루는 모든 안내가 공통으로 말하는 셋이고, 다만 셸 프로파일에 붙여넣는 대신
선언으로 옮겨 적었을 뿐이다.

1. **에이전트를 띄운다** — `gpgconf --launch gpg-agent`. gpg 는 필요할 때 알아서
   에이전트를 띄우지만 **ssh 는 gpg-agent 라는 것을 모른다.** 소켓을 열어보고 없으면
   포기할 뿐이다. 로그인 직후 gpg 명령을 한 번도 안 돌린 시점이 정확히 그 상황이다.
   보통 셸 프로파일에 넣으라고 하는 줄인데, 세션 전체에 걸리는 게 목적이므로
   LaunchAgent 에 둔다.
2. **`~/.ssh/config` 의 `IdentityAgent`** — ssh 바이너리는 누가 실행하든 이 파일을
   읽는다. 셸을 거치지 않는 GUI 앱이 ssh 를 호출하는 경우까지 덮는다.
3. **`launchctl setenv SSH_AUTH_SOCK`** — home-manager 는 이 변수를 셸 초기화에서만
   내보내는데, 그건 터미널까지만 닿는다. launchd 로 뜬 앱은 셸 프로파일을 읽지
   않으므로, 변수를 직접 읽는 쪽을 위해 세션 전역으로 심는다.

**home-manager 의 gpg-agent LaunchAgent 는 끈다** (`launchd.agents.gpg-agent.enable
= mkForce false`). `services.gpg-agent` 는 darwin 에서 `/private/var/run` 아래
launchd 소켓을 걸고 `gpg-agent --supervised` 를 띄우는 잡을 만드는데, `--supervised`
는 **systemd 의 소켓 액티베이션 규약**(환경변수 `LISTEN_FDS`, 그리고 fd 3 에 걸린
리스닝 소켓)을 구현한 모드다. launchd 는 소켓을 자기 API 로 넘기므로 fd 3 은 결코
소켓이 아니고, 잡은 뜨는 즉시 죽는다.

```
Fatal: file descriptor 3 must be valid in --supervised mode if LISTEN_FDNAMES is not set
```

여기서 나쁜 건 실패 자체가 아니라 **실패하는 방식**이다. launchd 는 잡을 돌리기 전에
`Sockets` 에 적힌 소켓 파일을 미리 만들어 둔다. 그래서 파일은 존재하는데 아무도
응답하지 않는다 — 연결하면 에러가 아니라 **무한 대기**다. `ssh` 가 멈춰 있고
`ssh-add -L` 이 영영 돌아오지 않는데 소켓은 멀쩡히 거기 있는, 진단하기 가장 나쁜
모양이 된다. 그래서 이 잡을 끄고 GnuPG 자신의 기동 경로(`gpgconf --launch`)와
GnuPG 자신의 소켓(`~/.gnupg/S.gpg-agent.ssh`)을 쓴다. `services.gpg-agent` 가 하는
나머지 일 — `gpg-agent.conf` 생성, 셸 초기화에서의 `SSH_AUTH_SOCK` — 은 그대로 다
쓴다.

세 조치가 **같은 하나의 소켓**을 가리키는 것이 핵심이다. 갈라지면 터미널에서는 되고
GUI 에서는 멈추는, 재현 조건이 이상한 버그가 된다.

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

### `xterm-ghostty` — 터미널 이름을 모르는 상대들

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

`tempo-cli`, `promtool`, `sentry-cli`, `posthog-cli`, `axiom`, `langfuse` 여섯을
**모든 기기**에 둔다 (`home/common.nix`). 코딩 에이전트가 대시보드 스크린샷을 받는
대신 텔레메트리를 직접 질의하라고 두는 것이라, `claude-code` 와 같은 층에 있다 —
에이전트는 작업이 있는 곳에서 돈다.

셋은 nixpkgs 에서 오지만 **어느 것도 이름 그대로의 attribute 가 아니다.**

- **`promtool` 은 `pkgs.prometheus` 에 없다.** 상류가 `moveToOutput bin/promtool
  $cli` 로 별도 출력에 옮겨 두어서, `pkgs.prometheus` 를 설치하면 서버와 `migrate`
  만 들어오고 정작 원한 도구는 안 들어온다. `pkgs.prometheus.cli` 로 집는다.
- **`tempo-cli` 는 잘라서 쓴다.** nixpkgs 의 `tempo` 는 `subPackages` 로 명령
  넷을 모두 빌드하는데 셋은 여기서 돌리지 않는 트레이스 저장소의 서버 쪽이다.
  `cmd/tempo-cli` 만 남기면 클로저가 237 MiB 에서 72 MiB 로 줄고, 서버로 읽히는
  `tempo` 라는 이름의 바이너리가 PATH 에서 빠진다 (`pkgs/overlay.nix`).
- **`axiom` 은 `axiom-cli` 가 아니다.** 바이너리 이름이 `axiom` 이다. attribute 는
  여기 있는 다른 CLI 옆에서 찾을 수 있게 `axiom-cli` 로 두었다.

`langfuse` 는 nixpkgs 에 없어서 직접 담았다. nixpkgs 의 `langfuse` attribute 는
파이썬 SDK 이고 그 안에는 실행 파일이 없다 — 아래 `pkgs/` 절을 보라.

### 서비스 CLI — 읽는 것에서 하는 것으로

`wrangler`, `stripe`, `agent-browser`, `gws` 넷도 같은 자리에 둔다
(`home/common.nix`). 관측 CLI 가 "무슨 일이 있었는지" 를 읽는 쪽이라면 이쪽은
에이전트가 실제로 **손을 대는** 쪽이다 — Worker 를 배포하고, 결제 이벤트를 찾고,
캘린더를 읽고, 브라우저를 몰고 다닌다.

넷 다 nixpkgs 에서 그대로 오지만 둘은 이름이 다르다.

- **`gws` 가 구글 워크스페이스 CLI 다.** 상류 이름은 `@googleworkspace/cli` 인데
  설치되는 바이너리는 `gws` 이고, nixpkgs 의 attribute 도 `gws` 다.
  `google-workspace-cli` 같은 attribute 는 없다. 구글 저장소에 있지만
  "officially supported Google product 가 아니다" 라고 스스로 명시한다.
- **`stripe-cli` 가 설치하는 바이너리는 `stripe` 다.**
- **`agent-browser` 는 테스트 러너가 아니다.** Vercel 이 에이전트가 몰도록 만든
  헤드리스 브라우저 CLI 라, `skills get core` 로 자기 사용법을 먼저 뱉는다.
  브라우저 **자체는 클로저에 없다** — nixpkgs 표현식이 크롬을 심어주지 않는다.
  기기마다 답이 다르고, 그 이야기는 아래에 따로 있다.
- **`wrangler` 는 클로저가 774 MiB 다.** 상류가 `workerd` 와 여러 플랫폼용
  `esbuild` 를 함께 담기 때문이고, 잘라낼 `subPackages` 같은 손잡이가 없다.
  `cache.nixos.org` 에서 그대로 받아오니 빌드 시간은 들지 않는다.

### agent-browser 에게 브라우저를 쥐여주는 두 가지 방법

`agent-browser` 는 크롬을 세 군데서 찾는다: `AGENT_BROWSER_EXECUTABLE_PATH`,
Playwright 캐시, 그리고 `/Applications` 밑의 네 경로 — Google Chrome, Chrome
Canary, Chromium, Brave. 마지막 것이 **하드코딩된 절대 경로**라는 게 핵심이다.

- **랩탑은 아무것도 안 해도 된다.** `google-chrome` 캐스크가 크롬을 정확히
  `/Applications/Google Chrome.app` 에 놓기 때문에 자동 탐지에 그대로 걸린다.
  `agent-browser doctor` 가 `pass Google Chrome 151.0.7922.109` 를 찍는다.
- **서버 맥은 nixpkgs 에서 받고, 경로를 손으로 알려준다**
  (`modules/roles/darwin-server.nix`). 아무도 안 쓰는 기기에 캐스크로 자동
  업데이트되는 브라우저를 둘 이유가 없어서 nixpkgs 쪽을 골랐다 — 클로저와 같이
  핀 되고, activation 중에 root 를 요구하는 `pkg` 아티팩트도 없다. 대신 nixpkgs
  는 구글 DMG 를 `/Applications` 가 아니라 `$out/Applications` 에 푼다. 스토어
  경로는 위의 네 경로 중 어느 것도 아니므로 자동 탐지가 절대 못 찾고,
  `AGENT_BROWSER_EXECUTABLE_PATH` 로 직접 가리켜야 한다.

`home.sessionVariables` 가 아니라 `environment.variables` 인 이유는 이 기기를
SSH 로 몰기 때문이다. `/etc/zshenv` 는 모든 zsh 가 읽지만 home-manager 의
세션 파일은 로그인·인터랙티브 셸만 읽는데, `ssh bhyoo-macbook-pro agent-browser …` 는 둘 다
아니다.

`doctor` 의 `Chrome` 항목은 이 환경변수를 무시하고 자동 탐지 결과만 보여준다 —
랩탑에서 환경변수를 nix 크롬으로 덮어씌워도 캐스크 경로를 계속 찍는다. 표시만
그럴 뿐 실행에는 환경변수가 이긴다: 없는 경로를 넣으면 `Launch test` 가
`Failed to launch Chrome at "…"` 로 떨어지고, nix 크롬을 넣으면 통과한다.

### 개발 도구 — 맥에만 있다

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

**플랫폼 CLI** — `gh`, `slack-cli`, `vercel-cli`. 셋 다 자기가 알아서 인증한다
(각각 키체인/`GH_TOKEN`, `slack login`, `vercel login`) 이라 계정에 관한 것은
이 레포에 하나도 없다. `gh` 가 `home/common.nix` 가 아니라 여기 있는 이유는 맥이
저장소를 만지는 기계이기 때문이고, SSH 키를 재활용하지 않는다는 점도 알아둘 만하다
— `gh` 는 HTTPS 위의 REST API 를 쓰므로 `git` 이 push 하는 자격증명과 별개다.
뒤의 둘은 nixpkgs 에서 그대로 오지 않는다 — 아래 `pkgs/` 절을 보라.

### 이 레포를 패키지 저장소로 쓰기

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
일이 없다. 제공 시스템은 `aarch64-darwin`, `aarch64-linux`, `x86_64-linux` 셋이다.

Nix 에서 "저장소" 는 AUR 처럼 중앙 집중이 아니다. 레포가 이 두 출력을 갖는 순간
그것이 곧 패키지 저장소이고, 등록 절차도 심사도 없다. 남이 **발견**하게 하려면
그때 [NUR](https://github.com/nix-community/NUR) 의 `repos.json` 에 PR 을 올리면
되는데, NUR 은 코드를 담지 않고 레포 목록만 관리한다.

### 세 기기가 같은 것을 세 번 컴파일하지 않게 — Cachix

AUR 과 정말 다른 지점은 여기다. 배포 방식이 아니라 **빌드**가 아프다.
`pkgs/` 의 여섯은 어떤 공개 캐시에도 없다 — 넷은 nixpkgs 에 존재하지 않고,
`slack-cli` 와 `tempo-cli` 는 nixpkgs 의 attribute 를 갈아끼운 것이라
`cache.nixos.org` 가 그 이름으로 빌드해 둔 것과 파생이 다르다. 그래서 기기마다
새로 컴파일한다. 나머지는 상류 캐시가 덮으므로, 올릴 가치가 있는 것은 정확히 이
여섯뿐이다. (`bun` 오버라이드도 로컬 빌드이긴 한데, 상류가 배포한 zip 을 푸는
게 빌드의 전부라 올려도 아끼는 게 없다.)

`packages.<system>` 과 `cache-push` 는 **같은 목록**이다. 후자가 전자를
`attrValues` 로 읽는다 — 한쪽에만 추가된 패키지는 조용히 모든 기기에서 다시
컴파일되는 패키지가 되기 때문이다.

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

`posthog-cli`, `axiom-cli`, `langfuse-cli`, `vercel-cli` 는 nixpkgs 에 아예 없다.
`slack-cli` 는 있는데 **다른 프로그램**이고, `tempo-cli` 는 nixpkgs 것을 잘라
쓴다. `pkgs/overlay.nix` 가 오버레이로 얹으므로, 이 디렉터리를 볼 일 없는
home-manager 모듈에서도 그냥 `pkgs.posthog-cli` 로 쓴다.

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

**langfuse-cli 는 npm 타르볼에서 가져온다.** 저장소에는 태그가 하나도 없고
`dist/` 가 `.gitignore` 에 들어 있다 — 번들은 prepublish 훅의 `bun build` 가
만든다. 체크아웃을 쓰면 npm 이 이미 배포한 파일 하나를 다시 만들자고 bun 을
빌드 의존성으로 끌어와야 하고, 버전 번호가 가리키는 것도 결국 그 타르볼이다.

npm 타르볼에는 **lock 파일이 없는데** `buildNpmPackage` 의 재현성은 `npm ci` 에서
나오고 `npm ci` 는 lock 없이는 돌기를 거부한다. 그래서 한 번 손으로 만들어
`pkgs/langfuse-cli/package-lock.json` 으로 함께 담았다. 버전을 올릴 때 둘을 같이
다시 만든다:

```sh
npm install --package-lock-only --legacy-peer-deps
nix run nixpkgs#prefetch-npm-deps -- package-lock.json   # npmDepsHash
```

`--legacy-peer-deps` 는 에러를 지우려고 붙인 것이 아니다. 유일한 의존성인 `specli`
가 `ai` 와 `zod` 를 peer 로 선언하는데, 그대로 두면 `undici` 까지 열두 개가 더
따라 들어온다. 둘은 `specli` 의 `dist/ai/tools.js` — 이 CLI 가 한 번도 로드하지
않는 별개 export — 에서만 쓰인다.

설치 검사는 `--version` 이 아니라 `api __schema` 다. 이 CLI 는 `--version` 을
아예 모르고 (도움말을 뱉으며 0 으로 끝난다), 도움말은 **아무것도 증명하지 않는다** —
번들의 유일한 런타임 import 인 `import.meta.resolve("specli")` 는 로드 시점이 아니라
api 서브커맨드가 돌 때 풀리므로, `node_modules` 가 통째로 없어도 도움말은 멀쩡히
나온다. 그게 바로 이 패키지가 깨질 수 있는 지점이다. `api __schema` 는 그 import 를
지나가는 가장 싼 명령이고, 스펙을 타르볼에 담긴 `openapi.yml` 에서 읽으므로 자격
증명도 샌드박스에 없는 네트워크도 필요 없다.

**vercel-cli 도 npm 타르볼에서 가져온다.** nixpkgs 에는 어떤 이름으로도 없다 —
`vercel` 도 `vercel-cli` 도 없고, 가장 비슷한 `vercel-pkg` 는 이름만 바뀐
zeit/pkg 번들러로 무관하다. 타르볼을 고른 이유는 langfuse-cli 와 같다: 저장소가
모노레포이고 `files` 가 `["dist"]` 이라, 배포된 것이 곧 prepublish 가 만든 번들이고
버전 번호가 가리키는 것도 그것이다.

까다로운 쪽은 의존성 트리이고, 패키지 옆에 `package.json` 과 `package-lock.json`
**둘 다** 들어 있는 게 그 결과다.

npm 타르볼에 lock 이 없다는 것까지는 langfuse-cli 와 같은데, 여기서는 배포된
manifest 그대로는 lock 을 만들 수조차 없다. devDependencies 셋이 애초에 배포된 적
없는 워크스페이스 패키지라 `npm install --package-lock-only` 가 레지스트리 404 에서
멈춘다. `--omit=dev` 도 답이 아니다 — lock 은 설치할 것이 아니라 **이상적인 트리
전체**를 적기 때문이다. 어차피 여기서는 아무것도 컴파일하거나 테스트하지 않으므로
필요도 없다.

`optionalDependencies` 는 이유가 다르다. 같은 네이티브 바이너리를 플랫폼별로 넷
빌드해 둔 것이고 하나가 약 68 MB 인데, `prefetch-npm-deps` 는 이 플랫폼 것인지와
무관하게 lock 의 모든 항목을 받아온다. `dist/vc.js` 의 shim 은 사용자가 명시적으로
켰을 때만 그중 하나를 JS CLI 보다 우선하므로, 빼도 기본 경로는 그대로이고 클로저가
270 MB 가벼워진다.

**그 편집이 lock 을 읽기 전에 끝나야 하고, 그건 곧 `postPatch` 안이어야 한다는
뜻이다.** `buildNpmPackage` 는 의존성 캐시를 두 번째 fixed-output 파생에서 만드는데
그쪽은 `src` 와 `postPatch` 만 공유하고 빌드 인풋은 하나도 못 받는다. 게다가
`npmConfigHook` 은 자기를 `postPatchHooks` 에 덧붙이므로 `preConfigure` 는
자기가 준비해 주려던 `npm ci` **다음에** 돈다. 이미 편집된 manifest 를 복사해
넣는 방식은 두 파생 모두에서 동작하고 둘 다 아무 도구도 필요 없다. 다시 만드는
절차는 패키지 안에 적어 두었다.

설치 검사가 `--version` 이 아니라 `vercel telemetry status` 인 것도 같은 종류의
이유다. 버전은 shim 이 아무것도 로드하기 전에 답하므로 `node_modules` 가 통째로
없어도 통과한다 — 위의 이야기가 전부 node_modules 에 무엇을 넣느냐였다는 걸
생각하면, 그게 바로 잡아야 할 고장이다.

**slack-cli 는 이름을 뺏긴 경우다.** nixpkgs 의 `slack-cli` 는
rockymadden/slack-cli — 2023년 2월에 마지막으로 손댄, incoming webhook 에 글을
올리는 bash 스크립트다. 오늘 "Slack CLI" 라고 하면 slackapi/slack-cli, Slack 앱을
만들고 돌리고 배포하는 Go 프로그램을 말한다. **둘 다 `slack` 이라는 바이너리를
설치하므로 잘못 고르는 것은 빌드 실패가 아니다** — 한참 뒤에 `slack app` 이 인자를
모른다고 답하는 형태로 나타난다. 그래서 오버레이는 새 이름을 만드는 대신 attribute
자체를 갈아끼운다.

빌드에 일러줘야 하는 것이 넷인데, 넷 다 빠뜨리면 시끄럽게가 아니라 조용히 어긋난다.

- **버전은 ldflags 로 박는다.** 상류는 `git describe` 에서 읽는데 받아온 타르볼은
  그 질문에 답할 수 없고, 폴백이 `v0.0.0-dev` 다 — 영원히 업그레이드하라고 잔소리하고
  `slack version` 에도 거짓을 말하는 바이너리가 된다. 설치 검사가 그 명령을 실행해
  진짜 버전을 찾으므로, 상류가 import 경로를 옮기면 도장이 조용히 썩지는 않는다.
- **Go 는 바이너리 이름을 모듈 경로에서 짓는다** — `slack-cli` 가 나온다. 상류의
  Makefile 도 Homebrew 도 문서도 전부 `slack` 이라, 설치할 때 이름을 바꾼다.
- **테스트와 설치 검사에 각각 임시 HOME 을 준다.** 이 CLI 는 무엇을 하기 전에 먼저
  `~/.slack` 을 여는데 샌드박스에는 홈 디렉터리가 없다. `git` 이 테스트 인풋인 것도
  같은 모양의 이유다 — `cmd/doctor` 의 테스트가 실제 도구들에게 버전을 묻고, 그중
  git 은 꼭 찾아야 한다고 고집한다.
- **빌드 동안은 텔레메트리를 끈다.** 안 그러면 위의 두 번의 실행이 네트워크 없는
  샌드박스에서 Slack 에 자기를 보고하려 든다. 빌드 환경에 한정된 이야기이고, 설치된
  바이너리가 무엇을 보고할지는 사용자 몫으로 남는다.

셸 완성은 바이너리 자신에게서 받는다 — Cobra 가 등록해 두고 숨겨 놓은 `completion`
서브커맨드다.

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
패키지를 가린다. 검증: 랩탑에서 `librewolf.pname`은 `Librewolf`(오버레이),
서버 맥에서는 `librewolf`(nixpkgs).

**기기 전용** (`hosts/<name>/`) — 정말 그 기계에만 해당하는 것. 지금은
`hostPlatform`과 서버의 `hardware-configuration.nix`뿐이다.

세 층 어디에도 안 맞는 것은 `extraModules` / `extraHomeModules`로 넘긴다 —
한 기계가 미디어 서버를 겸하는 식의 경우.

## 설계 메모

### switch 가 비밀번호를 두 번 묻던 이유

`sudo darwin-rebuild switch` 로 한 번 인증했는데 brew 차례에서 또 묻는 일이
있었다. 버그가 아니라 권한이 한 번 내려갔다 다시 올라오기 때문이다.

1. activation 전체가 **root** 로 돈다.
2. 그런데 Homebrew 는 root 로 도는 것을 거부하므로, nix-darwin 이 brew 단계에서
   일부러 사용자로 **내려간다**:
   `sudo --preserve-env=PATH --user=bhyoo --set-home env brew bundle …`
3. 캐스크 중 아티팩트가 `app` 이 아니라 `pkg` 인 것들은 `/usr/sbin/installer` 를
   root 로 불러야 한다. 지금 선언된 것 중에는 `cloudflare-warp` 과 `zoom` 둘이다.
   그래서 사용자로 내려간 Homebrew 가 **sudo 를 다시 부른다**.
4. root 의 권한은 강등된 자식에게 흘러내리지 않고, 1번의 sudo 타임스탬프는
   수명이 5분(sudoers(5) `timestamp_timeout` 기본값)이라 빌드가 그 시간을
   넘긴다.

그래서 **brew 가 할 일이 있을 때만** 묻는다. 할 일이 없으면 sudo 를 아예 안
부른다. `onActivation.upgrade` 가 켜져 있어 저 두 캐스크가 새 버전을 낼 때마다
걸린다.

두 곳을 고쳤고, 둘은 다른 질문에 답한다.

- **얼마나 자주 뜨는가** — `security.sudo.extraConfig` 의
  `Defaults timestamp_timeout=30` (`modules/darwin.nix`, 모든 맥). 리빌드
  하나를 덮되 하루 종일 인증된 채로 두지는 않는 길이다. 기록은 터미널 단위라
  (`timestamp_type` 기본값 `tty`) 다른 세션에 창을 열어주지 않는다.
- **떴을 때 무엇을 하는가** — `security.pam.services.sudo_local` 의
  `touchIdAuth` + `reattach` (`modules/roles/darwin-laptop.nix`, 랩탑만).
  지문 센서가 필요한 설정이라 SSH 로 닿는 헤드리스 미니에는 의미가 없다.
  `reattach`(pam_reattach)를 같이 켜는 이유는 pam_tid 가 사용자 bootstrap 세션
  안에서만 프롬프트를 그릴 수 있어서다 — tmux 안의 셸이 그 밖이고, root 에서
  `sudo --user=bhyoo` 로 들어가는 brew 단계도 그 밖이다. `auth optional` 줄이라
  필요 없는 곳에서는 비용이 없다.

nix-darwin 이 쓰는 `/etc/pam.d/sudo_local` 은 애플이 macOS 14 에서 **로컬 수정이
시스템 업데이트를 넘어 살아남으라고** 추가한 파일이다. `/etc/pam.d/sudo` 자체는
봉인된 볼륨에 있고 이 파일을 include 한다.

sudoers 파일은 문법이 틀리면 sudo 전체가 막히므로, 병합된 결과를
`visudo -c -f` 로 검증하고 나서 넣었다 — nix-darwin 은
`/etc/sudoers.d/10-nix-darwin-extra-config` 하나에 terminfo 용 `env_keep` 줄과
위의 `Defaults` 를 같이 쓴다.

NOPASSWD 규칙은 쓰지 않았다. 프롬프트는 사라지지만 그건 인증 정책을 통째로 내리는
것이라 질문에 대한 답이 아니다.

### 전원 연결 중에만 뚜껑을 닫아도 안 자게

서버 맥은 MacBook Pro 를 뚜껑 닫고 SSH 로만 쓰는 기계다. 요구는 처음부터
조건부였다 — **어댑터에 물려 있는 동안만** 클램쉘. 전원이 끊기면 다시 랩탑처럼
자야 한다. 배터리로도 안 자는 기계는 뚜껑 닫은 채 방전으로 끝나고, 그 뒤로는
아예 꺼진 기계다.

**유휴 타이머는 전원별로 쓸 수 있다.** macOS 에 그 옵션이 있다 — 시스템 설정 →
디스플레이 → 고급의 "디스플레이가 꺼져 있을 때 전원 어댑터 사용 시 컴퓨터를
자동으로 잠자지 않게 하기"(벤투라 이전에는 배터리 → 옵션에 있었다)이고, 실체는
`pmset -c sleep 0` 이다.
`-c` 가 어댑터 딕셔너리, `-b` 가 배터리 딕셔너리라 둘을 따로 쓴다:

```nix
/usr/bin/pmset -c sleep 0 disksleep 0 displaysleep 10
/usr/bin/pmset -b sleep 10 disksleep 10 displaysleep 2
```

nix-darwin 의 `power.sleep.*` 을 여기서 안 쓰는 이유가 이것이다. 그 옵션들은
`systemsetup -setComputerSleep` 계열을 모는데, 값을 하나만 받고 전원이라는 축이
아예 없다. 어댑터와 배터리가 달라야 한다는 게 이 역할의 전부라서 pmset 을 직접
쓴다. `ttyskeepawake` 는 기본으로 켜져 있고 살아 있는 SSH 세션을 활동으로 세므로,
배터리 타이머가 작업 중인 세션을 끊지는 않는다.

**뚜껑은 그 타이머가 안 덮는다.** 닫는 것은 잠들기로 가는 별개의 경로다 — 리드
스위치가 `IOPMrootDomain` 에 직접 잠들라고 하므로 `sleep 0` 인 기계도 뚜껑이
본체에 닿는 순간 내려간다. `caffeinate` 도 답이 아니다. 그건 power assertion 을
잡는데, assertion 을 참조하는 것은 리드 스위치가 아니라 유휴 타이머다. 애플의 정식
클램쉘 모드는 **외장 디스플레이 + 전원 + 입력장치**가 전제인데 이 기계는 셋 다 없다.

남는 것이 `SleepDisabled` 다. `IOPMrootDomain` 이 리드를 포함한 **모든** 출처의
잠들기에 대한 거부권으로 취급하는 커널 플래그이고, 세우는 방법은
`pmset -a disablesleep 1` 하나뿐이다 — nix-darwin 옵션도 없고 man page 에도 없다.
그리고 **이것만은 전원별 형태가 없다.** 보통의 pmset 설정은 전원별 딕셔너리에
들어가는데(`pmset -g cap` 이 각 전원이 받는 목록을 찍고, `disablesleep` 은 어느
쪽에도 없다), `SleepDisabled` 는
`/Library/Preferences/com.apple.PowerManagement.plist` 의 `SystemPowerSettings`
아래 단일 키다. `pmset -c disablesleep 1` 도 받아들여지지만 똑같은 전역 키를 쓴다 —
`-c` 는 장식이다.

그래서 조건을 **선언하는 대신 지켜본다.** `launchd.daemons.clamshell-on-power` 가
`pmset -g pslog` 를 따라간다. 이건 이벤트 스트림이라 시작할 때 현재 전원을 한 줄
찍고 그 뒤로는 바뀔 때마다 `Now drawing from 'X'` 한 줄씩만 나오고, 파이프를
통과해도 줄 단위로 흘러서 폴링할 것이 없다. 어댑터면 1, 아니면 0.

두 가지가 덜 자명하다.

- **배터리로 떨어질 때 이미 뚜껑이 닫혀 있으면** 명시적으로 재워야 한다. 거부권을
  내리는 것은 거부권을 내리는 것일 뿐, 그 거부권이 삼킨 리드 이벤트를 다시
  보내주지는 않는다. 그래서 `AppleClamshellState` 를 `ioreg` 로 확인하고
  `pmset sleepnow` 를 부른다.
- **시작 시 호출은 그걸 하지 않는다.** 방금 설치된 데몬이 제일 하면 안 되는 일이
  자기를 설치한 `switch` 도중에 기계를 재우는 것이다.

값을 먼저 읽는 것은 최적화가 아니다 — pmset 은 같은 값을 다시 써도 불평하지
않는다. [할 일이 없으면 아무 말도 하지 않는다](#activation-이-말을-거는-기준)
는 규칙 때문이다. 플래그가 꺼져 있는 동안 `pmset -g` 는 그 줄을 아예 빼므로, 빈
결과는 "모름"이 아니라 0 으로 읽어야 한다.

**남는 위험 하나.** 일단 잠들면 데몬도 같이 자므로, 어댑터가 돌아왔을 때 깨우는
것은 macOS 몫이다. 그걸 정하던 `acwake` 는 애플 실리콘에서 죽은 설정이라
(`pmset -g cap` 에 없고 써도 안 먹는다) 동작이 기종에 박혀 있다. 이 기계가 어댑터로
안 깨는 쪽이면, 배터리 타이머보다 긴 정전은 사람이 뚜껑을 열어야 끝난다. 전원이
아예 나갔다 들어온 경우는 위의 `restartAfterPowerFailure` 가 받는다.

데몬이 조용히 죽어서 뚜껑 뒤에서 기계가 자고 있는 것이 볼 수 있어야 할 실패라서,
stderr 는 `/var/log/clamshell-on-power.err.log` 로 남는다. 정상이면 비어 있다.

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

### activation 이 말을 거는 기준

activation 스크립트와 여기서 만든 커맨드(`gpg-ssh-authorize` 등)는 **사람이
직접 해야만 끝나는 일이 남았을 때만** 출력한다. GPG 키가 없다, service token 이
없어서 브라우저 등록이 필요하다, plist 를 못 읽어서 건너뛰었다 — 이런 것들이다.

"configuring keyboard shortcuts..." 류의 진행 상황 보고와, 스크립트가 알아서
처리한 변경의 통보는 넣지 않는다. switch 할 때마다 같은 줄이 지나가면 읽지 않게
되고, 그러면 정작 읽어야 할 한 줄도 같이 흘러간다. 성공하면 조용한 쪽이 유닉스
관례이기도 하다.
