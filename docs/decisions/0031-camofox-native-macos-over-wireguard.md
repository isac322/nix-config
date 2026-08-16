# 0031. Camofox 는 macOS 에서 네이티브로, 화면은 WireGuard 너머로

**결정** — 서버 맥에서 `@askjo/camofox-browser` API 를 Aqua LaunchAgent 로
headful 실행하고, 브라우저 코어는 `daijro/camoufox` 의 macOS arm64 릴리스를 쓴다.
화면은 macOS 내장 `screensharingd` 가 loopback VNC 로 내고, nixpkgs 의 noVNC 가
그것을 WireGuard 주소의 웹소켓으로만 중계한다. 실행 중에는 아무것도 받지 않는다.

## macOS 코어는 추측이 아니라 그 기계에서 확인했다

Camoufox 는 Firefox 계열 코어이고, 이번에 고정한 것은
`152.0.4-beta.28` 의 `camoufox-152.0.4-beta.28-mac.arm64.zip` 이다. Apple Silicon
전용 아티팩트를 Nix store 에 풀어 Camofox 가 그 경로만 실행하게 한다.
`@askjo/camofox-browser` 1.13.1 의 코어 로딩과 실제 기동은
`bhyoo-macbook-pro`의 aarch64-darwin 에서 확인했다. 즉 리눅스 패키지를 Rosetta 로
우회하거나, macOS 에서 될 것이라고 이름만 보고 가정한 구성이 아니다.

대신 **beta 를 고정한 위험**은 남는다. 안정판보다 회귀 가능성이 크고, 자동으로
다음 릴리스의 수정도 받지 않는다. 버전과 해시를 올리는 일은 의식적인 변경이어야
한다. 브라우저 지문과 동작이 버전에 민감한 프로그램에서 조용한 자동 업데이트보다
검증한 한 버전을 고정하는 쪽을 택했다.

## 상류 VNC 플러그인은 macOS 용이 아니다

Camofox 의 VNC 플러그인은 Linux 의 Xvfb 디스플레이를 만들고 그 디스플레이를 VNC 로
내보내는 경로다. Aqua 윈도우를 가진 macOS 브라우저를 공유하는 구현이 아니므로
그 플러그인은 그대로 비활성화한다. "VNC 가 필요하다"는 공통점만으로 Linux/X11
수명주기를 macOS 에 옮기지 않는다.

macOS 에 이미 같은 일을 하는 `screensharingd` 가 있다. Camofox 는 자동 로그인으로
만들어진 기존 Aqua 세션에서 headful 로 뜨고, 내장 Screen Sharing 은 **Camofox
창 하나가 아니라 그 Aqua 데스크톱 전체**를 VNC 로 낸다. noVNC 는
`127.0.0.1:5900`을 backend 로 삼아 브라우저 클라이언트와 로컬 VNC 사이를 잇는
웹 프런트엔드일 뿐이다.

`userId`는 macOS 로그인 사용자가 아니라 Camofox 내부 세션 식별자다. 서버 하나가
Camoufox 브라우저 프로세스 하나를 공유하고, `userId`마다 별도 Playwright
BrowserContext를 만든다. 쿠키와 웹 스토리지는 격리되지만 모든 컨텍스트의 창은 같은
Aqua 데스크톱에 나타나므로 화면, 포커스, 키보드, 마우스, 클립보드는 공유된다.
따라서 noVNC 는 신뢰된 운영자의 공용 관리 콘솔이며 사용자별 화면 경계가 아니다.

**VNC 비밀번호를 만들거나 소유하는 것은 noVNC 가 아니다.** activation 이 만든 값을
macOS 의 VNC 설정 형식으로 넣고, `screensharingd` 가 그 자격증명을 검사한다.

## headful opt-out 은 빌드할 때 끝낸다

배포된 `@askjo/camofox-browser` 는 기본적으로 headless 기동을 강제한다. 여기서는
패키지의 번들에 `CAMOFOX_HEADLESS=false` 를 읽는 opt-out 을 `postPatch` 로 넣는다.
서비스가 임의의 소스를 고치거나 시작할 때 패치하지 않는다. **같은 store 경로면
같은 headful 동작**이고, 패치가 상류 번들과 더는 맞지 않으면 switch 전에 빌드가
깨져 드러난다.

Camofox 의 crash-report telemetry 도 서비스 환경에서 끈다. 이것은 접근 경계를
대신하는 보안 기능이 아니라, 무인 브라우저의 실패 내용이 외부로 자동 전송되지 않게
하는 운영 선택이다.

## 짧은 VNC 비밀번호를 두 겹의 주소 경계로 감싼다

macOS legacy VNC 호환 경로는 **정확히 8자**만 쓴다. 더 긴 비밀번호나 현대적인
인증으로 바꾼 척할 수 없고, 이것만 인터넷에 내놓으면 약하다. 그래서 자격증명 자체가
아닌 도달 범위를 보강한다.

- `screensharingd` 는 `VNCOnlyLocalConnections=true` 로 non-loopback VNC 를 인증
  전에 거부하고, noVNC 만 `127.0.0.1:5900`으로 붙는다. OS 버전에 따라 listening
  socket 은 wildcard 로 보여도 LAN 과 WireGuard 클라이언트는 VNC 를 쓸 수 없다.
- noVNC 는 `/var/run/wireguard-addresses` 첫 줄의 주소에만 `:6080` 을 연다.
  `0.0.0.0`, LAN 주소, 주소가 없을 때의 fallback 은 없다.
- Camofox API 도 같은 WireGuard 주소에만 `:9377` 을 연다. 터널 주소가 아직 없으면
  둘 다 실패하고 launchd 재시작을 기다린다. 넓게 열어서 먼저 살아나는 것보다
  닫힌 채 재시도하는 쪽이 맞다.

비밀번호 원문은 `/var/lib/nix-darwin/camofox-vnc-password` 에 `root:wheel 0600`으로
한 번만 만들고, 이미 있으면 바꾸지 않는다. Screen Sharing 쪽의
`/Library/Preferences/com.apple.VNCSettings.txt` 는 그 8바이트를 16바이트로
NUL padding 한 뒤 애플의 고정 키와 XOR 한 호환 형식이다. **암호화 저장소가 아니다.**
파일 권한과 네트워크 경계가 실질적인 보호다.

이 구조는 웹 클라이언트가 noVNC 에 닿은 뒤 legacy VNC 비밀번호를 보내는 것을
없애지 않는다. 대신 백엔드는 한 호스트의 loopback 밖으로 못 나가고, 프런트엔드는
이미 WireGuard 피어인 클라이언트에게만 노출된다. 짧은 비밀번호 하나가 공개
인터넷 경계가 되지 않게 한 것이 이 설계의 보상이다.

## 실행 중 다운로드는 없다

Camoufox zip, Camofox npm tarball, npm 의존성은 전부 Nix 빌드 입력이고 해시로
고정한다. 서비스는 store 의 코어와 `node_modules` 만 읽는다. 첫 실행에 브라우저를
받거나 버전 API를 조회하는 fallback 은 두지 않는다. 무인 재부팅 뒤의 성공 여부가
외부 레지스트리 상태나 `HOME` 아래의 mutable cache 에 달리면 선언한 패키지가
실제 런타임을 설명하지 못하기 때문이다.

역할이 정하는 것은 `local.camofox.enable` 하나다. 서버 역할만 켜고, 자동 로그인과
WireGuard 는 각각 [0028](0028-orca-runtime-on-the-server-mac.md),
[0029](0029-wireguard-as-a-daemon-on-the-server-mac.md)의 기존 결정을 그대로 쓴다.
운영 주소·비밀번호 조회·재시작·검증 명령은 [운영](../operations.md)에 있다.
