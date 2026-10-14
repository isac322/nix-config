---
name: isac-e2e-release
description: Use when the user wants a versioned release driven end to end and gated on evidence - read every change since the most recent published release, derive the version from the public-interface and behavior delta, verify the candidate differentially against that release (full suite, required CI, the previous release's suite on new code, identical exploratory scenarios on both), stop with a GO/NO-GO report on a confirmed regression or new bug, run a fix branch when ordered, then cut the release PR, publish with exact-SHA tag checks, and verify the published artifact by a clean install from the public registry. Also covers "do we need a release / which version" (analysis mode) and a GO/NO-GO pass without publishing (qa mode). Triggers include "릴리즈해", "다음 버전 결정", "릴리즈 해야 하나?", "직전 릴리즈 대비 regression 확인 후 릴리즈". Not for QA loops over a deployed environment (isac-e2e-qa-to-fix, isac-live-qa), issue backlogs (isac-e2e-issue-resolution), a single fix PR (isac-issue-to-pr), promo or metadata readiness (isac-e2e-promo-readiness), or deploy-only services without versioned releases (route to isac-e2e-qa-to-fix or isac-issue-to-pr).
---

# E2E 릴리스: 변경 목록 → 차등 검증 → (수정) → 컷 → 게시 → 게시 후 검증

직전 공개 릴리스와 비교해 후보를 검증한 증거가 있을 때만 버전을 정하고 게시한다. 검증에서 회귀나 새 버그가 확인되면 멈추고 보고한다. 수정 지시가 있으면 수정 분기를 거쳐 다시 검증한 뒤 컷·게시하고, 게시된 산출물을 사용자가 설치하는 방식 그대로 다시 확인한다. 이 스킬은 오케스트레이터다. 소유 범위: 모드와 권한 지도, 단계·게이트·종착 상태, 버전 근거 방법, 차등 QA 방법, 수정 분기의 진입과 재진입, 컷·게시 단계 규율, 게시 후 검증, 릴리스 ledger, 최종 보고.

공통 핵심은 이 파일과 `references/`에 있다. 명령, 파일 이름, 이미지, 레지스트리, 태그 형식처럼 프로젝트마다 다른 내용은 프로젝트 프로필이나 저장소 하네스에만 둔다. QA 시나리오는 고정 테스트 케이스 목록으로 두지 않고 매 릴리스의 변경 목록과 공개 표면에서 새로 설계한다(E2V-14).

## 경계

- 단계 안의 규칙은 step 스킬이 소유하고 여기서는 이름과 규칙 ID로만 부른다.
  - 토론 방법·규모·합의 실패 시 arbiter·NEEDS-USER 상향·리뷰 GREEN 루프와 그 종료 기준·head별 판정 유효성: `isac-multi-agent-consensus` MAC-01, 02, 05, 07, 08–13, 16–20.
  - 수정 구현, QA 목록, 테스트, old-fail/new-pass, 테스트 계층, mutation 확인, CI flaky 처리, 머지 게이트, 머지 순서, 보고 상태, 릴리스 필요 안내: `isac-issue-to-pr` I2P-24, 25, 26, 28, 33, 39, 47, 52, 53, 54, 60, 61.
  - 커버리지 분모, 제한된 탐색 캠페인, 병렬 케이스, 계약 기록, 격리된 릴리스 전 산출물, 설치 경로 검증: `isac-live-qa` LQA-04, 20, 21, 23, 36, 37. 인용만 하고 LQA run으로 부르지 않는다.
  - 재현, 판정 분류, 태그 대 기본 브랜치 비교, 수정 출처 표현: `issue-validation`의 "Build a minimal, representative reproducer", "Compare three code states and trace provenance", "Verify fixes bidirectionally" 절.
  - 같은 케이스 재실행 + 제한된 탐색의 형태(패턴만): `isac-e2e-qa-to-fix` E2Q-09, E2Q-10.
  - 질문 형식·묶음·답 재사용: `isac-decision-brief` DBR-01, 04, 06, 12.
  - 공개 글(PR 본문, 릴리스 노트, 댓글)의 언어와 위생: `isac-github-publishing`(GHP).
  - 사고의 원인 분석: `five-whys-root-cause-analysis`. 선택적 리뷰 지적 처리: `receiving-code-review`.
- **E2V-50** 서브에이전트 brief와 구현·리뷰 handoff는 `references/briefs.md`에서 역할에 맞는 틀을 복사해 모든 칸을 채워 보낸다. 칸을 채울 수 없으면 보내지 않는다. "읽을 스킬" 칸에는 owner 스킬 이름과 규칙 ID(ID가 없으면 절 제목)만 적고 절차를 옮겨 적지 않는다. "쓰기 경계" 칸에는 요청의 쓰기 경계를 그대로 적는다(전역 task-intent 가드). 채운 brief는 scratch 파일로 남기고 경로를 ledger에 적는다.
- 전역 가드(PR 생성, 리뷰 가드, PR 머지 승인·admin bypass·head 브랜치 삭제, task-intent, application-code 승인, destructive, verification, temporary-resource-cleanup, release-gate)는 이름으로만 따른다.
- 저장소별 릴리스 절차와 노트 스타일은 0단계에서 찾은 저장소 하네스(`.claude/skills/*`, `.agents/skills/*`, AGENTS.md/CLAUDE.md, CONTRIBUTING)가 소유한다(E2V-04).
- 배포 환경 QA 루프, 이슈 백로그, 단일 수정 PR, 홍보·메타데이터 준비, 버전 릴리스가 없는 배포 전용 서비스는 범위 밖이다(E2V-03).

## 0단계: 프로젝트 훅

`gh repo view --json nameWithOwner,visibility`로 대상 저장소를 확인한다. 저장소 하네스의 릴리스·노트 스킬과 지침을 먼저 읽고(E2V-04), 이 스킬의 `references/projects/<owner>__<repo>.md`가 있으면 이어서 읽는다. 이 위치에는 공개 저장소 문서만 둔다. 비공개 저장소의 프로젝트 사실은 그 저장소의 자체 지침(AGENTS.md, `.agents/skills`)에 두고 nix-config에는 쓰지 않는다. 프로젝트 문서는 기본값을 좁히거나 구체화만 하고 `[U]` 규칙과 전역 가드를 완화할 수 없다. 프로필이 없으면 발견으로 진행하고 발견한 사실을 ledger에 적는다.

## 모드와 권한 지도

진입 때 모드를 하나 정해 ledger 머리에 적는다(E2V-02).

| 모드 | 범위 | 종착 |
|---|---|---|
| `analysis` | 0–1단계: 무엇이 바뀌었나, 릴리스가 필요한가, 어느 버전인가 | `ANALYSIS_DONE` |
| `qa` | 0–2단계: G-GO까지, GO/NO-GO 보고만 | `QA_DONE` / `STOPPED_NO_GO` |
| `release` | 0–5단계 | 아래 종착 상태 |

권한 지도는 run이 할 수 있는 행동과 PR마다 그것을 허락한 사용자 지시를 적는다. 허락한 지시가 없는 PR은 머지 가드 질문을 일찍 올린다.

## 단계와 게이트

- **E2V-51** 0단계에서 `references/state-machine.md`, `references/ledger-and-report.md`, `references/briefs.md`, `references/defaults.md`를 모두 읽는다(`references/cases.md`는 실행 중 읽지 않는다). 이어서 `references/ledger-checklist.md`를 파일 복사(`cat <파일> >> <ledger>`)로 ledger 끝에 붙인다. 게이트 통과는 그 블록의 `G-…` 줄에만 적고, 블록에 빈 칸이 하나라도 있으면 그 게이트는 통과가 아니다. 크래시·재개(`STOPPED_NO_GO`나 `BLOCKED` 뒤 사용자 지시로 다시 들어갈 때 포함)·컨텍스트 압축 뒤나 todo만 남은 상태로 이어갈 때는 다음 게이트 판정 전에 이 파일, state-machine.md의 현재 단계 절, ledger를 다시 읽는다.

```
0 진입·사전 점검 (G-INTAKE) ─► 1 변경 목록·버전 근거 (G-VERSION) ─► [analysis: ANALYSIS_DONE]
─► 2 후보 차등 검증 ─► G-GO
     ├─ GO ─► 3                                   [qa: QA_DONE]
     └─ NO-GO ─► 보고 ─► STOPPED_NO_GO (대기)
                  └─ 수정 지시/사전 허락 ─► F
F 수정 분기: 카탈로그(미검증) → 고정 프로토콜 → MAC 판정 → 결정 파일 → NEEDS-USER(의존 단계만 보류)
  → I2P 구현 → 리뷰 루프(MAC-16) → 수정 PR 최종 head에서 G-REQA → G-MERGE
  → 1(버전 재도출)과 2(변경분 범위)로 재진입
3 컷: 버전 근거·노트 초안 → 승인(E2V-35, 위임이면 생략. 프로필 Overrides가 요구하면 묻는다) → 릴리스 PR(또는 봇 PR 검증) → 노트 독립 리뷰(E2V-34) → G-CUT(묻는 경우 버전 답 기록 필요) → G-MERGE
4 게시(되돌릴 수 없음), 태그·게시 트리거·릴리스 객체의 소유자에 따라 둘로 나뉜다
  에이전트 소유: G-PUB tree·조상 단언 → 태그 생성·검증(서명은 프로젝트 서명 정책을 따름) → 파이프라인 → 채널별 공개 확인 → 릴리스 객체
  봇 소유(E2V-13): 봇 PR head에서 게시 전 게이트 전부와 G-PUB의 트리거 전 단언(tree·조상) → 머지(게시 트리거)
                  → G-PUB 나머지: 봇이 만든 태그·산출물·릴리스 객체를 관찰·검증(직접 만들지 않음) → 5단계 G-POST
5 게시 후: 머지된 SHA마다 기본 브랜치 CI → 공개 배포 채널에서 깨끗한 설치 → 후속 PR → 정리 처분(E2V-45) → 보고 (G-POST)
어느 단계든 ─► BLOCKED(<무엇>) | 0단계 ─► NOT_APPLICABLE
```

종착 상태: `NOT_APPLICABLE`(맞는 스킬로 안내), `ANALYSIS_DONE`, `QA_DONE`, `STOPPED_NO_GO`, `BLOCKED(<무엇>)`, `PARTIAL_PUBLISH(<채널>)`, `RELEASED_WITH_FOLLOWUPS(<열린 PR·승인>)`, `RELEASED_VERIFIED`. G-MERGE는 run 안의 모든 PR에 적용한다.

## 어휘

- 수정 판정(닫힌 집합): `FIX`(고친다), `KEEP`(개선이므로 유지), `DOCS`(문서만 고친다), `NOT-A-PROBLEM`(문제 아님), `UPSTREAM`(외부 원인, 보고만), `NEEDS-USER`(사용자 결정 필요).
- QA 관찰 분류(닫힌 집합): `ok`, `regression`, `new-bug`, `pre-existing-bug`, `env-limitation`, `not-testable`.
- 레인 기록: `ran` / `not_applicable` / `blocked`. 기준선 상태: `available` / `none` / `blocked`.

## 0단계: 진입

- **E2V-01** [U] 릴리스 요청은 조건부다. run이 가장 최근 공개 릴리스 대비 정확한 후보에 대한 게이트 증거를 갖기 전에는 태그, 릴리스 PR, 게시를 하지 않는다.
- **E2V-02** 진입 때 모드(analysis / qa / release)를 적고, run이 할 수 있는 모든 행동과 PR마다 그것을 허락한 사용자 지시를 적는다. 허락한 지시가 없는 PR은 머지 가드 질문을 일찍 올린다.
- **E2V-03** 공개 릴리스, 레지스트리 패키지, 릴리스 워크플로가 모두 없는 단위는 진입 때 `not_applicable`로 선언하고 맞는 스킬을 알려 준다. 배포 전용 서비스는 `isac-e2e-qa-to-fix` / `isac-issue-to-pr`로 보낸다.
- **E2V-04** 진입 때 프로필보다 먼저 저장소 하네스의 릴리스·노트 스킬, 에이전트, 하네스 문서를 읽는다. 그 릴리스 절차와 노트 규칙은 프로필과 직전 릴리스보다 우선하고, 직전 릴리스는 스타일 참고로만 쓴다. 찾지 못했으면 "없음"과 찾아본 경로를 ledger에 적는다.
- **E2V-05** 적힌 절차가 없으면 3단계 진입 때 직전 릴리스의 PR, 커밋, 태그, CI/게시 워크플로 파일에서 릴리스 절차를 도출해 ledger에 적고, 모호할 때만 묻는다.
- **E2V-06** "직전 릴리스"는 릴리스 단위마다 releases/레지스트리 API(가장 최근의 draft도 prerelease도 아닌 릴리스)로 정하고, 태그 패턴은 걸러내는 데만 쓴다.
- **E2V-07** 기준선은 공개 산출물 > 릴리스 asset > 태그에서 재빌드(차이를 명시) 순서로 만들고 `available` / `none` / `blocked`로 기록한다. `none`이면 새 표면 방법으로 바꾸고 old-on-new와 A/B 레인(G-REQA 포함)은 `not_applicable`로 둔다. 기준선에 기대는 다른 게이트 산출물(G-VERSION의 표면 차이, G-CUT의 직전 릴리스 PR 모양, G-PUB의 태그 형식)은 `references/state-machine.md`의 대체 산출물로 바꾸고, 첫 버전과 컷·태그 규약은 저장소 선언과 워크플로에서 도출하며 남는 선택만 묻는다. `blocked`이면 decision brief로 묻고 자동으로 GO하지 않는다.
- **E2V-08** 사전 점검에서 기억한 환경 사실과 저장소·프로필이 열거한 대상 환경(호스트 정체, 도달 가능성, CI 이미지 능력)을 다시 확인하고, 도달할 수 없거나 쓸 수 없는 대상은 건너뛰지 않고 미검증 범위로 적는다.
- **E2V-09** 모든 검증 기록(suite, CI, QA, 리뷰, 설치)은 실행한 SHA나 산출물, 명령, 범위를 적고, 게이트 주장은 그 기록을 인용한다.

## 1단계: 변경 목록·버전

- **E2V-10** [U] 버전을 제안하기 전에 직전 릴리스 이후 머지된 모든 변경을 읽는다.
- **E2V-11** 버전 근거는 기준선과 후보 사이의 공개 인터페이스·동작 차이, 전부 읽은 breaking 또는 mixed 변경, changelog의 의도한 변경이다. 두 번째 에이전트가 반박하고 독립 릴리스 리뷰어가 확인한다. 분류기는 선택적 읽기 보조일 뿐이고 이 스킬에 임계값을 두지 않는다.
- **E2V-12** 수정 분기가 머지되면 최종 릴리스 커밋의 기준선 대비 차이로 버전을 다시 도출하고, 수정이 들여온 동작 변경도 포함한다.
- **E2V-48** 저장소 규칙이 그 경우를 말하지 않거나 두 가지로 읽히면, 저장소가 선언한 기준(버전 방식 선언, 개발 단계 선언 등)과 그 규칙을 실제로 적용한 과거 릴리스를 해석 근거로 쓰고 그 근거를 ledger에 적는다. 공개 안정성 단계의 전환(예: 0.x에서 1.0으로)은 위임된 run에서도 run이 스스로 정하지 않고 사용자에게 올린다(MAC-12).
- **E2V-13** 봇이 버전 올리기를 소유하면 버전 파일과 태그를 직접 고치지 않는다. 봇의 릴리스 PR을 버전 근거와 대조하고, 필수 context가 봇 PR head에서 실제로 보고됐는지(또는 같은 tree에서 게이트를 돌렸는지) 확인한다. 그 머지가 게시 트리거이므로 게시 전 게이트 전부와 G-PUB의 트리거 전 단언을 머지 전에 끝내고, 트리거 뒤에 G-PUB의 나머지(봇이 만든 태그·산출물·릴리스 객체 검증)와 G-POST를 마친다.

## 2단계: 후보 검증

- **E2V-14** [U] 검증 폭은 모든 공개 표면을 smoke 수준으로 덮고 깊이는 변경 목록과 위험을 따른다. 시나리오는 매 run 표면 목록과 변경 목록에서 설계하고 고정 테스트 케이스 목록에서 가져오지 않는다.
- **E2V-15** 2단계는 다음 레인을 돌리고 각각 `ran` / `not_applicable` / `blocked`로 기록한다: 후보 전체 suite, 후보의 필수 CI, 후보 코드에 대한 기준선 릴리스의 suite, CI가 실행하는 테스트와 저장소에 있는 테스트의 차이(CI workflow가 호출하는 테스트 명령·경로·job과 저장소의 테스트 단위 목록(파일, 디렉터리, 패키지·모듈, feature·marker·ignore 설정으로 갈리는 대상처럼 그 저장소 테스트 러너가 나누는 단위)을 대조해 CI가 돌리지 않는 단위를 적고, 그 단위마다 E2V-26의 환경에서 돌린 결과(SHA)나 `blocked` 사유를 적는다. 기준선 대비 테스트 변경 diff와는 다른 레인이다), 기준선과 후보에서 같은 시나리오를 돌리는 차등 탐색 QA, 후보의 릴리스 동등 산출물을 공개 문서대로 깨끗한 환경에 설치하는 확인(I2P-28). 초록 suite만으로 GO가 되지 않는다. 환경 문제로 끝나지 않은 실행은 `blocked`로 적고 E2V-26의 환경에서 다시 돌린다. 끝나지 않은 실행을 `ran`이나 통과로 적지 않는다.
- **E2V-16** 기준선 suite의 실패는 changelog의 의도한 변경과 하나씩 맞춘다. 그런 실패가 테스트를 일찍 중단시키면 그 테스트의 나머지가 확인했을 내용을 적고 다른 방법으로 덮는다.
- **E2V-17** 차등 QA는 관찰마다 `ok` / `regression` / `new-bug` / `pre-existing-bug` / `env-limitation` / `not-testable`로 분류하고, 분모가 표면 목록인 커버리지 표를 유지하며(LQA-20), 두 번 이상 재현하고 최소화하며(`issue-validation` "Build a minimal, representative reproducer"), changelog가 선언한 의도한 변경도 믿지 않고 확인한다.
- **E2V-18** [U] 기준선과 다른 모든 동작은 먼저 개선 시험(고쳐짐, 더 직관적, 더 표준적)을 거친다. 개선은 `KEEP`이고 되돌리지 않는다.
- **E2V-19** [U] QA 발견은 가설이다. NO-GO blocker는 발견자가 아닌 에이전트의 재현과 결함 판정(MAC-05 사소 규모)이 있어야 하고, 나머지 발견은 미검증으로 보고한다.
- **E2V-20** [U] 확인된 회귀나 새 버그는 NO-GO다. 태그, 릴리스 PR, 게시를 만들지 않고 보고한 뒤, 요청이 이미 수정과 릴리스를 허락하지 않았다면 사용자의 범위 지시를 기다린다.
- **E2V-21** 모든 레인이 보고되고, 커버리지 표가 표면 목록 전체에 걸치고, 모든 regression·new-bug 가설에 challenger 판정이 있고, 미검증 범위가 보고에 적혀 있을 때만 GO를 선언한다.
- **E2V-22** GO/NO-GO 보고는 발견마다 어떻게 찾았는지, 누가 검증했는지, 기존 테스트가 덮는지, 검증 상태를 적고 미검증 범위를 더해 `references/ledger-and-report.md`의 양식을 따른다. 보내기 전에 `references/ledger-and-report.md`의 "보내기 전 확인"을 통과한다.

## 수정 분기

- **E2V-23** [U] 수정 지시를 받으면 조사 전에 2단계 발견 전체(기존 버그 포함)를 "미검증" 목록으로 모으고, 결정 질문 하나, 사용자의 강제 규칙, 판정 집합 `FIX` / `KEEP` / `DOCS` / `NOT-A-PROBLEM` / `UPSTREAM` / `NEEDS-USER`를 파일로 고정해 그 경로와 sha256을 ledger와 조사자·challenger brief에 적는다. 판정은 MAC 아래에서 내리고(구성은 E2V-46), 결정 파일(항목별 판정·근거 위치·판정 주체가 있는 MAC-11 매트릭스, 규약, 소유 파일·인터페이스가 있는 slice, NEEDS-USER, 동작 변경 목록)을 유일한 계약으로 삼아 기존 버그를 포함한 모든 `FIX` 항목을 테스트와 함께 PR 하나로 고친다. 결정 파일은 판정에 참여한 에이전트(arbiter나 통합 조사자)가 쓰고 머리에 `작성: <agent id>`를 단다. 메인은 결정 파일을 쓰지 않는다. 각 slice는 자기 worktree와 브랜치에서 구현하고, 메인이 slice 브랜치를 통합 브랜치(PR head)에 합치며 충돌은 거기서 푼다(MAC-02). 한 worktree를 두 slice가 함께 쓰는 dispatch는 파일 소유가 겹치지 않아도 금지한다.
- **E2V-47** [U] 저장소 전체에서 클라이언트가 보는 계약을 바꾸는 `FIX`도 사용자의 개선 기준(고쳐짐, 더 직관적, 더 표준적)에 맞으면 에이전트 합의로 확정할 수 있고, 그 변경은 릴리스 노트와 보고에 동작 변경으로 따로 적는다.
- **E2V-24** [U] `NEEDS-USER` 항목은 알게 되는 즉시 사용자에게 올리고 그 항목에 의존하는 단계만 기다린다. 답 뒤에 사용자가 후속 질문을 하면 그 항목을 다시 열어 답하고, 사용자가 정할 때까지 의존 단계만 보류한다. 답을 기다리는 동안 그 항목에 의존하는 slice에는 HOLD를 보내고 기본안을 미리 구현하지 않는다. 다른 slice는 계속한다.
- **E2V-25** 구현 brief에는 프로필의 환경 능력 사실을 담는다. suite 실패는 제품 코드를 고치기 전에 진단 증거와 함께 테스트 산물인지 제품 결함인지 분류한다. 실패를 구현자에게 넘기는 메시지에는 이 분류 파일 경로와 항목별 분류(테스트 산출물 / 제품 결함)를 붙이고, 분류 없이 원인을 찾아 고치라고 넘기지 않는다.
- **E2V-26** lint, format, type, test 게이트는 CI가 그 게이트에 쓰는 환경에서 돌린다.
- **E2V-27** old-fail/new-pass 확인(I2P-25)은 최종 head의 최종 테스트 집합으로 돌리거나, 돌리지 않은 테스트를 보고에 적는다. 어떤 주장도 실행한 범위를 넘지 않는다. old-fail을 돌렸으면 이전 코드에서 통과한 테스트도 control로 이름을 적는다.
- **E2V-28** 수정 PR을 머지하기 전에 최종 head를 기준선 suite, 수정이 동작을 바꾼 모든 표면의 A/B 실행(결정 파일의 목표 계약으로 판정), 공개 문서를 따른 릴리스 동등 산출물의 깨끗한 설치(I2P-28)로 다시 검증한다. 선언하지 않은 차이는 새 발견으로 수정 분기에 돌려보낸다.
- **E2V-29** 리뷰어 brief는 리뷰어가 확인할 사실을 나열하고 모든 손 편집을 밝히며, 판정을 미리 말하지 않는다. 확인할 사실에는 리뷰 대상 head SHA를 단다.

## 머지 (run 안의 모든 PR)

- **E2V-30** CI watcher는 ruleset이 요구하는 모든 context가 정확한 head에 대해 보고되고, 필수 리뷰의 상태가 그 head에 대해 기록됐을 때만 끝난 것으로 친다. 필수 목록은 실시간 ruleset 조회로 읽는다. 머지 단계는 어떤 머지보다 먼저 이것을 확인하고, 필수 리뷰가 없을 때 머지를 막을지(소유자 예외 포함)는 전역 머지 가드가 정하며 그 처분을 ledger에 적는다.
- **E2V-31** 필수 run이 실패하면 로그 시그니처를 읽고, 즉시 재실행은 최대 한 번, 필수인지 확인한 뒤 간격을 둔 제한된 재시도 watcher를 쓴다. bypass는 하지 않는다. 머지 후 기본 브랜치 run(I2P-47)을 포함해 릴리스가 의존하는 모든 필수 run에 적용한다.

## 3단계: 컷

- **E2V-32** 릴리스 PR의 파일 집합과 diff 모양은 직전 릴리스 PR에 버전 변경을 더한 것과 같다. 그 밖의 차이는 drift로 설명한다. lockfile 메타데이터는 이유와 그것을 만든 도구를 밝히지 않고는 base 브랜치와 달라지지 않으며, 손으로 맞춘 정규화는 리뷰어에게 손 편집으로 밝힌다.
- **E2V-33** changelog, PR 본문, 릴리스 노트, README의 모든 공개 주장은 코드나 SHA를 인용한 실행 명령과 대조하고, 내부 발견 ID를 담지 않는다(글 위생은 GHP 소유).
- **E2V-34** 릴리스 노트는 저장소가 정한 노트 규칙을 따르고, 게시 전에 독립 리뷰어가 그 규칙과 changelog에 맞춰 리뷰한다. 독립 리뷰어는 릴리스 PR head의 버전 일관성, changelog 연결, 버전 주장 대 공개 인터페이스 delta도 확인하고, PR 본문 같은 공개 텍스트도 한 번 대조한다.
- **E2V-35** [U] 요청이 버전 결정과 끝까지의 릴리스를 함께 명시적으로 맡겼으면 버전·노트 승인을 묻지 않고 버전 근거와 릴리스 노트를 최종 보고에 싣는다. 노트는 게시 전에 E2V-34의 독립 리뷰를 거친다. 그렇지 않으면 GO 직후 버전 근거와 노트 초안을 써서 둘을 한 번에 묻는다. 다만 프로필 `## Overrides`가 사용자 결정을 출처로 이 규칙을 좁혀 질문을 요구하면, 위임이어도 그 Overrides가 정한 질문만 묻는다.
- **E2V-36** [U] 릴리스 단위마다 자기 diff로 버전을 정하고, 노트는 그 단위의 직전 릴리스 이후 모든 변경을 업그레이드 안내, 알려진 한계(미검증 범위 포함)와 함께 다룬다.

## 4단계: 게시

- **E2V-37** 되돌릴 수 없는 첫 단계 전에 태그 대상의 tree가 마지막으로 모든 게이트를 통과한 head의 tree와 같고, QA한 후보와 태그 커밋 사이의 커밋이 정확히 이 run의 수정·릴리스 PR임을 단언한다. 아니면 추가 커밋 범위로 다시 검증한다.
- **E2V-38** 게시 단계마다 별도 명령으로 돌리고 실패하면 run을 멈춘다. 확인이 실패해도 다음 단계가 이어지거나 종료 상태가 숨겨지도록 명령을 `&&`, `;`, 파이프로 묶지 않는다.
- **E2V-39** [U] 에이전트가 태그를 소유하면 태그는 직전 릴리스의 형식대로 만들고, 프로젝트가 서명하면 같은 방식으로 서명한다(서명하지 않는 정책이면 서명은 `not_applicable`로 적고 태그 정체와 tree만 확인한다). push 전에 검증한다. 게시 파이프라인을 끝까지 지켜보고, 모든 배포 파일과 채널이 공개 게시됐는지(draft나 제출만이 아니라) 확인한 뒤에야 검증한 태그로 릴리스 객체를 만든다. 봇이 태그나 릴리스 객체를 만들면 직접 만들지 않고, 봇이 만든 것을 같은 기준으로 검증한다(E2V-13).
- **E2V-40** [U] 여러 채널에 게시할 때 한 채널의 실패가 다른 채널을 막지 않고, 끝에 부분 게시로 보고한다.

## 5단계: 게시 후

- **E2V-41** 릴리스 체인의 머지마다 머지된 SHA의 기본 브랜치 CI를 지켜보고, 실패는 최종 보고 전에 E2V-31로 분류한다.
- **E2V-42** [U] 게시 후 깨끗한 환경에서 공개 문서를 글자 그대로 따라 단위가 선언한 공개 배포 채널(레지스트리, 또는 digest를 확인한 릴리스 asset)에서 설치하고, 릴리스의 주요 변경과 수정을 smoke 테스트한다. 실패는 우회하기 전에 기록하고 최종 사용자 문서 공백인지 환경 전용 산물인지 분류한다.
- **E2V-43** 릴리스 뒤 찾은 문서·결함 후속 작업은 `isac-issue-to-pr`로 별도 PR을 만들고, 그 머지는 E2V-02에 따라 따로 허락받는다.
- **E2V-44** 최종 보고는 family 한국어 보고 규약을 따르고, 항목마다 I2P-61 상태를 주며, 어느 변경이 어느 공개 산출물에 들어 있는지 커밋 순서 타임라인을 보이고, 다음 릴리스까지 낡은 채로 남는 레지스트리 페이지를 적는다. 보내기 전에 `references/ledger-and-report.md`의 "보내기 전 확인"을 통과한다.
- **E2V-45** run이 만든 임시 자원은 전역 temporary-resource-cleanup 가드가 정한 종류 전부를 그 가드대로 기록하고 처분한다(예: worktree, PR head를 포함한 브랜치, 증거 파일이 든 scratch 디렉터리, 컨테이너, 이미지, VM, CI watcher·preview 서버 같은 백그라운드 프로세스). 기록 항목, ledger 경로 알림, 삭제 신호, 삭제 전 확인은 가드가 소유한다. 기록 위치는 ledger의 `### cleanup ledger` 절이고, 가드의 항목에 run이 만들었다는 증거(만든 명령·msg id)를 더한다. 서브에이전트가 만든 자원은 반환문으로 받아 메인이 적는다. 종착 상태 도달, 머지, 최종 보고는 삭제 신호가 아니다. 신호가 없으면 최종 보고에 남은 행과 삭제 명령을 적고 기다리며, 증거 파일은 신호가 올 때까지 지우지 않는다. PR head 브랜치는 만들 때 행에 넣고, 삭제는 신호에 더해 전역 pull-request-merge 가드의 삭제 허락이 있을 때만 하며 다른 행과 한 명령으로 묶지 않는다. 저장소의 자동 삭제는 run의 행동이 아니므로 그 행 결과에 "저장소 자동 삭제"로 적는다. 작업 기기에 묶인 사실은 프로필이 아닌 memory에 저장한다.

## 판정 주체

- **E2V-46** [U] 버전 근거, 각 NO-GO blocker, GO 결정 입력, 수정 판정, 재QA 차이 분류, 릴리스 노트 적합성, 게시 후 공백 분류, 필수 run 실패의 flake 여부, 단계 밖에서 늦게 나온 관찰(실제 문제인지와 분류)은 각각 MAC 아래 여러 에이전트가 정하고 메인 혼자 정하지 않는다. 방법은 MAC-01, 02가, 호출자 책임은 MAC-08이 정한다. 수정 판정은 MAC-05 대량 구성을 따른다. 판정 중에 나온 규약·적용 범위·계약 설계 같은 하위 쟁점과 challenger가 새로 낸 finding도 그 FIX 판정의 일부로 같은 구성으로 다룬다. 2라운드 응답자와 분류 판정 기본 구성은 MAC-05를 따른다. 사용자 기준(E2V-47) 밖의 제품 방향이면 arbiter 대신 NEEDS-USER로 올린다(MAC-12, E2V-24). arbiter 판정이 절차상 흠결이 있으면(잘못된 근거, 판정 주체 수 부족, 합의된 항목 개입) 그 판정을 되돌리지 않고 잘못된 근거를 뺀 채 같은 구성으로 다시 판정한다. NEEDS-USER는 사용자 기준(E2V-47) 밖 결정에만 올린다(MAC-12).
- **E2V-49** [U] 서브에이전트가 rate limit 같은 일시 장애로 뜨지 않으면 `references/defaults.md`의 상한까지 watcher로 기다린다. 판정 역할은 read-only 에이전트가 맡아도 되며 MAC-05 구성은 그대로 지키고, 그 반환문은 손대지 않고 파일로 저장해 머리에 `작성: <agent id>`를 단다. 구현·커밋 같은 쓰기 역할은 메인이나 read-only 에이전트가 대신하지 않는다(MAC-02). 상한을 넘으면 `BLOCKED(서브에이전트: <원인>)`로 멈추고, 더 기다릴지·다른 방식을 허락할지·멈출지를 `isac-decision-brief`로 묻는다.

| 판정 지점 | 구성(MAC-05) |
|---|---|
| 버전 근거 | 조사자 + challenger + 독립 릴리스 리뷰어 |
| NO-GO blocker 하나 | 사소 |
| GO 결정 입력 | 가설마다 challenger 판정 |
| 수정 판정 매트릭스 | 대량 |
| 재QA 차이 분류 | 사소 |
| 릴리스 노트 적합성 | 독립 리뷰어(MAC-17) |
| 게시 후 공백 분류 | 사소 |
| 필수 run 실패의 flake 여부 | 사소 |
| 늦게 나온 관찰(실제 문제인지·분류) | 사소 |

메인은 통합하고 게이트 규칙을 적용만 한다(MAC-02).

## Ledger와 최종 보고(한국어)

릴리스 ledger는 scratch에 두고 compaction 뒤에도 이어서 쓴다. 열, NO-GO 보고 양식, 최종 보고 양식(산출물 타임라인, I2P-61 상태, 미검증 범위, 낡은 레지스트리 페이지), 사용자 질문 묶음 지점은 `references/ledger-and-report.md`를 따른다. 보내기 전 확인은 E2V-22·E2V-44가 정한다.

## 완료 조건

모드의 종착 상태 중 하나에 도달, 도달한 단계까지의 모든 게이트 산출물이 ledger에 있음, 정리 처분(E2V-45: 신호에 따른 행별 삭제 exit, 또는 최종 보고의 남은 행과 삭제 명령), 최종 보고 작성. 0단계에 복사한 `ledger-checklist.md` 블록의 모든 칸이 산출물 경로나 `n/a: <이유>`로 채워짐. 모드 범위 밖이거나 run이 들어가지 않은 블록은 블록 제목 아래 한 줄 `n/a: <이유>`로 닫으면 채운 것으로 치고, 그 블록의 G 줄은 쓰지 않는다(면제는 통과가 아니다).

## 교정 루프

결과가 기대와 다르면 사용자는 `isac-skill-correction`으로 이 스킬을 교정할 수 있다. 실행 중 사용자가 교정했다면 따로 묻지 말고 최종 보고에 한 줄로 안내한다. 학습 규약은 `isac-skill-correction` 소유다.
