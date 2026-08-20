# 0032. 맥의 기본 로케일과 SSH 세션을 한국어 UTF-8로

**결정** — 두 macOS 호스트의 POSIX 로케일을 `ko_KR.UTF-8`로 고정한다. macOS 사용자
기본값에는 `AppleLocale = ko_KR`를 쓰고, 셸과 SSH 비로그인 명령에는
`LANG`·`LC_ALL`을 직접 제공한다.

## 왜 필요한가

현재 macOS의 기본 셸은 `en_US.UTF-8`이었고 `LC_ALL`은 비어 있었다. UTF-8 자체가
꺼진 것은 아니지만, SSH 클라이언트가 로케일을 보내지 않으면 세션은 접속하는 쪽과
서버의 기본값에 따라 달라진다. 그 결과 한글과 일부 유니코드 문자가 ASCII처럼
보이는 환경이 생긴다.

## 두 경로로 고정한다

`modules/darwin.nix`는 모든 Mac에 다음을 선언한다.

```nix
environment.variables = {
  LANG = "ko_KR.UTF-8";
  LC_ALL = "ko_KR.UTF-8";
};
```

이것을 `home.sessionVariables`에 넣지 않은 이유는 `ssh host command` 같은 비로그인
SSH 명령이 Home Manager의 세션 파일을 읽지 않기 때문이다. 시스템 환경 변수는
`/etc/zshenv`를 포함한 시스템 경로에서 제공된다.

macOS의 사용자 기본값은 별도로 `NSGlobalDomain AppleLocale`에 `ko_KR`로 쓴다.
이 값은 macOS 사용자 환경을 고정하고, POSIX 프로그램이 소비하는 인코딩 표기는
`LANG`·`LC_ALL`이 담당한다.

## SSH 서버 조각

모든 Mac은 `/etc/ssh/sshd_config.d/011-locale.conf`를 받는다.

```text
SetEnv LANG=ko_KR.UTF-8 LC_ALL=ko_KR.UTF-8
```

macOS가 제공하는 `100-macos.conf`에는 이미 `AcceptEnv LANG LC_*`가 있지만,
그것만 두면 접속하는 클라이언트가 어떤 로케일을 보내는지에 따라 결과가 달라진다.
`SetEnv`는 SSH 자식 세션의 값을 고정하고 클라이언트가 `AcceptEnv`로 보낸 값보다
우선한다.

파일 이름의 `011-` 접두사는 임의의 숫자가 아니다. `/etc/ssh/sshd_config`의
include glob은 사전순으로 읽히므로, `011-locale.conf`는 암호화 프로파일의
`010-ssh-audit-hardening.conf` 뒤에서 적용되고 Apple의 `100-macos.conf`와
nix-darwin의 `100-nix-darwin.conf`보다 먼저 읽힌다. 이 순서 규칙은
[0027](0027-ssh-audit-profile-shared-by-every-host.md)에 기록되어 있다.

서버 역할의 Mac에서 실제 sshd를 켜는 결정은
[0026](0026-sshd-on-the-server-mac.md)에 있고, 이 로케일 조각 자체는 두 Mac에
공통으로 선언된다. 따라서 Air에서 Remote Login을 켜도 Pro와 같은 UTF-8 정책을
사용한다.

## SSH 클라이언트도 전달한다

`home/darwin.nix`의 공통 SSH 설정은 다른 SSH 서버로 접속할 때 `LANG`과 `LC_*`를
`SendEnv`로 보낸다. 관리되는 Mac은 서버 쪽 `SetEnv`가 자체 정책을 우선하므로,
이 설정은 관리되지 않는 원격 서버에서도 현재 Mac의 UTF-8 로케일을 보존한다.
