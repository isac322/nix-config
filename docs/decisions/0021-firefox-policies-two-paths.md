# 0021. Firefox 정책을 두 경로로 넣는 이유

**결정** — 같은 `policies` 를 번들 안과 사용자 도메인 양쪽에 넣는다.

`firefox-bin`은 오버레이가 제공하는 순수 `.app` 번들이라 home-manager가 wrap할 수
없다. 그래서 정책을 두 군데에 넣는다.

1. 번들 안 `Contents/Resources/distribution/policies.json` — 오버레이의 `extraFiles`
2. `~/Library/Preferences/org.mozilla.firefox.plist` — home-manager의 `policies`

`home/roles/darwin-laptop.nix`에서 `let policies = ...`로 한 번만 정의해 양쪽에
`inherit`한다.
Linux 데스크톱이 생기면 같은 `policies`를 `pkgs.firefox`에 그냥 넘기면 된다 —
"같은 옵션, 다른 구현"의 전형적인 사례다.
