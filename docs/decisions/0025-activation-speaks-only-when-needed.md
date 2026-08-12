# 0025. activation 이 말을 거는 기준

**결정** — 사람이 직접 해야만 끝나는 일이 남았을 때만 출력한다.

activation 스크립트와 여기서 만든 커맨드(`gpg-ssh-authorize` 등)는 **사람이
직접 해야만 끝나는 일이 남았을 때만** 출력한다. GPG 키가 없다, service token 이
없어서 브라우저 등록이 필요하다, plist 를 못 읽어서 건너뛰었다 — 이런 것들이다.

"configuring keyboard shortcuts..." 류의 진행 상황 보고와, 스크립트가 알아서
처리한 변경의 통보는 넣지 않는다. switch 할 때마다 같은 줄이 지나가면 읽지 않게
되고, 그러면 정작 읽어야 할 한 줄도 같이 흘러간다. 성공하면 조용한 쪽이 유닉스
관례이기도 하다.

이 규칙은 출력만이 아니라 **동작**도 정한다. 값을 쓰기 전에 먼저 읽어서 이미 맞으면
건너뛰는 코드들 — [클램쉘 데몬](0006-clamshell-only-while-on-power.md),
[roman-switch](0010-caps-lock-stays-caps-lock.md) — 이 그래서 그렇게 생겼다.
