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
  darwin.nix         맥 두 대 공통
  nixos.nix          NixOS 공통
hosts/             기기 고유
  bhyoo-macbook-air/
  bhyoo-mac-mini/
  server/            + hardware-configuration.nix
home/              사용자 레벨 (home-manager)
  common.nix         모든 기기 공통 — 설정의 대부분이 여기 있다
  darwin.nix         맥 전용
  linux.nix          NixOS 전용
```

축이 둘(기기 × 목적)인데 상속이 아니라 **조합**으로 푼다. 모든 설정은
`common + platform + host + roles`이고, 조합 지점은 `flake.nix` 한 곳뿐이다.

역할을 추가하려면 모듈 파일을 만들고 `flake.nix`에서 넘긴다:

```nix
"bhyoo-mac-mini" = mkDarwin {
  hostname = "bhyoo-mac-mini";
  extraModules = [ ./modules/roles/media-server.nix ];
  extraHomeModules = [ ./home/roles/media-server.nix ];
};
```

다른 기기는 아무것도 모른 채로 남는다.

## 기기별 명령

속성 이름은 각 기기의 호스트명과 같다. 이름이 맞으면 속성을 생략해도 되고,
아니면 명시한다.

```sh
# 맥 (해당 기기에서)
sudo darwin-rebuild switch --flake ~/nix-config#bhyoo-macbook-air
sudo darwin-rebuild switch --flake ~/nix-config#bhyoo-mac-mini

# 서버 (해당 기기에서)
sudo nixos-rebuild switch --flake ~/nix-config#server

# 서버 (맥에서 원격으로 — aarch64 리눅스 빌더가 필요하다)
nixos-rebuild switch --flake ~/nix-config#server --target-host root@server
```

레포 경로는 기기마다 달라도 된다. flake 경로는 `--flake`로 지정하는 값일 뿐이라
설계에 영향이 없다.

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

`home/darwin.nix`에서 `let policies = ...`로 한 번만 정의해 양쪽에 `inherit`한다.
Linux 데스크톱이 생기면 같은 `policies`를 `pkgs.firefox`에 그냥 넘기면 된다 —
"같은 옵션, 다른 구현"의 전형적인 사례다.

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
