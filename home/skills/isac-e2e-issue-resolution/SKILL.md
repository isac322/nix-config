---
name: isac-e2e-issue-resolution
description: Use when driving one or many GitHub issues (including a whole open backlog) end to end — confirm scope and merge authorization, sweep duplicates across all open issues first, use one owner subagent per issue when there are several, and walk each issue through triage → fix PR → independent review → merge → closure comment, or stop it at a terminal state (duplicate, not reproduced, needs info, intended behavior, awaiting structural approval, existing open PR, merge not authorized, merged and closed, external blocker); including "이슈들 전부 해결해", "백로그 이슈 정리하고 해결까지", "이슈마다 서브에이전트 붙여서 해결해", "이슈 재현부터 머지하고 닫는 것까지 해", "이슈 고치고 머지하고 닫아". Not for a single step — triage or labels only (isac-issue-triage); already-triaged issues with a decided fix direction that only need PRs, even several (isac-issue-to-pr); reviewing a PR (isac-pr-review); filing issues from live exploration (isac-live-qa); open-PR backlogs (isac-e2e-pr-backlog); QA → issue → re-verify loops (isac-e2e-qa-to-fix).
---

# E2E Issue Resolution

이슈 1개~N개(백로그 전체 포함)를 intake부터 이슈별 종착 상태까지 끌고 가는 **오케스트레이터**다. 단계 안의 규칙(재현, 판정, 라벨, 댓글 형식, QA list 토론, TDD, CI, 리뷰 차원, 게시 문체, 질문 형식)은 step·공유 스킬이 소유하고, 여기서는 스킬 이름과 규칙 ID로만 참조한다. 같은 규칙을 여기 다시 쓰지 않는다.

`[U]` = 사용자 지시·교정·승인에서 온 규칙(사용자 승인 없이 완화·삭제 불가). 태그 없음 = 바꿀 수 있는 기본값.

## 소유와 경계

- 소유: intake·범위 확정, 대량 run의 중복 정리 순서, 이슈별 상태 기계(단계·전이 게이트·종착 상태), 단계별 step 스킬 호출, 항목별 병렬 배치, 진행 ledger, 멈춤/계속 조건, 최종 보고 형식.
- 호출: `isac-issue-triage`(재현·판정·근본 원인·방향·라벨·분석 댓글), `isac-issue-to-pr`(QA list·TDD·PR·CI·머지 게이트·종료 댓글), `isac-pr-review`(독립 PR 판정), `isac-multi-agent-consensus`(항목별 owner·토론·리뷰-GREEN 루프), `isac-github-publishing`(모든 GitHub 쓰기), `isac-decision-brief`(묻는 형식).
- 전역 가드(task-intent, application-code 승인, PR 생성·머지, PR 리뷰, destructive, verification)는 이름으로만 따른다. 머지는 그 run의 사용자 지시가 있을 때만 한다(I2P-53). 계획 단계에서 결정된 변경은 구현 때 다시 묻지 않는다(I2P-14).
- 인접 e2e: 열린 PR 묶음은 `isac-e2e-pr-backlog`, 라이브 QA에서 시작하는 루프는 `isac-e2e-qa-to-fix`(그 루프가 등록한 이슈를 이 스킬이 intake로 받는다).
- 릴리스·배포는 범위 밖이다(E2I-17).

## 0. 프로젝트 훅과 모드

`gh repo view --json nameWithOwner,visibility,defaultBranchRef`로 대상 저장소와 기본 브랜치를 확인한다. 이 스킬의 `references/projects/<owner>__<repo>.md`가 있으면 먼저 읽는다(공개 저장소 문서만 여기 둔다). 비공개 저장소의 프로젝트 사실은 그 저장소 자체 지침(AGENTS.md, `.agents/skills`)에 있다. 프로젝트 문서는 기본값을 좁히거나 구체화만 하고 `[U]` 규칙과 전역 가드를 완화할 수 없다.

게시 모드와 초안 모드는 `isac-github-publishing`으로 판별한다(GHP-01). 분석만 요청한 run은 ledger·종착 판정·댓글/PR 초안까지만 만들고 최종 보고에 게시 가능함을 한 줄로 알린다.

## 1. Intake와 범위 확정

- **E2I-01** [U] fan-out 전에 범위를 확정해 ledger 머리에 적는다: 대상 저장소, 대상 이슈(명시 번호 / 부분집합 / 열린 이슈 전부), 게시 모드, 이 run의 머지 승인 여부와 범위. 머지 승인은 그 run의 지시로만 판정하고, 지시가 지목한 이슈·PR에만 적용한다(I2P-53). 지시가 없으면 머지하지 않는 run이다. 대상이나 머지 범위를 지시에서 정할 수 없으면 그 부분만 `isac-decision-brief`로 묻고 나머지는 진행한다.
- **E2I-02** 확정한 범위를 run 시작 보고에 한 줄로 밝힌다. 인벤토리(open·closed 이슈와 열린 PR, 중간 신규 이슈 편입과 완료 전 재조회)는 TRI-02를 따른다.
- **E2I-03** 이슈 지목이 아닌 동반 요청은 파이프라인에 넣지 않고 해당 절차로 응답한다: 기능·enabler 이슈에 대한 질문은 TRI-35 브리핑, 남은 이슈 요약 요청은 TRI-34 형식. 사용자가 명시로 넣지 않은 기능 요청·제안 이슈는 결함 파이프라인 밖으로 분류한다(TRI-03).

## 2. 중복 정리(owner 배치 전)

- **E2I-04** [U] 대상이 둘 이상인 run은 어떤 이슈에도 owner를 붙이기 전에 대상 이슈 전체와 그것과 겹칠 수 있는 열린 이슈를 한 번 훑는 중복 정리 단계를 끝낸다(대상이 백로그 전체면 열린 이슈 전체). 판정 방법은 TRI-04, TRI-41을 따른다. 정본만 다음 단계로 보내고 나머지는 ledger에 종착 `중복`으로 기록한다. 이 단계는 owner별로 나눠 하지 않는다(서로 다른 owner가 같은 원인을 병렬로 고치는 것을 막는다).
- **E2I-05** 대상이 하나인 run은 전체 스윕을 하지 않는다(중복 후보 확인은 TRI-04). 바로 트리아지로 가고, 담당은 E2I-08 또는 E2I-20으로 정한다.

## 3. 이슈별 상태 기계

단계: `중복정리` → `트리아지` → `수정` → `리뷰` → `머지` → `종결알림`. 전이 게이트, 종착 상태 목록, 전이별 게시물은 `references/state-machine.md`를 읽고 따른다. 단계별 호출:

| 단계 | 담당 | 호출 스킬과 규칙 |
|---|---|---|
| 트리아지 | owner | `isac-issue-triage` 전체(재현 TRI-07~09, 판정 TRI-51, 근본 원인 TRI-17~22, 방향 TRI-24/25/44, 라벨 TRI-28, 분석 댓글 TRI-30/31) |
| 수정 | owner | `isac-issue-to-pr` 전체(진입 I2P-01/02, QA list I2P-22/23, 구현·QA I2P-24, old 실패/new 통과 I2P-25, 교차 리뷰 I2P-32, PR I2P-41~45, CI I2P-46~50) |
| 리뷰 | 구현자가 아닌 리뷰어(대량 run은 메인) | `isac-pr-review`(PRR-05, PRR-08, PRR-12~17, PRR-24/25), 루프는 MAC-16/18 |
| 머지 | 메인 | E2I-01 승인이 있는 항목만. 게이트 I2P-52, 여러 PR 순서 I2P-54, 세부는 전역 머지 가드 |
| 종결알림 | 게시 주체 | I2P-57/58 종료 댓글과 닫기, 버전 표기 I2P-60 |

- **E2I-06** [U] 단계를 건너뛰지 않는다. 앞 단계의 종료 조건(각 step 스킬 소유)이 채워지기 전에는 다음 단계로 보내지 않는다: 재현·근본 원인·우리 코드 결함 판정 전에는 수정에 들어가지 않고(I2P-01), old 실패/new 통과와 QA 확인 전에는 PR을 열지 않고(I2P-25), QA list 전체 실행과 CI green 전에는 리뷰로 넘기지 않고(I2P-24, I2P-46), 리뷰 통과·QA 코드화·CI green·동등 환경 검증 전에는 머지하지 않는다(I2P-52).
- **E2I-07** 전이 게이트를 못 넘은 항목은 종착 상태 중 하나로 닫거나 이전 단계로 되돌린다. 리뷰 `BLOCKING`은 종착이 아니라 owner에게 되돌리는 반복이다(MAC-16, MAC-18).

## 4. 항목 배치와 메인 역할

- **E2I-08** [U] 대상이 둘 이상인 run 또는 사용자가 이슈별 서브에이전트 위임을 지시한 run에서, 중복 정리 이후의 이슈별 과정은 이슈마다 owner 서브에이전트를 하나씩 두고 병렬로 돌린다(MAC-03, TRI-38, I2P-07). 메인은 이슈별 분석·재현·구현을 직접 하지 않는다(MAC-02). 메인 몫은 intake, 중복 정리 판정, ledger, 전이 게이트 판정, 리뷰, 머지 실행, 최종 보고다.
- **E2I-20** 그 밖의 대상 하나짜리 run은 메인이 트리아지·수정을 직접 해도 된다. 이때 리뷰는 구현에 참여하지 않은 리뷰어가 한다(I2P-63).
- **E2I-09** [U] E2I-08 run에서 owner는 자기 이슈의 `트리아지`와 `수정`을 끝까지 맡고, 메인이 리뷰어다. 메인은 PR 코드를 한 줄씩 읽고 이슈와 대조해 판정하며(MAC-18, I2P-51, 리뷰 차원 PRR-12~17), finding은 owner에게 돌려보내 고치게 하고 직접 패치하지 않는다.
- **E2I-10** 게시 주체는 GHP-15를 따른다. 사용자가 owner에게 댓글·PR 게시까지 맡기면 owner가 자기 이슈의 게시 주체다.
- **E2I-11** run 중간의 사용자 규칙·정정은 실행 중인 owner에게 즉시 전파하고 이후 위임의 standing constraint로 둔다(MAC-07). 한 이슈에만 걸린 질문은 그 이슈만 멈추고 묻는다. 다른 이슈의 진행은 막지 않는다. 같은 시점의 질문은 묶는다(DBR-12).

## 5. 멈춤과 계속

- **E2I-12** [U] 근본 해결이 프로젝트 핵심을 바꾸는 이슈는 그 이슈만 `구조 변경 승인 대기`로 멈춘다(TRI-25, I2P-14, MAC-12). 브리프는 `isac-decision-brief` 형식으로 만들어 최종 보고의 결정 필요 항목에 모은다. 나머지 이슈는 계속 진행한다. 승인이 오면 그 이슈만 `수정`부터 재개한다.
- **E2I-13** run 전체는 모든 대상이 종착 상태이거나, 남은 이슈가 모두 사용자·외부 입력 대기(`구조 변경 승인 대기`, `정보 필요`, `외부 블로커`, `PR 준비됨(머지 미승인)`)일 때 멈춘다. 같은 실패로 제자리를 도는 항목(재현 환경 구축 실패, 같은 finding 반복)은 원인을 분리해 `외부 블로커`나 결정 필요 항목으로 올린다.

## 6. 종결과 머지 후

- **E2I-14** [U] 머지된 이슈는 `종결알림`을 마쳐야 종착이다. 머지만 하고 이슈를 열어 두지 않는다. 종료 댓글·닫기·재오픈 조건은 I2P-57, I2P-58. 사용자가 종결을 지시한 비수정 이슈도 판정 근거 댓글을 남기고 닫는다(TRI-01).
- **E2I-15** 머지됐지만 릴리스에 없는 수정은 ledger와 보고에 "merged but unreleased"로 남기고 사용자에게 릴리스가 필요함을 알린다(I2P-60, PRR-35).
- **E2I-16** 열린 PR이 이미 있는 이슈는 I2P-02, TRI-42대로 처리하고 종착 `기존 PR 있음`으로 둔다. 그 PR을 처리하라는 지시가 있으면 PR 하나는 `isac-pr-review`, 여러 개는 `isac-e2e-pr-backlog`로 넘긴다.
- **E2I-17** 릴리스·배포 실행은 이 스킬 범위 밖이다. 사용자가 run 끝에 릴리스를 지시하면 그 지시를 새 작업으로 따르고 절차를 이 스킬에 두지 않는다. 이 스킬은 E2I-15의 목록만 넘긴다.

## 7. 보고(한국어)

- **E2I-18** [U] 최종 보고는 `references/ledger-and-report.md` 형식을 따른다: 대상 전부의 종착 표(이슈, 종착, 무엇이 문제였고 어떻게 해결했는지 한 줄, PR·머지 커밋, 게시물), 게시한 것, 남은 것(미해결·미릴리스·블로커), 사용자 결정이 필요한 항목(구조 변경 브리프, 머지 승인, 종결 권고). 종결 전에 종료 댓글이 실제로 나갔는지와 제보자 동등 환경 검증 여부를 적고, 검증한 것과 안 한 것을 나눈다.
- **E2I-19** run 중간에 진행 보고를 요청받으면 같은 표로 현재 ledger를 요약한다. 남은 이슈의 문제·해결 가능성·추가 정보 필요 여부는 TRI-34 형식이다.

## 완료 조건

- 범위(E2I-01)가 기록됐고, 대상 전부가 종착 상태이거나 E2I-13의 대기 상태로 분류됐다.
- 대량 run이면 owner 배치 전에 중복 정리를 끝냈고 정본만 진행했다.
- PR을 연 이슈마다 현재 head에 대한 `isac-pr-review` 판정이 있고, 머지한 이슈는 E2I-01 승인과 I2P-52 게이트를 충족했으며 종결알림까지 끝났다.
- 게시 모드면 종착별 게시물이 나갔고 GHP-15의 다시 읽기 대조를 마쳤다.
- 최종 보고가 E2I-18 형식이다.

## 교정 루프

결과가 기대와 다르면 사용자는 `isac-skill-correction`으로 이 스킬을 교정할 수 있다. 실행 중 사용자가 교정했다면 따로 묻지 말고 최종 보고에 한 줄로 안내한다. `references/cases.md`는 교정할 때만 읽는다.
