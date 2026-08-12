# nix config

`bhyoo`의 기기 전부를 담는 단일 flake. macOS 두 대와 NixOS 서버 한 대.

레포를 하나로 두는 이유는 `flake.lock` 이다 — lock 하나가 nixpkgs 리비전부터
home-manager, llm-agents 까지 전부 고정한다
([0001](docs/decisions/0001-single-repo-single-lock.md)).

## 이미 올라간 기기에서

```sh
# 맥 (해당 기기에서). 기기 이름을 칠 일이 없다
sudo darwin-rebuild switch --flake ~/nix-config
sudo darwin-rebuild switch                      # 레포가 /etc/nix-darwin 일 때

# 서버 (해당 기기에서)
sudo nixos-rebuild switch --flake ~/nix-config#server

# 서버 (맥에서 원격으로). --build-host 를 같이 주는 것이 핵심이다:
# 맥은 aarch64-darwin 이라 aarch64-linux 파생물을 realise 할 수 없다.
nixos-rebuild switch --flake ~/nix-config#server \
  --target-host root@server --build-host root@server
```

맥이 이름을 안 받는 것은 `darwin-rebuild` 가 `scutil --get LocalHostName` 을
속성 이름으로 쓰기 때문이다 — 그래서 [부트스트랩 3번](#맥)이 이름을 세운다
([0005](docs/decisions/0005-hostname-selects-the-configuration.md)).
`nixos-rebuild` 는 이 편의가 없어서 서버만 `#server` 를 붙인다.

레포 경로는 기기마다 달라도 된다. flake 경로는 `--flake` 로 지정하는 값일 뿐이라
설계에 영향이 없다.

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
   기계를 헷갈리므로 같이 세운다
   ([0005](docs/decisions/0005-hostname-selects-the-configuration.md)).
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

   # 여기서 nix.custom.conf 를 비켜둔다. 이 자리는 activation 이 선언된 내용으로
   # 다시 채우는데, nix-darwin 은 내용을 알아보지 못하는 /etc 파일을 덮어쓰지
   # 않고 중단한다 — 4번을 했다면 확실히 그렇게 된다. 지우는 게 아니라 이름만
   # 바꾸는 것이고, 빌드는 위에서 이미 끝났으므로 캐시 설정도 제 몫을 다했다.
   sudo mv /etc/nix/nix.custom.conf{,.before-nix-darwin}

   sudo ./result/sw/bin/darwin-rebuild switch --flake .
   ```
   업스트림이 안내하는 `sudo nix run nix-darwin/master#darwin-rebuild -- switch` 도
   되지만 그건 nix-darwin 을 **master 에서** 끌어온다. 위 방식은 `flake.lock` 에
   핀 고정된 리비전을 쓰므로 두 번째 switch 부터와 같은 버전이다.
6. **App Management 권한 승인.** `home.stateVersion >= 25.11`이라
   `targets.darwin.copyApps`가 켜져 있고 Firefox.app을
   `~/Applications/Home Manager Apps/`로 복사한다. 거부하면 activation이 실패한다.
   시스템 설정 → 개인정보 보호 및 보안 → 앱 관리.
7. **GPG 키 가져오기.** 커밋 서명과 SSH 인증이 둘 다 이 키를 쓰므로 없으면 둘 다
   먹통이다. activation 이 없다는 걸 알아채고 절차를 그 자리에서 안내한다 —
   [운영 · GPG 키 가져오기](docs/operations.md#gpg-키-가져오기) 와 같은 내용이다.
8. **App Store 전용 앱 두 개** — 랩탑만. KakaoTalk 과 WireGuard 는 손으로 깐다
   ([0016](docs/decisions/0016-mas-only-apps-installed-by-hand.md)).
9. **WARP service token** — 서버 역할의 맥만.
   [운영 · WARP service token](docs/operations.md#warp-service-token).

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

lock 은 공유 상태다 — 한 기기에서 갱신하고 나머지는 pull 한다
([운영 · 기기 간 독립성](docs/operations.md#기기-간-독립성)).

flake 밖에서 관리되는 것:

- **Nix 자체 (맥)** — `sudo determinate-nixd upgrade`
- **Homebrew** — `onActivation.{upgrade,autoUpdate}`가 켜져 있어 switch 때 같이 올라간다

## 문서

- **[docs/reference.md](docs/reference.md)** — 무엇이 어디에 있나. 디렉터리 구조,
  층별 배분, 설치되는 CLI·앱 목록, 단축키 표, `pkgs/`, 이 레포를 인풋으로 쓰기.
- **[docs/operations.md](docs/operations.md)** — 손으로 하는 절차. GPG 키 반입,
  WARP service token, 캐시 푸시, 기기 간 독립성.
- **[docs/decisions/](docs/decisions/)** — 왜 이렇게 됐나. 결정 하나에 파일 하나.
