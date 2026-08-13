# 0016. App Store 전용 앱 둘은 손으로 깐다

**결정** — KakaoTalk 과 WireGuard 는 선언에서 뺀다. `homebrew.masApps` 도 쓰지
않는다.

둘 다 Mac App Store 전용이라 **선언적으로 설치할 방법이 없다.**

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

## 그 뒤

서버 역할의 맥은 WireGuard 앱을 아예 안 쓰게 됐다. 위의 두 문장은 그대로 참이고,
달라진 것은 화면 없는 기계가 그 앱을 원하지 않는다는 쪽이다 —
[0029](0029-wireguard-as-a-daemon-on-the-server-mac.md).

설치돼 있어야 하는 기계에 없을 때는 switch 가 매번 알린다
([0025](0025-activation-speaks-only-when-needed.md)). 선언은
`local.masApps` 이고 구현은 `modules/mas-apps.nix` 에 있다.
