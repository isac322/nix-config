---
name: isac-e2e-pr-backlog
description: Use when taking a set of open pull requests (external contributions, dependabot, agent-made PRs) end to end through a merge pass — audit each PR, group verdicts into decision units, push fixes or update branches to the latest main, merge one at a time checking main after each merge, close superseded PRs with an evidence comment and the version to use, then summarize what remains broken on main; including "열린 PR 다 정리하고 머지까지 해", "PR들 최신화해서 CI 통과하면 하나씩 머지해", "PR 백로그 처리해", "subset PR 먼저 머지해", "dependabot PR들 머지해". Not for reviewing a single PR, verdict-only audits, or auditing stale PRs and closing superseded ones without a merge pass (isac-pr-review), fixing one issue into a PR (isac-issue-to-pr), taking issues end to end (isac-e2e-issue-resolution), or answering review feedback on your own PR (receiving-code-review).
---

# E2E PR Backlog

열린 PR 묶음을 감사 → 판정 → 결정 단위 → PR별 조치(수정 push, 최신화, 순차 머지, 근거 댓글과 close) → 남은 main 문제 정리 → 보고까지 끈다. 이 스킬은 오케스트레이터다. 대상·권한 확정, PR별 상태 기계, 순서, ledger, 멈춤 조건, 최종 보고만 소유한다.

`[U]` = 사용자 지시·교정·승인에서 온 규칙(사용자 승인 없이 완화·삭제 불가). 태그 없음 = 바꿀 수 있는 기본값.

## 경계

- PR 한 건의 감사·판정·리뷰 이벤트·닫기 코멘트·superseded 증명: `isac-pr-review`(PRR, 절차는 그 스킬의 외부·오래된 PR 감사 참조). 판정 어휘와 결정 단위 묶음도 그 스킬 것을 쓴다(PRR-24, PRR-31).
- PR 브랜치에 넣을 수정: `isac-issue-to-pr`의 QA list·TDD·회귀 증명(I2P-22–I2P-28), CI(I2P-46–I2P-47), 머지 게이트(I2P-52), 여러 PR 순차 머지(I2P-54). 남은 main 결함의 판정: `isac-issue-triage`. 남은 결함을 끝까지 고치기: `isac-e2e-issue-resolution`.
- 독립 조사·교차 검증·리뷰-GREEN 루프: `isac-multi-agent-consensus`. GitHub 게시: `isac-github-publishing`. 사용자 질문 형식: `isac-decision-brief`.
- 전역 가드(task-intent, application-code 승인, PR 머지 승인, PR 리뷰 가드, destructive, verification)는 이름으로만 따른다. 가드와 충돌하면 이 스킬이 진다.
- 릴리스는 범위 밖이다. 사용자가 끝에 릴리스를 지시하면 그 지시를 따르되 절차를 여기 쓰지 않는다.

## 0. 프로젝트 훅

`gh repo view --json nameWithOwner,visibility,defaultBranchRef`로 대상 저장소와 기본 브랜치를 확인한다. 이 스킬의 `references/projects/<owner>__<repo>.md`가 있으면 먼저 읽는다(공개 저장소만 둔다). 비공개 저장소의 프로젝트 사실은 그 저장소 자체 지침(AGENTS.md, `.agents/skills`)에 있다. 프로젝트 문서는 기본값을 좁히거나 구체화할 수 있지만 `[U]` 규칙과 전역 가드를 완화하지 못한다. 프로젝트 문서에는 `## Overrides`(규칙 ID 기준)와 `## Cases`를 두고, 첫 프로젝트 교정 때 만든다.

## 1. Intake와 권한

- **E2P-01** [U] 대상 PR과 이번 실행에서 허용된 종착 행동(판정 코멘트만 / 수정 push / 최신화 / 머지 / close)은 이번 실행의 사용자 지시에서 정한다. 머지는 I2P-53과 전역 머지 가드, close는 PRR-02에 따른다. 지시가 주는 우선순위·카테고리(예: 특정 봇 PR 먼저)는 그 실행에만 적용하고 일반 정책으로 넓히지 않는다. 대상·권한이 정말 불명확할 때만 `isac-decision-brief`로 한 번에 묻고, 증거로 정할 수 있는 범위 판단은 묻지 않는다(DBR-01, DBR-03).
- **E2P-02** [U] 머지 방식(관리자 우회 포함)은 전역 머지 가드를 따른다. 그 가드의 기본값이 적용되는 PR은 PR마다 우회 승인을 묻지 않는다. 그 밖의 우회는 가드대로 새 승인을 받고, PR 한 건의 우회 승인을 다른 PR로 넓히지 않는다(DBR-04). PR마다 머지 방식과 근거(가드 기본값 / 이번 승인)를 ledger에 적는다.
- **E2P-03** 대상 목록과 시작·끝 재대조는 `isac-pr-review` 외부·오래된 PR 감사 절차를 쓴다. 실행 중 새로 열린 PR은 범위 밖으로 기록하고 보고한다.

## 2. PR 상태 기계

전이마다 ledger에 head SHA와 증거 링크를 남긴다(`references/ledger.md`).

| 현재 | 조건 | 다음 |
|---|---|---|
| `intake` | 감사 완료(E2P-04) | `audited` |
| `audited` | 결정 단위 확정(E2P-05) | `unit` |
| `unit` | 허용된 행동 없음(확인만: PRR-01 코멘트까지) | `left-open`(권한 없음) |
| `unit` | superseded·close-without-merge이고 닫기 지시 있음 | `closed`(E2P-12) |
| `unit` | 수정 필요, push 허용 | `fixing` |
| `unit` | 머지 대상 | `updating` |
| `unit` | 사용자 결정 필요 | `left-open`(사용자 결정 대기) |
| `fixing` | 리뷰-GREEN 루프 종료(MAC-16) | `updating` |
| `updating` | 최신화 후 PR 고유 변경만 남음(E2P-09), 봇 rebase 완료(E2P-10) | `gate` |
| `updating` | 무관한 변경이 계속 남음(E2P-09) | `left-open`(사용자 결정 대기) |
| `updating` | 머지된 내용을 빼니 남는 것 없음(E2P-06), 닫기 지시 있음 | `closed`(없으면 `left-open` 권한 없음) |
| `gate` | PRR-24 `GREEN`·`PR-ready: true`, 우리가 push했으면 I2P-52도 충족, 머지 지시 있음 | `merged` |
| `gate` | 조건 충족, 머지 지시 없음 | `left-open`(권한 없음) |
| `gate` | CI 실패, push 허용 | `fixing` |
| `gate` | CI 실패, push 불허 | `left-open`(권한 없음) |
| 비종착 전부 | 형제 PR 머지(E2P-08) | `updating` |
| 비종착 전부 | fork 권한·필요 승인 없음(E2P-11) | `left-open`(외부 blocker) |

실행 수준: 한 PR의 `left-open`은 다른 PR을 막지 않는다. 머지 후 main CI가 깨지면 남은 머지를 모두 멈추고(E2P-07), main CI가 다시 green이 될 때까지 남은 PR은 `left-open`(외부 blocker: main CI 실패)이다. 모든 PR이 종착이면 4절로 간다.

- **E2P-04** 감사는 PR마다 owner 에이전트가 `isac-pr-review` 절차로 한다(병렬은 MAC-03, 도중 사용자 교정 전파는 MAC-07). 문제 실재·재현·근본 원인·그 원인을 고치는 PR인지(PRR-08, PRR-09), 연결 이슈 없는 PR도 같은 순서(PRR-10), 여전히 필요한지(PRR-17)를 본다. 이슈를 새로 만들지 않고 PR 댓글이나 PR 브랜치 push로 처리한다(PRR-10, PRR-03). 사용자가 "앞에서 한 방식 그대로"를 요구하면 그 세션 기록에서 실제 절차를 찾아 재사용한다(I2P-08).
- **E2P-05** 판정은 PRR-31의 결정 단위로 묶는다. 작성자 종류(외부 / 봇 / 에이전트)는 ledger 필드로 둔다. 같은 문제를 겨냥한 PR끼리의 겹침(subset·superset·충돌)을 이 단계에서 ledger에 기록한다.

## 3. 순서와 실행

- **E2P-06** [U] 이미 검증돼 머지만 남은 PR들이 같은 문제를 겹쳐 겨냥하면 문제 범위가 더 작은 subset PR을 먼저 머지한다. 그 뒤 superset PR을 최신 main으로 올리고, 이미 머지된 내용을 그 PR에서 빼 남은 범위만 다시 리뷰한 다음 머지한다. 빼고 나서 남는 것이 없으면 superseded 판정으로 기록하고, 닫기는 E2P-12를 따른다.
- **E2P-07** [U] 순차 머지와 형제 머지 후 재검증은 I2P-54, 머지 후보 판정은 PRR-24 `PR-ready`를 따른다. 여기서 더하는 것: 머지할 때마다 main CI를 확인한다. 깨지면 남은 머지를 모두 멈추고 원인을 진단해 보고하며, 수정은 E2P-14 경로로 넘긴다. main CI가 다시 green이면 남은 PR을 `updating`부터 재개한다. PR CI 실패는 PR 브랜치에서 진짜 원인을 고친다(I2P-47, PRR-03).
- **E2P-08** 형제 PR이 머지되면 남은 PR을 `updating`으로 되돌리고 겹침(E2P-05)을 다시 기록한다(I2P-54, MAC-20, PRR-37). head가 바뀌면 전역 리뷰 가드대로 리뷰를 다시 받는다.
- **E2P-09** [U] 최신화나 rebase 후 PR diff나 적용 계획(IaC plan 등)에 그 PR과 무관한 변경이 섞이면 적용·머지하지 않는다. 다시 최신화해 PR 고유 변경만 남았는지 증거로 확인하고, 사용자가 조건부 진행("X만 보이면 끝까지")을 줬으면 DBR-13대로 평가한다. 무관한 변경의 출처(다른 PR 머지, provider 계산 노이즈)를 구분해 적는다(DBR-21).
- **E2P-10** [U] 의존성 업데이트 봇 PR은 봇의 rebase가 끝난 head에서 CI와 앱 동작 확인(설치·실행 경로)을 마친 뒤 머지한다. 사용자가 봇 rebase를 요청해 뒀으면 완료를 기다린다.
- **E2P-11** 수정이 필요한 PR은 승인 범위 안에서 PR 브랜치에 push한다(PRR-03). 수정 자체는 경계에 적은 `isac-issue-to-pr` 단계를 따르고 리뷰-GREEN 루프(MAC-16)를 거친다. fork 권한이 없거나 GitHub 설정상 필요한 승인이 없으면 외부 blocker로 `left-open` 처리하고 보고한다(PRR-28, I2P-50).
- **E2P-12** `closed` 전이 조건은 PRR-02(닫기 지시), PRR-33–PRR-35(증명·재검증·닫기 코멘트·사용할 버전·예외), GHP-12("제거"는 close)를 따른다.
- head 브랜치 삭제는 전역 머지 가드를 따른다.

## 4. 종착 후 정리

- **E2P-13** [U] 모든 머지·close가 끝나면 최종 main HEAD 기준으로 "main에 남은 문제"를 다시 정리한다(형식·전달은 PRR-32). 모을 대상: 감사 중 드러났지만 PR로 고치지 않은 결함, 머지한 PR의 알려진 한계, CI에서만 보이는 실패. 항목 필드 기본값은 `references/ledger.md`의 끝 절.
- **E2P-14** 남은 결함의 다음 경로: 고치라는 지시가 있으면 `isac-e2e-issue-resolution`, 판정만이면 `isac-issue-triage`, 업스트림 결함이면 TRI-06·TRI-46. 새 이슈는 사용자가 요청할 때만 만든다(PRR-10, GHP-10). 이 스킬 안에서 새 수정 PR을 만들지 않는다.
- **E2P-15** [U] 이 실행이 만든 임시 리소스(worktree, 컨테이너, 이미지, scratch, 테스트 리소스)는 끝에 모두 정리하고 보고에 적는다.
- 사용자가 계속 봐야 하는 산출물(보고 페이지 등)은 남기고 위치를 알린다.

## 5. 보고 (한국어)

- **E2P-16** 최종 보고 순서: (1) 결론 한 줄(머지 N, close N, 남은 열린 PR N) (2) PR 표: 번호·제목 요지 / 판정 / 결정 단위 / 한 조치(push·최신화·머지·close) / head SHA·머지 커밋 / 근거 링크 (3) 머지 순서와 그 이유(겹침, subset, CI) (4) `left-open` PR과 사유 (5) main에 남은 문제 요약과 다음 경로(E2P-13, E2P-14) (6) 릴리스 여부: main에만 있고 릴리스 안 된 수정이 있으면 알린다(PRR-35, I2P-60) (7) 정리한 리소스. 판정 단위마다 무엇이 바뀌었고 무엇이 남았는지 설명한다(PRR-31).
- 실행 중 사용자가 교정한 것이 있으면 보고 끝에 한 줄로 알린다.

## 교정 루프

결과가 기대와 다르면 사용자는 `isac-skill-correction`으로 이 스킬을 교정할 수 있다. 실행 중 사용자가 교정했다면 따로 묻지 말고 최종 보고에 한 줄로 안내한다. `references/cases.md`는 교정할 때만 읽는다.
