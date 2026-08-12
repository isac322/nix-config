# 0010. Caps Lock 한/영 전환 끄기 — `roman-switch`

**결정** — defaults 키가 없는 설정이라, HIToolbox 의 비공개 함수를 부르는 작은 C
프로그램을 빌드해 activation 때 실행한다.

macOS Sierra 이후, 한국어 입력 소스가 있으면 **Caps Lock이 기본적으로 한/영
전환**이고 길게 누르면 본래의 대문자 잠금이 된다. 여기서는 Caps Lock을 Caps Lock으로
두고 한/영은 [오른쪽 command 가 맡는다](0009-hangul-toggle-via-f18.md).

**이 설정에는 defaults 키가 없다.** 토글을 움직여도 어느 plist에도 나타나지 않는다.
시스템 설정이 HIToolbox의 비공개 함수를 호출하기 때문이다. Keyboard 설정 확장
바이너리의 임포트 심볼을 보면 드러난다.

```
_TISIsRomanSwitchAllowed
_TISIsRomanSwitchEnabled
_TISSetRomanSwitchState
```

"Roman switch"가 이 기능의 내부 이름이다. `modules/keyboard.nix`가 이 셋을
Carbon.framework에서 `dlsym`으로 찾아 호출하는 작은 C 프로그램을 빌드해서 activation
때 실행한다. 왕복 테스트로 확인했다 — `off` → `enabled=0`, `on` → `enabled=1`.

비공개 API라 macOS 업데이트로 사라질 수 있다. 그래서 심볼을 못 찾으면 경고만 남기고
0으로 종료해 activation을 막지 않는다. `TISIsRomanSwitchAllowed()`가 거짓이면
(비라틴 입력 소스가 없으면) 아무것도 하지 않고, 이미 원하는 상태면 건너뛴다.

키 리매핑으로는 우회할 수 없다는 점도 적어 둔다. macOS가 caps lock 이벤트 자체를
가로채므로, 다른 키를 caps lock으로 보내면 그 키도 똑같이 한/영 전환이 된다.
