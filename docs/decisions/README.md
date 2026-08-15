# 결정 기록

왜 이렇게 됐는지의 기록. 결정 하나에 파일 하나이고, 번호는 붙은 순서일 뿐 우선순위가
아니다. 무엇이 어디 있는지는 [레퍼런스](../reference.md), 손으로 하는 절차는
[운영](../operations.md).

## 구조

- [0001. 기기 전부를 한 레포에](0001-single-repo-single-lock.md) — lock 하나로 묶는 대가와 이득
- [0002. 상속이 아니라 조합](0002-compose-not-inherit.md) — 세 축을 푸는 방법, 공유 모듈에 넣으면 안 되는 것
- [0003. 맥에서는 nix-darwin 이 Nix 를 소유하지 않는다](0003-determinate-owns-nix-on-macos.md) — Determinate 와의 경계
- [0005. 호스트명이 설정을 고른다](0005-hostname-selects-the-configuration.md) — 이름을 설정 안에 두지 않는 이유
- [0023. `follows` 를 일부러 안 붙인 인풋](0023-inputs-without-follows.md)
- [0025. activation 이 말을 거는 기준](0025-activation-speaks-only-when-needed.md)

## 자격증명 · 네트워크

- [0004. 열쇠 하나로 셋 다](0004-one-gpg-key-for-ssh-signing-packaging.md) — SSH · 커밋 서명 · 패키징
- [0017. WARP 조직 등록은 mdm.xml 로](0017-warp-enrollment-via-mdm-xml.md)
- [0026. 서버 맥의 sshd](0026-sshd-on-the-server-mac.md) — 키 전용, 그리고 열쇠는 레포에 안 넣는다
- [0027. ssh-audit 권장값을 프로파일 하나로](0027-ssh-audit-profile-shared-by-every-host.md) — KEX와 P-256 공개키 호환 override
- [0029. 서버 맥의 WireGuard 는 앱이 아니라 루트 데몬](0029-wireguard-as-a-daemon-on-the-server-mac.md) — 앱은 콘솔 로그인이 있어야 한다

## 전원 · 하드웨어

- [0006. 전원 연결 중에만 뚜껑을 닫아도 안 자게](0006-clamshell-only-while-on-power.md)
- [0007. switch 가 비밀번호를 두 번 묻던 이유](0007-one-password-prompt-per-switch.md)

## 키보드 · 입력

- [0008. 키 리매핑은 Karabiner 가 아니라 hidutil](0008-hidutil-not-karabiner.md)
- [0009. 한/영 전환은 왜 F18을 거치는가](0009-hangul-toggle-via-f18.md)
- [0010. Caps Lock 한/영 전환 끄기](0010-caps-lock-stays-caps-lock.md) — `roman-switch`
- [0011. Esc 아래 키의 ₩ 문제](0011-won-sign-fixed-at-insertion.md)
- [0012. `activateSettings` 를 직접 부른다](0012-call-activate-settings-directly.md)

## 앱 · 터미널

- [0013. Ghostty — 설정이 파일이라서 골랐다](0013-ghostty-because-config-is-a-file.md)
- [0014. `xterm-ghostty` — 터미널 이름을 모르는 상대들](0014-xterm-ghostty-terminfo.md)
- [0015. GUI 앱은 Homebrew 에서](0015-gui-apps-come-from-homebrew.md)
- [0016. App Store 전용 앱 둘은 손으로 깐다](0016-mas-only-apps-installed-by-hand.md) — 그리고 없으면 switch 가 매번 알린다
- [0021. Firefox 정책을 두 경로로 넣는 이유](0021-firefox-policies-two-paths.md)
- [0022. Vim 이 vim-sensible 위에 얹히는 방식](0022-vim-on-top-of-vim-sensible.md)
- [0024. agent-browser 에게 브라우저를 쥐여주는 두 가지 방법](0024-chrome-for-agent-browser-on-the-server.md)
- [0028. 서버 맥에서 Orca 런타임을 계속 띄운다](0028-orca-runtime-on-the-server-mac.md) — LaunchAgent 가 콘솔 로그인에 안 묶이게

## 패키징 · 캐시

- [0018. 세 기기가 같은 것을 세 번 컴파일하지 않게](0018-cachix-not-flakehub-cache.md) — Cachix
- [0019. 소스 체크아웃이 아니라 배포된 아티팩트에서](0019-package-from-published-artifacts.md)
- [0020. `slack-cli` 는 attribute 를 갈아끼운다](0020-slack-cli-attribute-replaced.md)
