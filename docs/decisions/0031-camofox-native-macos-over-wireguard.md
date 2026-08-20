# 0031. Camofox 는 macOS 에서 네이티브로, 화면은 WireGuard 너머로

**결정** — 서버 맥에서 `@askjo/camofox-browser` API를 Aqua LaunchAgent로
headful 실행하고, 브라우저 코어는 `daijro/camoufox`의 macOS arm64 릴리스를 쓴다.
같은 LaunchAgent가 MIT 라이선스의 DeskPad 1.3.2로 가상 디스플레이를 만들고,
displayplacer 1.4.0으로 1920×1080 main display를 정한다. GPL-2.0의
`LibVNC/macVNC`는 그 디스플레이 전체가 아니라 bundle identifier
`org.mozilla.camoufox`가 소유한 창만 `127.0.0.1:5901`의 VNC로 내보낸다. root
noVNC LaunchDaemon은 이를 WireGuard 주소의 HTTPS 웹소켓으로만 중계한다. API는
loopback에만 열고, 실행 중 다운로드는 없다.

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

## 상류 VNC 플러그인과 Apple Screen Sharing을 최종 경로로 쓰지 않는다

Camofox의 VNC 플러그인은 Linux의 Xvfb 디스플레이를 만들고 그 디스플레이를 VNC로
내보내는 경로다. Aqua 윈도우를 가진 macOS 브라우저를 공유하는 구현이 아니므로
`ENABLE_VNC=0`을 유지한다.

macOS 내장 `screensharingd`도 최종 백엔드로 쓰지 않는다. 물리 디스플레이가 있는
동안에는 동작하지만, 닫힌 뚜껑 상태에서 만든 Apple VFB를 Screen Sharing 자체가
캡처하지 못해 인증과 소켓은 정상인데 framebuffer만 검게 남았다. 이 실패를 화면
잠금이나 noVNC 문제로 숨기지 않고 백엔드를 교체했다.

전환 activation은 legacy VNC 인증을 즉시 끄고
`/Library/Preferences/com.apple.VNCSettings.txt`를 제거한다. 첫 전환에서는
`local.camofox.retireScreenSharing = false`로 native Screen Sharing job을 noVNC와
무관한 migration console로 남겼다. macVNC의 Screen Recording·Accessibility 권한,
전용 가상 디스플레이의 화면, 키보드와 포인터 입력을 모두 확인했으므로 현재 역할은
이 값을 `true`로 둔다. switch는 `com.apple.screensharing`을 disable·bootout한다.
어느 단계에서도 noVNC가 이 서비스를 backend로 쓰거나 같은 8자 legacy 비밀번호를
검사하게 두지 않는다.

DeskPad는 Aqua 세션 안에서 `CGVirtualDisplay`로 전용 가상 모니터를 만든다.
displayplacer가 그 모니터를 1920×1080, scaling off, origin `(0,0)`의 main display로
배치하고, 상류 macVNC가 ScreenCaptureKit으로 그 디스플레이 전체를 캡처한다. 별도
application/window filter나 PID별 입력 전달 코드는 유지하지 않는다. VNC framebuffer에는
그 디스플레이의 desktop·Dock·menu bar와 그 위에 놓인 모든 앱이 그대로 보이고,
키보드와 포인터도 Aqua 세션의 해당 좌표로 전달된다.

따라서 운영 경계는 Camoufox 프로세스나 특정 창이 아니라 **전용 가상 디스플레이**다.
다른 앱을 이 디스플레이로 옮기면 noVNC에 보이고 조작할 수 있다. 이 제약을 명시하는
대신, 여러 Camoufox 창을 추적하고 frontmost·hit-test·button-state를 동기화하던
커스텀 macVNC 계층을 제거한다.

Camofox는 상류 기본값인 300000ms idle timer를 쓴다. 서비스가
`BROWSER_IDLE_TIMEOUT_MS`를 덮어쓰거나 `0 = never` sentinel patch를 유지하지 않는다.
활성 세션이 없으면 Camoufox 프로세스는 약 5분 뒤 종료되지만 Node API daemon,
DeskPad, macVNC, noVNC는 계속 실행된다. 다음 브라우저 요청이 공유 Camoufox
프로세스를 다시 띄운다. VNC 수명과 브라우저 PID를 분리해 idle browser의 상주
메모리와 별도 readiness gate를 없앤다.

noVNC는 특정 창이나 `sessionKey`의 화면이 아니라 전용 디스플레이 전체를 보여주는
운영 콘솔이다. MCP의 탭 namespace 격리와 VNC 화면 경계를 같은 것으로 취급하지
않는다.

DeskPad가 내부에서 쓰는 `CGVirtualDisplay`는 공개 SDK 계약이 아닌 macOS private
API다. 이 위험은 남지만, 이 저장소가 private API VNC 서버를 새로 유지하지는 않는다.
OS 업데이트로 가상 디스플레이가 깨지면 DeskPad 준비 단계가 실패하고 LaunchAgent가
전체 스택을 재시도한다. 검은 화면을 성공으로 취급하는 fallback은 두지 않는다.

macVNC의 기본 모드는 키보드와 포인터 입력을 허용하므로 Accessibility 권한이 없으면
시작하지 않는다. Screen Recording 권한도 full-display 캡처에 필요하다. 관찰 경로만
진단할 때 명시적으로 `local.camofox.vncViewOnly = true`를 쓸 수 있지만 자동으로
view-only로 후퇴해 권한 실패를 숨기지는 않는다.

`userId`는 macOS 로그인 사용자가 아니라 Camofox 내부 세션 식별자다. 서버 하나가
필요할 때 공유 Camoufox 브라우저 프로세스 하나를 띄우고, `userId`마다 별도
Playwright BrowserContext를 만든다. 쿠키와 웹 스토리지는 격리되지만 noVNC 화면,
포커스, 키보드, 마우스, 클립보드는 전용 디스플레이 전체에서 공유된다. noVNC는
신뢰된 운영자의 공용 콘솔이며 사용자별 화면 경계가 아니다.

OMP, Claude Code, Codex는 같은 `camofox-browser-mcp-session` wrapper를 stdio MCP
서버로 실행한다. wrapper는 `CAMOFOX_USER_ID=omp`를 유지해 로그인 쿠키와 웹
스토리지를 공유하고, 클라이언트 세션 식별자를 `sessionKey`로 넣어 탭 namespace와
조작 권한을 분리한 뒤 패키지의 `camofox-browser-mcp`를 실행한다. 그 어댑터는
`http://127.0.0.1:9377`의 REST API로 요청을 전달하고, Camofox daemon이 필요할 때
공유 Camoufox 프로세스를 하나만 실행한다.

상류 1.13.1은 `sessionKey`로 탭 생성 group만 골랐고, list와 `tabId` 조작은 같은
`userId`의 모든 group을 검색했다. 따라서 wrapper만 추가하면 namespace 이름만 다를
뿐 실제 격리가 아니다. Nix 패키지는 MCP 어댑터가 모든 탭 요청에 `sessionKey`를
전달하도록 하고, REST 서버의 list와 lookup이 그 group 밖을 보거나 조작하지 못하게
함께 패치한다. session A가 session B의 `tabId`를 알아도 조작은 404로 거부된다.

OMP 17.3.4는 세션 UUID를 MCP 환경에 직접 내보내지 않으므로 wrapper가 현재 terminal
breadcrumb의 transcript 파일명에서 UUID를 읽는다. 같은 transcript를 resume하면
같은 namespace를 되찾는다. Claude Code 2.1.233은 `CLAUDE_CODE_SESSION_ID`를 MCP
자식에게 전달하고 resume에서도 보존한다. Codex 0.147.0은 thread ID를 MCP 자식에게
전달하지 않으므로 현재는 adapter 프로세스별 자동 UUID가 경계다. 이는 동시 프로세스
간 격리는 제공하지만 종료 후 resume 안정성은 제공하지 않으며, 그 보장에는 Codex
상류 변경이나 패키지 패치가 필요하다.

**VNC 비밀번호를 만들거나 소유하는 것은 noVNC가 아니다.** activation이 root
master를 만들고 표준 LibVNCServer 형식의 8바이트 auth 파일을 원자적으로 파생한다.
macVNC가 그 파일로 자격증명을 검사한다.

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

RFB VNCAuth는 실질적으로 처음 8바이트만 쓰므로 비밀번호를 정확히 8자의 영숫자로
제한한다. 이것만 인터넷에 내놓으면 약하다. 그래서 자격증명 자체가 아닌 도달 범위를
보강한다.

- `macVNC.app`은 `127.0.0.1:5901`에만 연다. LAN과 WireGuard에서 VNC backend로
  직접 접속할 수 없다.
- noVNC는 `/var/run/wireguard-addresses` 첫 줄의 주소에만 `:6080`을 연다.
  `0.0.0.0`, LAN 주소, 주소가 없을 때의 fallback은 없다.
- Camofox API는 `127.0.0.1:9377`에만 연다. OMP의 stdio MCP 어댑터만 로컬에서
  접근한다.

비밀번호 원문 master는 `/var/lib/nix-darwin/camofox-vnc-password`에
`root:wheel 0600`으로 한 번만 만들고, 이미 있으면 바꾸지 않는다. activation은 이를
RFB의 고정 DES key로 암호화해 `/var/lib/camofox/vnc-auth`에
`bhyoo:staff 0400`으로 원자적으로 교체한다. 이 auth 파일도 고정 key로 되돌릴 수 있는
secret이므로 로그나 Nix store에 넣지 않는다. 원문은 argv·launchd plist·Nix store에
들어가지 않는다.

웹 클라이언트는 noVNC에 닿은 뒤 VNC 비밀번호를 보낸다. 대신 backend는 한 호스트의
loopback 밖으로 못 나가고, frontend는 이미 WireGuard peer인 클라이언트에게만
노출된다. 짧은 비밀번호 하나가 공개 인터넷 경계가 되지 않게 한 구조다.

## 실행 중 다운로드는 없다

Camoufox zip, Camofox npm tarball과 의존성, DeskPad zip, displayplacer 실행 파일,
macVNC source revision은 전부 Nix 빌드 입력이고 버전·revision·hash로 고정한다.
서비스는 store의 실행 파일만 읽는다. 첫 실행에 브라우저나 원격 화면 구성요소를
받거나 버전 API를 조회하는 fallback은 두지 않는다. 무인 재부팅 뒤의 성공 여부가
외부 registry 상태나 `HOME` 아래의 mutable cache에 달리면 선언한 패키지가 실제
runtime을 설명하지 못하기 때문이다.

서버 역할은 `local.camofox.enable = true`와 migration gate인
`retireScreenSharing = false`를 선언한다. 후자는 macVNC 화면과 입력을 확인한 뒤에만
`true`로 바꾼다. 자동 로그인과 WireGuard는 각각
[0028](0028-orca-runtime-on-the-server-mac.md),
[0029](0029-wireguard-as-a-daemon-on-the-server-mac.md)의 기존 결정을 그대로 쓴다.
운영 주소·비밀번호 조회·재시작·검증 명령은 [운영](../operations.md)에 있다.
