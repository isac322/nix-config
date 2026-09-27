# PR 백로그 ledger (바꿀 수 있는 기본값)

SKILL.md 2절의 상태 기계를 기록하는 형식이다. 대상 저장소 밖 scratch 디렉터리에 둔다. PR별 감사 산출물(dossier, result, comment 초안)은 `isac-pr-review`의 외부·오래된 PR 감사 형식을 쓰고, 여기에는 링크만 둔다.

## 실행 머리

- 저장소, 기본 브랜치, 시작·끝 main HEAD
- 이번 실행의 허용 종착 행동(E2P-01)과 지시가 준 우선순위
- 시작·끝 열린 PR 목록 대조 결과(E2P-03)

## PR 행

| 필드 | 내용 |
|---|---|
| PR | 번호, 작성자 종류(외부 / 봇 / 에이전트 / 사용자) |
| 상태 | `intake` / `audited` / `unit` / `fixing` / `updating` / `gate` / `merged` / `closed` / `left-open` |
| head | 판정·머지 시점의 head SHA와 base SHA |
| 판정 | `isac-pr-review` 판정 어휘, PR-ready |
| 결정 단위 | E2P-05 단위 |
| 겹침 | 같은 문제를 겨냥한 PR 번호와 관계(subset / superset / 충돌) |
| 순서 | 머지 순번과 이유 |
| 머지 방식 | 일반 / 관리자 우회(근거: 전역 가드 기본값 / 이번 승인) |
| 증거 | 감사 산출물, CI run, 머지 커밋, 게시 댓글 URL |
| 사유 | `left-open`이면 권한 없음 / 외부 blocker / 사용자 결정 대기 / 범위 밖 |

## 전이 기록

전이마다 한 줄: 시각, PR, 이전 → 다음 상태, head SHA, 근거. 형제 PR 머지로 무효가 된 판정(E2P-08)은 무효 표시 후 새 줄로 다시 쓴다.

## 끝

- 최종 main HEAD, main CI 결과
- 남은 main 문제 목록 위치(E2P-13)와 다음 경로(E2P-14). 항목 필드 기본값: 증상, 원인 코드 위치, 재현 여부·환경·횟수, 로그 경로
- 정리한 리소스와 남긴 산출물(E2P-15)
