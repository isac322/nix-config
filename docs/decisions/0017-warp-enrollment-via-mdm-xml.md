# 0017. WARP 조직 등록은 mdm.xml 로

**결정** — 두 맥에 같은 WARP 설정을 넣고, 조직 등록은 `mdm.xml` 로 선언한다.
토큰 절차는 [운영 · WARP service token](../operations.md#warp-service-token).

두 맥이 **완전히 같다.** 같은 클라이언트, 같은 Zero Trust 조직(`runbear`). WARP는
아웃바운드 클라이언트라, 책상에 놓인 기계든 들고 다니는 기계든 내부 전용 서비스에
닿기 위해 쓰는 방식이 동일하다. 그래서 `modules/warp.nix`는 호스트 분기가 없다.

설치는 [cask 로 한다](0015-gui-apps-come-from-homebrew.md) — 특권 데몬을 심는 것이
`.pkg` 이고 그것을 실행하는 것은 cask 뿐이다.

조직 등록은 선언적으로 들어간다. macOS는
`/Library/Application Support/Cloudflare/mdm.xml`을 읽고, 서비스가 로그인 전에 이를
적용하므로 기계마다 team 이름을 입력할 필요가 없다. 여기 적은 값이 대시보드의 기기
설정을 덮어쓰므로, 레포에 둘 만한 것만 적는다.

`service_mode`는 `warp`(전체 터널)다. 내부 전용 서비스에 닿으려면 이게 필요하고,
`1dot1`은 DNS만 암호화한다. `onboarding = false`는 최초 실행 화면을 건너뛰고,
`auto_connect = 1`은 누가 스위치를 켜주길 기다리지 않는다 — 둘 다 헤드리스에서 의미가
있다.
