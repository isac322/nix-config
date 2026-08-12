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

## 따라오는 것 — `knownSha256Hashes`

`environment.etc."nix/nix.custom.conf".knownSha256Hashes` 가 필요한 것도 이 구도
때문이다. Determinate 설치 프로그램이 만들어둔 `nix.custom.conf`를 determinate
모듈이 덮어쓰려 하는데, nix-darwin은 정체불명 파일을 만나면 activation을 중단한다.
설치 프로그램이 쓴 파일의 해시를 화이트리스트에 넣어 첫 activation이 통과하게 한다.
설치 옵션이 다르면 해시도 달라지므로, 그때는 새 해시를 목록에 추가한다.
