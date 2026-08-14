# 0024. agent-browser 에게 브라우저를 쥐여주는 두 가지 방법

**결정** — 랩탑은 캐스크 크롬의 자동 탐지에 맡기고, 서버 맥은 nixpkgs 크롬을
환경변수로 직접 가리킨다.

`agent-browser` 는 크롬을 세 군데서 찾는다: `AGENT_BROWSER_EXECUTABLE_PATH`,
Playwright 캐시, 그리고 `/Applications` 밑의 네 경로 — Google Chrome, Chrome
Canary, Chromium, Brave. 마지막 것이 **하드코딩된 절대 경로**라는 게 핵심이다.

- **랩탑은 아무것도 안 해도 된다.** `google-chrome` 캐스크가 크롬을 정확히
  `/Applications/Google Chrome.app` 에 놓기 때문에 자동 탐지에 그대로 걸린다.
  `agent-browser doctor` 가 `pass Google Chrome 151.0.7922.109` 를 찍는다.
- **서버 맥은 nixpkgs 에서 받고, 경로를 손으로 알려준다**
  (`modules/roles/darwin-server.nix`). 아무도 안 쓰는 기기에 캐스크로 자동
  업데이트되는 브라우저를 둘 이유가 없어서 nixpkgs 쪽을 골랐다 — 클로저와 같이
  핀 되고, activation 중에 root 를 요구하는 `pkg` 아티팩트도 없다. 대신 nixpkgs
  는 구글 DMG 를 `/Applications` 가 아니라 `$out/Applications` 에 푼다. 스토어
  경로는 위의 네 경로 중 어느 것도 아니므로 자동 탐지가 절대 못 찾고,
  `AGENT_BROWSER_EXECUTABLE_PATH` 로 직접 가리켜야 한다.

`home.sessionVariables` 가 아니라 `environment.variables` 인 이유는 이 기기를
SSH 로 몰기 때문이다. `/etc/zshenv` 는 모든 zsh 가 읽지만 home-manager 의
세션 파일은 로그인·인터랙티브 셸만 읽는데, `ssh <server> agent-browser …` 는 둘 다
아니다.

`doctor` 의 `Chrome` 항목은 이 환경변수를 무시하고 자동 탐지 결과만 보여준다 —
랩탑에서 환경변수를 nix 크롬으로 덮어씌워도 캐스크 경로를 계속 찍는다. 표시만
그럴 뿐 실행에는 환경변수가 이긴다: 없는 경로를 넣으면 `Launch test` 가
`Failed to launch Chrome at "…"` 로 떨어지고, nix 크롬을 넣으면 통과한다.

## 그 뒤 — `systemPackages` 에서 뺐다

크롬은 `environment.systemPackages` 에 있었는데 거기서 뺐다. 절대경로로 지목한다는
위의 결론이 바뀐 것이 아니라, **오히려 그 결론 덕분에 뺄 수 있었다.**

`systemPackages` 에 있으면 nix-darwin 이 `/Applications/Nix Apps` 에 번들을 만든다.
그리고 nix-darwin 의 검사는 그 디렉터리 아래 번들마다 `touch` 를 시도해 수정 권한을
확인하는데, SSH 세션에는 그 권한이 없다 — "Allow full disk access for remote users"
를 손으로 켜야 하고, 상류 주석은 그걸 켜도 "will still fail sometimes" 라고 적어
두었다. 즉 번들 하나 때문에 **헤드리스 기계가 원격으로 switch 불가능**해진다.

거기 있던 번들은 크롬 하나뿐이었다. 빼면 검사할 것이 없어 루프가 통과한다. 잃는
것도 없다 — agent-browser 는 PATH 도 `/Applications` 도 안 보고, 패키지는
`AGENT_BROWSER_EXECUTABLE_PATH` 가 `/etc/zshenv` 에 박히면서 클로저에 남는다.
Nix 가 출력에서 store 경로 문자열을 훑기 때문이다.
