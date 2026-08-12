# 0003. 맥에서는 nix-darwin 이 Nix 를 소유하지 않는다

**결정** — 맥에서 `nix.enable` 을 끄고 Determinate Nix 에 맡긴다. NixOS 에서는
`nix.settings` 를 그대로 쓴다.

nix-darwin의 nix 모듈은 Nix 패키지, `/etc/nix/nix.conf`,
`org.nixos.nix-daemon` launchd 데몬을 관리하려 한다. 맥에서는 셋 다 Determinate
Nix(`systems.determinate.nix-daemon`)가 이미 소유하고 있어 정면으로 충돌한다.
그래서 `determinateNix.enable = true`로 `nix.enable`을 강제로 끄고, Determinate가
`nix.conf`에 남겨둔 `!include nix.custom.conf` 확장 지점만 `customSettings`로 채운다.

NixOS에는 이 문제가 없다. Nix가 시스템 클로저의 일부라서 `nix.settings`로 직접
쓴다. 같은 캐시 설정이 플랫폼마다 다른 옵션 경로로 들어가는 이유이고,
`lib/caches.nix`가 모듈이 아니라 순수 데이터인 이유다.

## 따라오는 것 — 첫 activation 의 `nix.custom.conf`

이 구도는 부트스트랩에 걸림돌을 하나 남긴다. determinate 모듈이 설치 프로그램의
`nix.custom.conf` 를 자기가 만든 것으로 바꾸려 하는데, nix-darwin 은 내용을
알아보지 못하는 `/etc` 파일을 덮어쓰지 않고 `exit 2` 로 activation 을 중단한다.
사용자가 직접 넣은 설정을 말없이 날리지 않으려는 장치다.

이 검사는 **파일이 아직 `/etc/static/…` 심링크가 아닐 때만** 돈다. 즉 기계마다
첫 switch 한 번만 걸리고, 넘겨받은 뒤로는 영구히 통과한다.

받는 방법이 둘인데 후자를 골랐다.

- `environment.etc."nix/nix.custom.conf".knownSha256Hashes` 에 설치 프로그램이
  쓴 파일의 해시를 넣는다. 설치 버전마다 내용이 달라서 목록을 계속 덧붙여야 하고,
  그 목록은 업스트림을 따라다녀야 한다. nix-darwin 도 같은 목록을 갖고 있지만
  우리에게는 안 닿는다 — 그 사본은 nix 모듈의 `handleUnmanaged` 뒤에 있고
  `nix.enable = false` 가 그 가지를 통째로 끈다.
- **첫 switch 직전에 파일을 옆으로 치운다** (README 맥 5번). 검사할 대상이
  사라지므로 유지할 목록도 없다. 잃는 것도 없다. 삭제가 아니라 개명이라 원본은
  남고, 어차피 이 모듈이 같은 파일을 선언으로 다시 만든다.

캐시 부트스트랩(맥 4번)이 이 파일에 `tee -a` 로 덧붙이기 때문에 후자는 선택이
아니라 필수에 가깝다 — 그 단계를 거치면 해시는 어떤 검증값과도 맞지 않는다.
치우는 시점이 `nix build` 와 `darwin-rebuild switch` 사이인 이유도 이것이다.
캐시는 빌드에 쓰이고, switch 는 이미 스토어에 있는 것을 실현할 뿐이다.
