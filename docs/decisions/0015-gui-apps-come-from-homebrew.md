# 0015. GUI 앱은 nixpkgs 가 아니라 Homebrew 에서

**결정** — 데스크톱 앱은 cask 로 깐다. 예외 목록은
[레퍼런스 · GUI 앱](../reference.md#gui-앱).

대부분은 nixpkgs에 darwin 빌드가 아예 없고, 있는 것도 특권 구성요소가 빠진 앱
번들 복사본이다. `onActivation.upgrade`가 켜져 있어 최신 유지도 Homebrew가 한다.

**실체가 시스템 서비스인 패키지는 스토어에서 설치할 수 없다.** WARP 이 그 전형이다.
nixpkgs도 `cloudflare-warp`를 aarch64-darwin으로 빌드하지만, darwin 분기는 `.pkg`
payload에서 `Cloudflare WARP.app`만 꺼내 복사하고 `warp-cli`를 심볼릭 링크할 뿐이다.
정작 클라이언트가 올라타는 특권 데몬
`/Library/LaunchDaemons/com.cloudflare.1dot1dot1dot1.macos.warp.daemon.plist`는
`.pkg` 자신이 설치하고, 그 `.pkg`를 실제로 실행하는 건 cask뿐이다.
Karabiner 도, 1Password 데스크톱 앱도 같은 모양의 문제다 — 후자는 브라우저 연동과
SSH 에이전트 통합이 시스템에 걸린다.

Nix에서 오는 GUI 예외는 Firefox와 서버 맥의 Orca·Camoufox·DeskPad·macVNC다.
Firefox는 오버레이가 주는 `.app` 번들이라
[정책을 두 경로로](0021-firefox-policies-two-paths.md) 넣어야 한다. 서버 Orca는
현재 `serve` 회귀를 피하려고 마지막 검증 릴리스를 고정한다
([0028](0028-orca-runtime-on-the-server-mac.md)). 나머지 세 앱은 고정한
브라우저/VNC 스택이라 Nix로 패키징한다. Camoufox와 DeskPad는 LaunchAgent가
store에서 직접 실행하고, Screen Recording과 Accessibility 권한이 필요한 macVNC만
Home Manager Apps의 안정된 경로로 실행한다
([0031](0031-camofox-native-macos-over-wireguard.md)).
