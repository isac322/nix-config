# 0016. App Store 전용 앱도 switch에서 갱신한다

**결정** — KakaoTalk과 WireGuard를 `local.masApps`에 선언하고, switch가
`mas`로 설치·업데이트한다. `homebrew.masApps`에 섞지 않고
`modules/mas-apps.nix`에서 로그인 세션과 실패 처리를 관리한다.

두 앱은 Homebrew cask나 직접 다운로드로 대체하지 않는다. App Store에 로그인한
사용자 세션으로 요청을 보내되, 설치에 필요한 root 권한은 유지한다.
대상은 선언된 App Store ID로 제한한다.

사용자는 먼저 App Store에 로그인하고 해당 계정으로 앱을 받아야 한다.
최초 계정 등록·구매·추가 인증은 자동화하지 않으며 보안 설정도 바꾸지 않는다.
이미 계정에 등록된 앱이 기기에 없으면 설치하고, 설치된 앱은 업데이트한다.

GUI 세션이 없거나 계정·권한·네트워크 문제, 시간 초과가 발생하면 switch를
실패시킨다. 경고만 출력하고 전체 업데이트가 끝난 것처럼 넘어가지 않는다.
실패를 해결한 뒤 switch를 다시 실행한다. 다른 패키지에서 이미 완료된
시스템 변경까지 원복하는 트랜잭션은 아니다.

이전 구현은 root activation에서 App Store에 접근하지 못하는 문제를 피해
설치 여부만 확인하고 수동 설치를 안내했다. 이제 사용자 세션을 명시적으로
선택하므로 설치와 갱신을 같은 switch 경로에 포함한다.

서버 역할의 맥에는 두 GUI 앱을 선언하지 않는다. WireGuard는 앱 대신
`wireguard-tools` 데몬을 사용한다
([0029](0029-wireguard-as-a-daemon-on-the-server-mac.md)).
