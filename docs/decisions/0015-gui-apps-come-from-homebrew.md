# 0015. GUI 앱은 nixpkgs가 아니라 Homebrew에서

**결정** — 데스크톱 앱은 cask로 설치한다. 예외 목록은
[레퍼런스 · GUI 앱](../reference.md#gui-앱)에 둔다.

대부분은 nixpkgs에 Darwin 빌드가 없고, 있는 것도 특권 구성요소가 빠진 앱 번들
복사본이다. `onActivation.upgrade`가 켜져 있어 최신 유지도 Homebrew가 맡는다.

**실체가 시스템 서비스인 패키지는 store에서 설치할 수 없다.** WARP가 그 전형이다.
nixpkgs도 `cloudflare-warp`를 aarch64-darwin으로 빌드하지만, Darwin 분기는 `.pkg`
payload에서 `Cloudflare WARP.app`만 꺼내 복사하고 `warp-cli`를 심볼릭 링크할 뿐이다.
정작 클라이언트가 올라타는 특권 데몬
`/Library/LaunchDaemons/com.cloudflare.1dot1dot1dot1.macos.warp.daemon.plist`는
`.pkg` 자신이 설치하고, 그 `.pkg`를 실제로 실행하는 건 cask뿐이다.
Karabiner와 1Password 데스크톱 앱도 같은 문제가 있다. 1Password는 브라우저
연동과 SSH 에이전트 통합이 시스템에 걸린다.

Nix에서 오는 GUI 예외는 Firefox와 Camoufox·DeskPad다. Firefox는 오버레이가 주는
`.app` 번들이라 [정책을 두 경로로](0021-firefox-policies-two-paths.md) 넣어야 한다.
Camoufox와 DeskPad는 고정한 상류 앱을 LaunchAgent가 Nix store에서 직접 실행한다.
DeskPad는 `local.camofox.virtualDisplay = true`인 MBP에서만 1920×1080 Aqua
가상 디스플레이를 만든다
([0031](0031-deskpad-virtual-display-on-clamshell-macos.md)).

RustDesk는 두 Mac 모두 Homebrew cask로 설치한다. 관리 대상 aarch64-linux NixOS
server의 클라이언트는 `pkgs.rustdesk-flutter`로 설치한다. Direct IP host는
서버 역할의 MBP만 실행한다.
