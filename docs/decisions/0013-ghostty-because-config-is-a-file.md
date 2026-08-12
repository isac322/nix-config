# 0013. Ghostty — 설정이 파일이라서 골랐다

**결정** — 랩탑 터미널로 Ghostty 를 쓰고, 앱 자체는 cask 로 깐다. 키바인딩 표는
[레퍼런스 · 터미널](../reference.md#터미널-ghostty).

quake 스타일 드롭다운(Ghostty가 "quick terminal"이라 부르는 것)이 내장이고,
`⌃\``로 어느 앱 위에서든 내려온다. 같은 기능을 Warp, iTerm2, Tabby도 내장으로 갖고
있다. Ghostty를 고른 이유는 **설정이 평범한 텍스트 파일**(`~/.config/ghostty/config`)
이기 때문이다. 나머지 셋은 GUI 환경설정 저장소에 값이 들어가서, 레포로 관리하려면
스냅샷을 뜨고 토글한 뒤 diff로 키를 찾아내는 짓을 해야 한다 — 이 레포에서 Liquid
Glass와 [Caps Lock](0010-caps-lock-stays-caps-lock.md)에 실제로 했던 그것이다.

앱은 cask다. nixpkgs의 `ghostty`는 `meta.platforms`에 darwin이 없다. home-manager
모듈이 이 경우를 문서화해 두었으므로 `programs.ghostty.package = null`로 두고
설치만 Homebrew에 맡긴다.

**전역 단축키에는 접근성 권한이 필요하다.** `global:` 접두사가 붙은 키바인딩은
다른 앱이 포커스를 가진 상태에서도 동작해야 하므로 macOS가 승인을 요구한다.
선언으로 없앨 수 없는 한 번의 GUI 단계다.

키를 고를 때는 macOS 자체 단축키 표(`DefaultShortcutsTable.xml`)와 이 기계의
`symbolichotkeys`를 대조해 충돌을 확인했다. F12(키코드 111)와 `⌘⌥R`은 비어
있었고, `⇧⌥` 조합은 시스템이 전혀 쓰지 않아 WASD 네 개가 모두 자유롭다.

**`⌘⌥D`만 충돌했다.** macOS의 "Dock 자동 숨기기 켜기/끄기"(단축키 52번)가 그
조합이고, **시스템 단축키는 앱 단축키보다 우선**이라 Ghostty가 이벤트를 아예 받지
못한다. 그래서 52번을 꺼 두었다 — `system.defaults.dock.autohide`를 여기서
고정하고 있으므로 그 토글은 어차피 다음 activation에 되돌려질 뿐이다.

**전역 단축키는 앱이 떠 있어야 동작한다.** 키를 듣는 주체가 실행 중인 앱이라,
Ghostty가 꺼져 있으면 F12도 `⌘⌥T`도 아무 일도 하지 않는다. macOS에는 키에 앱
실행을 묶는 기본 기능이 없다 — 키보드 단축키 설정은 이미 실행 중인 앱의 메뉴
항목에만 닿는다. 그래서 두 가지를 함께 건다.

- `launchd.user.agents.ghostty` (`modules/roles/darwin-laptop.nix`)가 로그인 때
  `open -g -a Ghostty --args --initial-window=false`로 띄운다. `-g`는 포커스를
  뺏지 않고, `--initial-window=false`는 그 실행에만 적용되므로 손으로 열 때는
  평소대로 창이 뜬다.
- `quit-after-last-window-closed = false`로 마지막 창을 닫아도 프로세스가 남는다.
  macOS 기본값이지만 이 구조 전체가 여기에 의존하므로 명시해 둔다.

**드롭다운 창에는 탭이 없다.** macOS 네이티브 탭 구현상의 제약으로 quick terminal
과 non-native fullscreen 둘 다 탭을 지원하지 않는다 (ghostty #2888, #3629).
분할은 되므로 분할 이동 키들이 그 자리를 메운다. 일반 창(`⌘⌥T`)에서는 `⌘T`로 탭이
정상 동작한다.

**한글은 폴백 체인으로 처리한다.** `font-family`를 여러 번 적으면 Ghostty가 위
폰트에 없는 코드포인트를 만났을 때 아래로 내려간다. JetBrains Mono에 한글이 없어서
두 번째 항목이 없으면 macOS가 아무 폰트나 고른다 — 그래서 한글만 어색해 보인다.
짝으로 D2Coding을 쓰는 이유는 한글 글자 폭이 ASCII의 정확히 두 배라서 터미널
격자가 안 깨지기 때문이다. 비례 한글 폰트는 이 조건을 만족하지 않고, 터미널에서는
그게 바로 티가 난다.
