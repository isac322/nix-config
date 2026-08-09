# nix-darwin configuration

`bhyoo`의 macOS(aarch64) 시스템 설정. Nix 자체는 **Determinate Nix**가 소유하고,
nix-darwin은 그 위의 시스템/사용자 설정만 담당한다.

| 파일 | 내용 |
|---|---|
| `flake.nix` | 인풋 핀, `darwinConfigurations.{default,bhyoo-macbook-air}` |
| `configuration.nix` | 시스템 레벨 (Determinate, 오버레이, Homebrew, macOS defaults) |
| `home.nix` | home-manager 사용자 레벨 (패키지, git, zsh, Firefox) |

## 새 기계에 올리기

선언적으로 되지 않는 부트스트랩 단계가 남아 있다. 순서대로.

### 1. Determinate Nix 설치

nix-darwin 모듈은 Determinate Nix를 **설치해주지 않는다**. macOS는 그래픽 설치
프로그램을 쓴다: <https://install.determinate.systems/determinate-pkg/stable/Universal>

### 2. 이 저장소를 `/etc/nix-darwin`에 배치

```sh
sudo git clone <remote> /etc/nix-darwin
sudo chown -R "$(id -un):staff" /etc/nix-darwin
```

### 3. 바이너리 캐시 부트스트랩 (선택, 강력 권장)

첫 `switch`는 아직 `nix.custom.conf`가 적용되기 전에 빌드를 수행한다. 이 단계를
건너뛰면 `omp`(oh-my-pi)를 소스에서 빌드한다 — Rust 툴체인 + zig 461 MiB를 받고
cargo vendor부터 전부 컴파일한다.

```sh
printf '\nextra-substituters = https://cache.numtide.com\nextra-trusted-public-keys = niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g=\n' \
  | sudo tee -a /etc/nix/nix.custom.conf
sudo launchctl kickstart -k system/systems.determinate.nix-daemon
```

activation이 같은 내용을 선언적으로 다시 깔아주므로, 이후에는 신경 쓸 필요 없다.

### 4. 첫 switch

```sh
sudo darwin-rebuild switch --flake /etc/nix-darwin#default
```

`#default`를 쓰는 이유: `darwin-rebuild`는 속성을 생략하면
`darwinConfigurations.$(scutil --get LocalHostName)`을 찾는다. 기계 이름에 의존하지
않도록 `default` 별칭을 둔다.

### 5. App Management 권한 승인

`home.stateVersion >= 25.11`이라 `targets.darwin.copyApps`가 켜져 있고, Firefox.app을
`~/Applications/Home Manager Apps/`로 **복사**한다. 첫 activation 때 터미널에 권한
요청이 뜬다. 거부하면 activation이 실패한다.
시스템 설정 → 개인정보 보호 및 보안 → 앱 관리.

### 6. 확인

```sh
claude --version                       # 최신 (llm-agents 경유)
omp --version                          # oh-my-pi
defaults read org.mozilla.firefox      # EnterprisePoliciesEnabled, DisableAppUpdate
```

Firefox를 실행해 `about:policies`에서 정책이 활성인지, `about:preferences`의 업데이트
섹션이 사라졌는지 본다.

## 일상 업데이트

패키지 버전은 전부 `flake.lock`에 핀돼 있다. lock을 갱신해야 올라간다.

```sh
sudo nix flake update --flake /etc/nix-darwin              # 전체
sudo nix flake update nixpkgs --flake /etc/nix-darwin      # 특정 인풋만
sudo darwin-rebuild switch --flake /etc/nix-darwin#default
```

flake 밖에서 관리되는 것:

- **Nix 자체** — `sudo determinate-nixd upgrade`
- **Homebrew** — `homebrew.onActivation.{upgrade,autoUpdate}`가 켜져 있어 switch 때 같이 올라간다

## 설계 메모

### Nix 설정은 왜 nix-darwin이 아니라 Determinate가 소유하나

nix-darwin의 nix 모듈은 Nix 패키지, `/etc/nix/nix.conf`, `org.nixos.nix-daemon`
launchd 데몬을 관리하려 한다. 이 시스템에서는 셋 다 Determinate Nix
(`systems.determinate.nix-daemon`)가 이미 소유하고 있어 정면으로 충돌한다.
그래서 `determinateNix.enable = true`로 `nix.enable`을 강제로 끄고, Determinate가
`nix.conf`에 남겨둔 `!include nix.custom.conf` 확장 지점만 `customSettings`로 채운다.

### Firefox 정책을 두 경로로 넣는 이유

`firefox-bin`은 `nixpkgs-firefox-darwin` 오버레이가 제공하는 순수 `.app` 번들이라
home-manager가 wrap할 수 없다. 그래서 정책을 두 군데에 넣는다.

1. 번들 안 `Contents/Resources/distribution/policies.json` — 오버레이의 `extraFiles`
2. `~/Library/Preferences/org.mozilla.firefox.plist` — home-manager의 `policies`

`home.nix`에서 `let policies = ...`로 한 번만 정의해 양쪽에 `inherit`한다.

### `follows`를 일부러 안 붙인 인풋

- `llm-agents` — `shared-nixpkgs` 오버레이가 `bun`을 자기 nixpkgs에서 고정한다.
  follows를 걸면 세트 전체의 store path가 바뀌어 캐시가 전부 빗나간다.
- `determinate` — upstream이 FlakeHub 캐시 미스를 이유로 권장하지 않는다.

### `environment.etc."nix/nix.custom.conf".knownSha256Hashes`

Determinate 설치 프로그램이 만들어둔 `nix.custom.conf`를 determinate 모듈이 덮어쓰려
하는데, nix-darwin은 정체불명 파일을 만나면 activation을 중단한다. 설치 프로그램이
쓴 파일의 해시를 화이트리스트에 넣어 첫 activation이 통과하게 한다. 설치 옵션이
다르면 해시도 달라지므로, 그때는 새 해시를 목록에 추가한다.
