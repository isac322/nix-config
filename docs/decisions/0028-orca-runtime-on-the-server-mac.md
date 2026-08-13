# 0028. 서버 맥에서 Orca 런타임을 계속 띄운다

**결정** — `orca serve` 를 LaunchAgent 로 돌린다. 세션 타입은 `Background`,
포트는 6768, 광고 주소는 그 기계의 WireGuard 주소. exit 3 은 재시작하지 않는다.

Orca 는 [양쪽 맥 다 깔린다](0015-gui-apps-come-from-homebrew.md). 랩탑에서는
사람이 앱을 열지만 서버 맥에는 열 창이 없고, 그런데도 런타임은 계속 있어야 한다
— 클라이언트는 UI 일 뿐이고 프로젝트·워크트리·터미널·에이전트 프로세스를 쥐는
쪽은 서버다.

## 왜 `serve` 인가

`orca serve` 가 상류가 정해 둔 답이다. 데스크톱 창 없이 런타임만 올린다. 문서는
맥이라면 그냥 로그인해 두고 앱을 쓰라고 권하지만, 그건 사람이 앞에 있는 기계
이야기다. 이 기계는 뚜껑이 닫혀 있다.

한 기계에 호스팅 모드는 하나뿐이다. 앱이 이미 그 기계를 공유하고 있으면 `serve`
를 따로 띄우면 안 된다. 서버 맥에서 앱이 뜰 일은 없지만, 그 상황을 런타임이
exit 3 으로 알려주므로 아래에서 그걸 다룬다.

## `Background` 가 이 결정의 핵심이다

LaunchAgent 는 `LimitLoadToSessionType` 을 안 주면 기본이 `Aqua` 다. **콘솔 GUI
로그인 때만 뜨고 SSH 로그인으로는 안 뜬다는 뜻이다.** 맥에서 확인했다:

```
gui/501/org.nix-community.home.gpg-agent-ssh   있음   (session = Aqua)
user/501/org.nix-community.home.gpg-agent-ssh  없음   (session = Background)
```

반대 방향도 같다. `LimitLoadToSessionType = Background` 가 박힌 애플의
`com.apple.cfprefsd.xpc.agent` 는 `user/501` 에만 있고 `gui/501` 에는 없다.

그래서 `Background` 를 준다. `user/<uid>` 도메인은 윈도우 서버에 안 묶여 있다.
**증명하지 못한 것 하나** — 아무도 로그인하지 않은 부팅 직후에 그 도메인이
올라오는지는 로그인해 있는 기계에서 확인할 수 없었다. 그 기계에서 재부팅 후
한 번 확인하는 절차를 [운영](../operations.md) 에 적어 뒀고, 안 되면 남는 답은
자동 로그인이다.

대안이던 LaunchDaemon 은 로그인 없이 뜨는 대신 GUI 세션도 로그인 keychain 도
없다. Electron 기동과 Claude·Codex 계정 인증이 거기서 깨진다. 로그인 없이 뜨는
것이 목적인데 뜬 다음 아무것도 못 하면 의미가 없다.

## 주소는 기기에 속한다

`--pairing-address` 는 **광고할 주소만** 바꾼다. 바인딩 주소가 아니다. 런타임은
`0.0.0.0:6768` 에 열리고 그걸 좁히는 플래그는 없다. 그래서 이 값은 "이 기계에
어떻게 닿는가" 이고, 서버 맥이 둘이면 둘의 값이 다르다. 역할에 넣을 수 없다.

세 축([0002](0002-compose-not-inherit.md))이 정확히 이 경우를 위해 있다. 역할은
"런타임이 돈다" 까지만 정하고, 주소와 포트는 `hosts/<name>/` 이 말한다.

옵션 선언은 `modules/orca.nix` 에 따로 있다. **`local.` 접두사**를 쓴다 — 이
레포가 스스로 만드는 옵션은 한 군데 아래 모아야, 나중에 nix-darwin 이 같은 이름을
추가해도 부딪히지 않는다. 이게 그 첫 번째다.

에이전트 자체는 home-manager 모듈이라 시스템 옵션을 직접 못 본다. `osConfig` 로
읽는다 — home-manager 의 `nix-darwin/default.nix` 가 `nixos/common.nix` 를
import 하고, 거기서 `specialArgs.osConfig = config` 로 시스템 설정을 넘겨준다.

기본값은 `null` 이고, 그건 "아직 안 정했다" 가 아니라 **런타임을 안 띄운다**는
뜻이다. 주소를 짐작해서 만든 페어링 URL 은 아무데도 닿지 않는 링크가 된다.
상류가 와일드카드 광고를 거부하는 것도 같은 이유다.

값 자체는 사설 대역이고 터널 안에서만 닿으므로 공개 레포에 적어도
[열쇠를 안 넣는 것](0026-sshd-on-the-server-mac.md)과 성격이 다르다 — 그건
자격증명이고 이건 경로다. 진짜 경계는 다른 데 있다: 바인딩이 0.0.0.0 이라
그 기계가 붙은 **다른 네트워크에서도** 6768 은 열려 있다. 막는 것은 런타임이
아니라 네트워크고, 상류도 공개 인터넷 포워딩만은 하지 말라고 못박는다.

## exit 3 은 왜 다르게 다루나

exit 3 은 "다른 프로세스가 이미 이 프로필을 쓰는 중" 이다. 재시작해도 같은
결과라서 상류의 systemd 유닛은 `RestartPreventExitStatus=3` 으로 뺀다. launchd
에는 대응하는 키가 없다.

그래서 래퍼 스크립트가 exit 3 을 0 으로 바꿔 보고한다. `KeepAlive.SuccessfulExit
= false` 는 0 을 재시작하지 않으므로 결과가 같아진다. 이유는 로그에 남는다.

같은 래퍼가 `/opt/homebrew/bin/orca` 가 아직 없을 때도 0 으로 빠진다. cask 가
깔리기 전 첫 부팅이 그 상태이고, 없는 것을 10초마다 다시 실행할 이유는 없다.

## PATH 를 손으로 쓰는 이유

launchd 에이전트는 셸 프로파일을 안 읽는다. 그런데 `orca serve` 는 git·claude·
codex 를 **서버 쪽 환경에서** 찾아 실행한다 — 원격 세션이 클라이언트의 PATH 를
쓰지 않는다는 것이 이 구조의 전제다. 그래서 래퍼가 home-manager 프로필,
시스템 프로필, Homebrew, 기본 시스템 순으로 PATH 를 명시한다.

같은 이유로 에이전트 계정도 서버에서 등록해야 한다. 원격 클라이언트는 Add
account 를 아예 막아 둔다. 절차는 [운영](../operations.md).
