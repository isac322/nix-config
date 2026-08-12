# 0009. 한/영 전환은 왜 F18을 거치는가

**결정** — 오른쪽 command 를 F18 로 보내고, F18 을 입력 소스 단축키에 묶는다.
단축키는 `defaults write -dict-add` 로 병합해 넣는다.

오른쪽 command를 `lang1`(0x90, 애플 한국어 키보드의 한/영 키가 보내는 usage)로
매핑하는 것은 hidutil이 받아들이기는 하지만 **macOS가 반응하지 않는다.** 동작하는
방법은 쓰지 않는 키를 보내고 그것을 입력 소스 단축키에 묶는 것이다.

```
오른쪽 command → F18 (hidutil)
F18 → 단축키 60번 "이전 입력 소스 선택" (com.apple.symbolichotkeys)
```

라틴 소스 하나와 한국어 소스 하나만 있으면 "이전 입력 소스"는 곧 한/영 토글이다.

단축키는 `system.defaults.CustomUserPreferences`가 아니라 activation 스크립트에서
`defaults write ... -dict-add`로 넣는다. `AppleSymbolicHotKeys`는 시스템의 모든
단축키를 담은 **하나의 딕셔너리**인데 nix-darwin은 키를 통째로 덮어쓰기 때문에,
그대로 쓰면 여기 적지 않은 스무 개 남짓이 사라진다. `-dict-add`는 병합한다.

`parameters`는 (ASCII 문자, 가상 키코드, 모디파이어 마스크)이고 65535는 대응하는
ASCII가 없다는 뜻이다. 마스크는 shift 131072, control 262144, option 524288,
command 1048576. Spotlight(64번)를 ⌥Space로 바꾸는 것도 같은 경로다.
