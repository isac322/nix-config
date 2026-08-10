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

`home/darwin.nix`에서 `let policies = ...`로 한 번만 정의해 양쪽에 `inherit`한다.
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
