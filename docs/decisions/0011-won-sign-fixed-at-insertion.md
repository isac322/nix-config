# 0011. Esc 아래 키의 ₩ 문제

**결정** — 키 리매핑이 아니라 문자가 삽입되는 지점에서 고친다.

`~/Library/KeyBindings/DefaultKeyBinding.dict`로 해결한다.

```
{
    "₩" = ("insertText:", "`");
}
```

키 리매핑으로는 풀 수 없다. ₩는 2벌식 레이아웃이 그렇게 정한 결과이고 그 레이아웃은
hidutil이나 Karabiner보다 하류에 있어서, 어떤 키가 도착하는지는 바꿀 수 있어도
레이아웃이 무엇을 만들지는 못 바꾼다. 입력 소스를 잠깐 빠져나갔다 돌아오는 우회가
있지만 upstream이 그걸 막는다 —
"switching to input sources which have input_mode_id (Chinese, Japanese, **Korean**,
Vietnamese) may be failed due to an macOS issue."

그래서 문자가 실제로 삽입되는 지점에서 고친다. Cocoa 텍스트 시스템이 이 파일을 읽고,
₩를 넣으려던 자리에 백틱을 넣는다. 한글 모드·영문 모드 모두 해당된다.

**한계:** Cocoa 메커니즘이라 자체 텍스트 스택을 그리는 앱(Electron, JetBrains, 일부
터미널)에는 적용되지 않는다. 앱은 실행 시점에 이 파일을 읽으므로 첫 적용 후 재시작이
필요하다.
