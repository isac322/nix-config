# 0029. 서버 맥의 WireGuard 는 앱이 아니라 루트 데몬

**결정** — 서버 역할의 맥은 App Store 클라이언트를 안 쓴다. nixpkgs 의
`wireguard-tools` 를 깔고 `wg-quick up` 을 LaunchDaemon 으로 돌린다. 랩탑은
그대로 앱을 쓴다.

[0016](0016-mas-only-apps-installed-by-hand.md) 을 뒤집는 것이 아니다. 거기 적힌
두 가지 — 그 앱은 선언적으로 설치할 수 없고, nixpkgs 의 `wireguard-tools` 는 그
앱이 아니라 CLI 다 — 는 지금도 참이다. 바뀐 것은 질문이다. **화면이 없는 기계는
그 앱을 원하지 않는다.**

## 앱이 왜 안 되나

[0028](0028-orca-runtime-on-the-server-mac.md) 과 정확히 같은 병이다. 앱이 깔린
맥에서 확인했다.

```
번들 실행파일        WireGuard 하나. CLI 바이너리 없음
확장                 WireGuardNetworkExtension.appex
                     → com.apple.networkextension.packet-tunnel (앱이 호스팅한다)
번들 안 launchd plist 없음
설정                 ~/Library/Group Containers/…group.com.wireguard.macos
                     /Library/… 에는 아무것도 없다

launchctl print gui/501     앱 프로세스 + login-item-helper
launchctl print user/501    login-item-helper 등록만
launchctl print system      WireGuard 관련 잡 0개
```

`system` 도메인이 비어 있고 설정이 사용자 컨테이너에만 있다. 즉 콘솔 로그인
전에 터널을 올릴 **주체가 존재하지 않는다.** 뚜껑 닫힌 채 재부팅된 기계는
아무에게도 안 닿고, 그러면 [Orca 광고 주소](0028-orca-runtime-on-the-server-mac.md)
도 같이 죽는다.

## CLI 는 진짜로 macOS 판이다

`wireguard-tools` 가 리눅스용을 darwin 에 얹어 놓은 것이 아니다. 받아서 열어봤다:

```
127: cmd "${WG_QUICK_USERSPACE_IMPLEMENTATION:-wireguard-go}" utun
228: get_response="$(cmd networksetup -getdnsservers "$service")"
302: cmd networksetup -setdnsservers "$service" "${DNS[@]}"
```

`utun`·`networksetup`·`scutil` 호출이 24군데다. 커널 모듈이 없는 macOS 에서는
`wireguard-go` 가 사용자 공간 구현을 맡고, nixpkgs 래퍼가 그걸 PATH 에 얹어
준다. 설정은 `/etc/wireguard/<iface>.conf` 에서 읽는다.

패키지가 주는 서비스 통합은 systemd 유닛뿐이라 launchd plist 는 우리가 쓴다.

## 부팅 때 안 뜨던 두 가지

선언만으로는 안 됐다. 실제로 그 기계에서 잡은 것 둘.

**`wait4path` 가 없었다.** nix-darwin 의 `command`/`script` 옵션은
ProgramArguments 를 `/bin/sh -c '/bin/wait4path /nix/store && exec …'` 로 만들어
주는데, `serviceConfig.ProgramArguments` 를 손으로 쓰면 그 래퍼가 안 붙는다.
`/nix/store` 는 데몬이 시작될 때 아직 안 붙은 볼륨이라 맨 store 경로는 exec 자체가
실패한다. **조용히** 실패한다 — `StandardErrorPath` 에 쓸 프로세스가 뜨기 전이라
로그도 안 남는다. 로그의 마지막 줄이 부팅보다 두 시간 앞서 있는 것으로 드러났다.

**launchd 가 `wireguard-go` 를 죽였다.** `wg-quick up` 은 `wireguard-go` 를 떼어
놓고 자신은 끝난다. launchd 는 잡의 메인 프로세스가 사라지면 그 프로세스 그룹에
남은 것을 죽인다. 로그에는 성공적인 bring-up 이 전부 찍혀 있는데 — 주소, 경로
19개, "Backgrounding route monitor" — 정작 그 인터페이스가 없었다.
`AbandonProcessGroup = true` 가 그것을 막는 키다.

두 증상 모두 "설정이 틀렸다" 처럼 보이지 않는다는 점이 같다. 하나는 아무 흔적도
안 남기고, 다른 하나는 성공한 흔적만 남긴다.

## 주소는 읽을 수 있는 곳에 따로 발행한다

wg-quick 이 남기는 것은 전부 root 전용이다. 설정은 0600 root, 그리고 인터페이스와
실제 utun 을 잇는 `/var/run/wireguard/<name>.name` 은 0400 root:daemon 이다.

그래서 사용자 권한으로 도는 것은 이 기계가 어느 주소로 답하는지 알 방법이 없다.
[Orca 런타임](0028-orca-runtime-on-the-server-mac.md)이 정확히 그런 처지라, 데몬이
인터페이스를 올린 뒤 주소를 `/var/run/wireguard-addresses` (0644) 에 쓴다. 설정
파일이 아니라 **인터페이스에서** 읽어서, 적힌 것이 실제로 올라온 것이 되게 한다.
터널이 하나도 없으면 그 파일을 지운다 — 낡은 주소가 남아 있는 것이 없는 것보다
나쁘다.

## KeepAlive 를 안 켠 이유

`wg-quick up` 은 인터페이스를 올리고 **끝난다**. 감시할 프로세스가 없다.
`KeepAlive = true` 였다면 터널을 무한히 다시 올린다.

살아 있게 하는 것은 wg-quick 이 떼어 놓고 가는 `wireguard-go` 이고, 그게 죽으면
지금은 아무도 안 살린다. 그게 문제가 되면 답은 이 잡의 KeepAlive 가 아니라
따로 만드는 watchdog 이다.

대신 스크립트를 멱등으로 썼다. switch 는 이전 터널이 살아 있는 채로 데몬을
재적재하고, wg-quick 은 이미 있는 인터페이스를 다시 올리기를 거부한다. 먼저
내리고 올려야 reload 가 reload 가 된다.

## `.conf` 는 레포에 안 들어간다

개인키가 들어 있다. [WARP service token](0017-warp-enrollment-via-mdm-xml.md) 과
같은 처리다 — 기계당 한 번 손으로 놓고, 없으면 데몬이 터널을 안 올리고 이유를
`/var/log/wireguard.log` 에 남긴다. 절차는 [운영](../operations.md).

인터페이스 이름은 **레포에 안 적는다.** 파일 이름이 곧 인터페이스 이름이라
설정 파일이 이미 그 정보를 들고 있고, 이름을 양쪽에 두면 갈라질 자리만 생긴다.
데몬은 `/etc/wireguard/*.conf` 를 전부 올린다.

역할이 정하는 것은 `local.wireguard.enable` 하나뿐이다. 기본값 `false` 는 "이
기계는 자기 터널을 안 돌린다" 이고, 사람이 앉는 맥이 그 경우다 — 거기서는 앱이
더 낫고, 앱이 필요로 하는 로그인 세션이 실제로 있다.
