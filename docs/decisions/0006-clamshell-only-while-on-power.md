# 0006. 전원 연결 중에만 뚜껑을 닫아도 안 자게

**결정** — 유휴 타이머는 전원별로 선언하고, 뚜껑은 데몬이 전원을 지켜보며 처리한다.

서버 맥은 MacBook Pro 를 뚜껑 닫고 SSH 로만 쓰는 기계다. 요구는 처음부터
조건부였다 — **어댑터에 물려 있는 동안만** 클램쉘. 전원이 끊기면 다시 랩탑처럼
자야 한다. 배터리로도 안 자는 기계는 뚜껑 닫은 채 방전으로 끝나고, 그 뒤로는
아예 꺼진 기계다.

**유휴 타이머는 전원별로 쓸 수 있다.** macOS 에 그 옵션이 있다 — 시스템 설정 →
디스플레이 → 고급의 "디스플레이가 꺼져 있을 때 전원 어댑터 사용 시 컴퓨터를
자동으로 잠자지 않게 하기"(벤투라 이전에는 배터리 → 옵션에 있었다)이고, 실체는
`pmset -c sleep 0` 이다.
`-c` 가 어댑터 딕셔너리, `-b` 가 배터리 딕셔너리라 둘을 따로 쓴다:

```nix
/usr/bin/pmset -c sleep 0 disksleep 0 displaysleep 10
/usr/bin/pmset -b sleep 10 disksleep 10 displaysleep 2
```

nix-darwin 의 `power.sleep.*` 을 여기서 안 쓰는 이유가 이것이다. 그 옵션들은
`systemsetup -setComputerSleep` 계열을 모는데, 값을 하나만 받고 전원이라는 축이
아예 없다. 어댑터와 배터리가 달라야 한다는 게 이 역할의 전부라서 pmset 을 직접
쓴다. `ttyskeepawake` 는 기본으로 켜져 있고 살아 있는 SSH 세션을 활동으로 세므로,
배터리 타이머가 작업 중인 세션을 끊지는 않는다.

**뚜껑은 그 타이머가 안 덮는다.** 닫는 것은 잠들기로 가는 별개의 경로다 — 리드
스위치가 `IOPMrootDomain` 에 직접 잠들라고 하므로 `sleep 0` 인 기계도 뚜껑이
본체에 닿는 순간 내려간다. `caffeinate` 도 답이 아니다. 그건 power assertion 을
잡는데, assertion 을 참조하는 것은 리드 스위치가 아니라 유휴 타이머다. 애플의 정식
클램쉘 모드는 **외장 디스플레이 + 전원 + 입력장치**가 전제인데 이 기계는 셋 다 없다.

남는 것이 `SleepDisabled` 다. `IOPMrootDomain` 이 리드를 포함한 **모든** 출처의
잠들기에 대한 거부권으로 취급하는 커널 플래그이고, 세우는 방법은
`pmset -a disablesleep 1` 하나뿐이다 — nix-darwin 옵션도 없고 man page 에도 없다.
그리고 **이것만은 전원별 형태가 없다.** 보통의 pmset 설정은 전원별 딕셔너리에
들어가는데(`pmset -g cap` 이 각 전원이 받는 목록을 찍고, `disablesleep` 은 어느
쪽에도 없다), `SleepDisabled` 는
`/Library/Preferences/com.apple.PowerManagement.plist` 의 `SystemPowerSettings`
아래 단일 키다. `pmset -c disablesleep 1` 도 받아들여지지만 똑같은 전역 키를 쓴다 —
`-c` 는 장식이다.

그래서 조건을 **선언하는 대신 지켜본다.** `launchd.daemons.clamshell-on-power` 가
`pmset -g pslog` 를 따라간다. 이건 이벤트 스트림이라 시작할 때 현재 전원을 한 줄
찍고 그 뒤로는 바뀔 때마다 `Now drawing from 'X'` 한 줄씩만 나오고, 파이프를
통과해도 줄 단위로 흘러서 폴링할 것이 없다. 어댑터면 1, 아니면 0. activation
스크립트가 아니라 데몬인 이유는 전원이 activation 이 끝난 한참 뒤에 바뀌기
때문이고, 이 일을 하는 서드파티 도구들도 같은 모양이다.

두 가지가 덜 자명하다.

- **배터리로 떨어질 때 이미 뚜껑이 닫혀 있으면** 명시적으로 재워야 한다. 거부권을
  내리는 것은 거부권을 내리는 것일 뿐, 그 거부권이 삼킨 리드 이벤트를 다시
  보내주지는 않는다. 그래서 `AppleClamshellState` 를 `ioreg` 로 확인하고
  `pmset sleepnow` 를 부른다.
- **시작 시 호출은 그걸 하지 않는다.** 방금 설치된 데몬이 제일 하면 안 되는 일이
  자기를 설치한 `switch` 도중에 기계를 재우는 것이다.

값을 먼저 읽는 것은 최적화가 아니다 — pmset 은 같은 값을 다시 써도 불평하지
않는다. [할 일이 없으면 아무 말도 하지
않는다](0025-activation-speaks-only-when-needed.md)는 규칙 때문이다. 플래그가 꺼져
있는 동안 `pmset -g` 는 그 줄을 아예 빼므로, 빈 결과는 "모름"이 아니라 0 으로
읽어야 한다.

**남는 위험 하나.** 일단 잠들면 데몬도 같이 자므로, 어댑터가 돌아왔을 때 깨우는
것은 macOS 몫이다. 그걸 정하던 `acwake` 는 애플 실리콘에서 죽은 설정이라
(`pmset -g cap` 에 없고 써도 안 먹는다) 동작이 기종에 박혀 있다. 이 기계가 어댑터로
안 깨는 쪽이면, 배터리 타이머보다 긴 정전은 사람이 뚜껑을 열어야 끝난다. 전원이
아예 나갔다 들어온 경우는 `restartAfterPowerFailure` 가 받는다.

데몬이 조용히 죽어서 뚜껑 뒤에서 기계가 자고 있는 것이 볼 수 있어야 할 실패라서,
stderr 는 `/var/log/clamshell-on-power.err.log` 로 남는다. 정상이면 비어 있다.
