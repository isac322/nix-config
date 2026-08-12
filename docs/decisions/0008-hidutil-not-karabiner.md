# 0008. 키 리매핑은 Karabiner 가 아니라 hidutil

**결정** — 모디파이어 회전을 hidutil 로 한다. 매핑 표는
[레퍼런스 · 키보드](../reference.md#키보드와-트랙패드).

**Karabiner-Elements를 쓰지 않는다.** 콘솔에 사람이 없으면 올릴 수 없기 때문이다.
DriverKit 확장을 시스템 설정에서 승인해야 하고, grabber에 입력 모니터링 권한이
필요한데 그 권한을 기록하는 TCC 데이터베이스는 SIP로 보호된다 — CLI도, defaults 키도
없다. MDM 프로파일만이 미리 허가할 수 있다.

hidutil은 그런 게 하나도 필요 없다. root로 IOKit 안에서 remap하고, 내장 키보드를
포함한 모든 키보드에 적용되며, `org.nixos.activate-system` LaunchDaemon이 부팅마다
다시 실행하므로 로그인 항목 없이 재부팅을 견딘다. 대가는 1:1 리매핑만 된다는 것 —
조건부·코드 규칙은 못 한다. 여기서 필요한 건 그 이상이 아니다.

한계가 드러나는 지점이 둘 있는데, 둘 다 hidutil 아래층이라 어차피 Karabiner 로도
못 푼다 — [한/영 키](0009-hangul-toggle-via-f18.md) 와
[₩](0011-won-sign-fixed-at-insertion.md).
