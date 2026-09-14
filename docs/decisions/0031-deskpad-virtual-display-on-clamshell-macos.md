# 0031. 클램쉘 서버 맥의 Aqua 화면은 DeskPad로 유지한다

**결정** — Camofox는 macOS의 로그인된 Aqua 세션에서 네이티브 Camoufox를
실행한다. MBP는 `local.camofox.enable = true`,
`local.camofox.virtualDisplay = true`, `local.autoLogin.enable = true`를 함께
설정한다. 단일 Aqua LaunchAgent가 DeskPad 가상 모니터를 만들고, displayplacer로
1920×1080 main display를 선택하며, `caffeinate -d`로 display idle sleep을
막는다. MBA는 `virtualDisplay`의 기본값 `false`를 써서 실제 데스크톱에서
Camofox를 실행한다.

DeskPad 스택은 화면만 제공한다. 전체 데스크톱의 원격 화면과 입력은 MBP의
RustDesk Direct IP host가 담당한다. 두 기능을 한 서비스나 한 자격증명 경계로
묶지 않는다.

## 왜 Aqua 가상 디스플레이인가

Camofox의 macOS 브라우저는 일반 Firefox 앱과 같은 WindowServer 세션을 쓴다.
Linux용 headless display 구성을 macOS에 얹으면 네이티브 앱의 창 배치, 입력,
LaunchServices 동작을 그대로 재현하지 못한다. 로그인된 Aqua 세션에서 실행해야
운영자가 보는 브라우저와 자동화가 다루는 브라우저가 같다.

서버 역할의 MBP는 닫힌 뚜껑으로 오래 실행한다. 물리 화면이 없으면 창 좌표와 main
display가 사라지거나 바뀔 수 있다. LaunchAgent는 기존 display layout을 기억하고
`caffeinate -d`를 시작한 뒤 DeskPad를 실행해 숨긴다. DeskPad의
`CGVirtualDisplay`를 찾으면 displayplacer로 1920×1080 main display에 배치하고
Camofox daemon을 시작한다. 실행 중 DeskPad가 교체되면 persistent display ID로
새 프로세스와 화면을 다시 채택한다. 종료할 때는 이전 layout을 복원한 뒤 DeskPad를
끝낸다. 이 수명 관리가 클램쉘 상태에서도 안정적인 Aqua 작업 공간을 유지한다.

MBA는 사람이 쓰는 실제 화면이 있으므로 별도 가상 모니터를 만들지 않는다.
옵션의 기본값을 `false`로 두고 서버 역할의 MBP만 명시적으로 켠다.

## 화면 제공과 원격 접속의 경계

DeskPad는 디스플레이 장치와 좌표계를 제공한다. 화면 전송, 키보드·포인터 전달,
원격 접속 인증은 RustDesk의 책임이다. RustDesk는 Aqua 데스크톱 전체를 보여
주므로 Camofox뿐 아니라 같은 화면에 놓인 다른 앱도 보인다.

RustDesk 클라이언트는 관리 대상 세 기기에 설치한다.

- MBP와 MBA: 공통 Darwin 구성의 Homebrew RustDesk cask
- aarch64-linux NixOS server: `pkgs.rustdesk-flutter`

MBP만 Direct IP host를 실행한다. PF anchor는 현재 WireGuard interface의 IPv4
TCP 21118만 허용하고 다른 IPv4 interface와 IPv6를 차단한다. 별도 ID server나
relay server를 두지 않으며, 클라이언트는 WireGuard 주소로 직접 접속한다.

이 분리 덕분에 가상 디스플레이는 원격 접속 listener, 접속 비밀번호, 인증서,
화면 캡처 권한을 관리하지 않는다. DeskPad 패키지나 화면 배치를 바꿔도 원격 접속
보안 경계는 RustDesk와 PF에 남는다.

## Camofox의 경계

Camofox API는 `127.0.0.1:9377`에만 연다. OMP, Claude Code, Codex는
`camofox-browser-mcp-session` stdio wrapper를 통해 이 API를 사용한다. 외부
네트워크는 API에 직접 접속하지 않는다.

`CAMOFOX_USER_ID=omp`는 세 클라이언트의 쿠키와 웹 스토리지를 공유한다.
`sessionKey`는 탭 목록과 조작 권한을 대화별 namespace로 나눈다. 이 논리적
분리는 RustDesk가 보여 주는 Aqua 데스크톱의 화면 격리를 뜻하지 않는다.

Camofox browser는 활성 세션이 없으면 상류 idle timeout 뒤 종료될 수 있다.
API daemon과 DeskPad 화면은 계속 살아 있고, 다음 요청이 같은 관리 환경에서
브라우저를 다시 띄운다.

## 운영 결과

서버 맥은 Aqua LaunchAgent를 위해 자동 로그인과 FileVault 비활성화를 감수한다.
DeskPad, displayplacer, Camofox는 Nix가 고정한 패키지를 사용한다. switch는
별도 보조 job 없이 단일 Camofox LaunchAgent의 시작 순서, 감시, display 복원을
관리한다. RustDesk 앱은 두 Mac의 공통 Homebrew cask로 설치하지만 Direct IP
host와 PF 경계는 서버 역할에만 둔다.

이 결정은 Camofox의 표시 장치와 전체 데스크톱 원격 접속을 분리한다. DeskPad는
클램쉘 MBP의 안정적인 1920×1080 Aqua 디스플레이를 제공하고, RustDesk는 그
데스크톱에 대한 원격 접속을 제공한다.
