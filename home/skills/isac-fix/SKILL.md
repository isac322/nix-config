---
name: isac-fix
description: Use when turning a GitHub issue whose defect, root cause, and fix direction are confirmed into a mergeable pull request — debate and agree on a QA list before implementing, implement with TDD, run and codify every QA item as tests, prove old-fails/new-passes, open an English PR that closes the issue, and drive CI to green; including "이슈 고쳐서 PR 만들어", "이 이슈 PR 만들어", "이슈 고치고 ci 다 통과시켜", "이슈들 병렬로 해결해", "근본 원인이 맞으면 pr 만들어". Not for triaging or labeling issues (isac-triage), reviewing a PR as the reviewer (isac-review), answering review feedback on your own PR (receiving-code-review), or PRs that do not resolve a GitHub issue.
---

# GitHub Issue to PR

원인과 수정 방향이 확정된 이슈를 머지 가능한 PR로 만든다. 순서가 핵심이다: **구현 전에 QA list를 합의**하고, 구현 후 그 QA를 전부 실행하고 테스트 코드로 남기고, 옛 버전 실패와 새 버전 통과를 증명한 뒤에만 PR을 연다.

## 소유 경계

- 재현·판정·fix provenance는 `issue-validation`, 근본 원인은 `five-whys-root-cause-analysis`, 라벨·분석 댓글·구조 변경 정의와 선택지 조사는 `isac-triage`가 맡는다.
- 토론·합의 절차, 이슈별 owner 병렬, 리뷰-GREEN 루프, 판정 어휘, 규모 게이트는 `isac-consensus`가 맡는다.
- 사용자에게 묻는 형식은 `isac-brief`, GitHub 쓰기(게시/초안 모드, 영어, 문체, 공개 위생, 중복 확인)는 `isac-publish`가 맡는다.
- PR 리뷰 기준은 `isac-review`, 받은 리뷰 대응은 `receiving-code-review`, 실환경·공유 환경 QA의 안전 절차는 `isac-live-qa`가 맡는다.
- 전역 가드(PR 생성과 생성 승인, 머지와 머지 승인, 리뷰 처리, task-intent, application-code 승인, public-api, destructive, verification)는 이름으로만 따르고 다시 쓰지 않는다.

## 0단계: 프로젝트 훅과 모드

`gh repo view --json nameWithOwner,visibility,defaultBranchRef`로 대상과 기본 브랜치를 확인한다. 이하 `main`은 그 기본 브랜치를 뜻한다. 이 스킬의 `references/projects/<owner>__<repo>.md`가 있으면 먼저 읽는다(공개 저장소만 둔다). 비공개 저장소의 프로젝트 사실은 그 저장소 자체 지침(AGENTS.md, `.agents/skills`)에 있다. 프로젝트 문서는 기본값을 좁히거나 구체화할 뿐 `[U]` 규칙과 전역 가드를 완화하지 못한다.

게시 모드와 초안 모드는 `isac-publish`로 판별한다. 분석만 요청받았으면 저장소 밖 scratch에서 QA list·수정안·PR 본문 초안까지만 만들고, 최종 보고에 게시 가능함을 한 줄로 알린다.

## 흐름

순서를 바꾸지 않는다. 앞 단계가 끝나지 않으면 다음 단계로 가지 않는다.

1. 진입 확인 — I2P-01
2. 중복·열린 PR 확인 — I2P-02
3. 계획: 흐름별 세부 기획, 방식·OSS 재사용 토론 — I2P-07~08, I2P-10, I2P-63
4. 코어·구조 변경 게이트. 해당하면 멈추고 승인받는다 — I2P-14~17
5. **구현 전** QA list 토론·합의(`isac-consensus`) — I2P-22~23
6. 구현(TDD): 첫 구현 묶음의 QA 테스트를 먼저 쓰고 실패를 확인한 뒤 고친다 — I2P-18~21
7. QA list 전체 실행과 재검증 반복 — I2P-24, I2P-26~30
8. 나머지 QA 항목 전부를 테스트 코드로 — I2P-33~40
9. 회귀 증명(old 실패 / new 통과 + healthy control), 구현자와 분리된 교차 리뷰 — I2P-25, I2P-32
10. PR 생성: 영어 본문(`isac-publish`), `Fixes #N` — I2P-41~45
11. CI 루프: 테스트를 약화하지 않고 green까지 — I2P-46~50
12. 독립 리뷰(`isac-review`). finding은 담당자가 같은 PR 브랜치에서 고치고 7~9를 다시 돈 뒤 11로 돌아간다 — I2P-51
13. 제보자 동등 환경 검증(브랜치 산출물, I2P-28 방식) — I2P-25, I2P-52
14. mergeable로 종료. 머지는 전역 merge 가드와 현재 지시가 허용하고 1~13이 모두 끝났을 때만 한다 — I2P-52~56
15. 머지 후 이슈 종료 댓글, 릴리스 안내, 단계별 완료 보고 — I2P-57~61

## 진입과 범위

- **I2P-01** [U] 진입 조건: 이슈가 "실제 문제이고 근본 원인이 우리 코드의 결함"으로 확정되고 수정 방향이 정해졌거나(`triage:fix-direction-decided`), 사용자가 직접 수정을 지시한 경우다. 사용자가 테스트 harness·oracle 결함 수정을 지시하면 그것도 대상이고 분류만 달리 적는다. `triage:needs-structural-change`이면 `isac-triage`의 구조 변경 승인부터 거친다. 조건이 없으면 `isac-triage`를 먼저 돌린다(초안 모드 가능). triage 결과는 코드 변경 권한이 아니다. 구현·커밋·PR 권한은 현재 요청과 전역 task-intent·application-code 가드가 정한다.
- **I2P-02** [U] 이슈 일괄 처리에서 대상 이슈에 이미 열린 PR이 있으면 기본으로 그 이슈는 건너뛰고 중복 PR을 만들지 않는다. 기존 PR이 못 푸는 잔여 결함은 분석해 `isac-triage` 경로로 이슈 댓글에 남긴다. 사용자가 잔여 결함 수정이나 기존 PR 처리를 지시하면 그 지시(새 PR, 기존 PR 댓글·push)를 따른다.
- **I2P-03** [U] 버그 수정은 관측된 사례 하나로 끝내지 않고 같은 근본 원인의 다른 발현 위치(형제 모듈·리소스)까지 찾아 함께 고친다. 범위는 합의된 공통 원인까지다. 기능을 "전부/다" 지원하라고 했거나 공식 API·스키마를 옮기는 작업이면 공식 스키마와 구현을 한 줄씩 대조한 누락 인벤토리를 만든다(방법: `isac-triage` 스킬의 구조 변경 조사 절차, TRI-25).
- **I2P-04** 범위 선택지를 줄 때는 완전한 옵션(제품 생명주기의 정식 구현, 나머지 기능까지 검증)을 (권장)으로 둔다. 테스트 환경의 수동 임시 우회를 권장하지 않는다.
- **I2P-05** 이 변경이 들인 결함과 대상 이슈(I2P-03의 같은 원인 형제 결함 포함)만 고친다. 범위 밖의 기존 결함이나 업스트림 결함은 조건과 증거를 붙여 PR 본문의 NOT changed나 별도 이슈로 남기고, "해결됨"으로 보고하지 않는다.
- **I2P-06** [U] 요구가 여러 번 쌓인 긴 작업은 지금까지의 요구를 종합해 예산 없는 goal로 잡고 지정된 end state(구현, QA, CI green, 요청 시 머지)까지 간다.

## 오케스트레이션

- **I2P-07** [U] 이슈가 여럿이면 `isac-consensus`의 항목별 owner 병렬과 워크스트림 세부 기획 규칙을 따른다. 이 스킬에서 owner는 분석, 재현, 근본 원인 확인, 구현, QA, e2e 테스트 작성까지 이슈를 끝까지 맡고, main은 이슈별 작업을 직접 하지 않는다.
- **I2P-08** [U] 이전 파이프라인을 "똑같이" 하라고 하면 세션 기록에서 정확한 방법을 찾아 단계 하나 빠뜨리지 않고 다시 적용한다. 세션 원본 위치는 `isac-correct` 스킬의 세션 탐색 방법을 쓴다.
- **I2P-63** 구현한 에이전트는 자기 변경의 리뷰어를 겸하지 않는다. 이슈가 하나여서 main이 직접 구현했다면 9단계와 12단계 리뷰는 구현에 참여하지 않은 리뷰어가 한다.
- **I2P-10** [U] 새 방식·도구·테스트 인프라를 도입하는 수정이면 구현 전에 여러 에이전트가 "이 방식이 사용자 목적을 달성하는가", "각 기획 요소를 그대로 승인해도 되는가"를 토론해 합의한다. 그다음 같은 일을 하는 안정적인 OSS가 있는지 찾는다. 재사용이 기본이고 직접 구현은 차선이다.
- **I2P-11** 이슈마다 최신 `origin/main`에서 만든 전용 worktree와 브랜치에서 일하고 사용자의 main checkout은 건드리지 않는다. 자기 브랜치·PR·이슈 댓글만 만지고, 리뷰 대응이 끝날 때까지 worktree를 유지한다.
- **I2P-12** [U] old/new QA와 자기 파일의 focused test는 이슈 owner 에이전트가 직접 돌린다.
- **I2P-13** 프로젝트 전역 lint, format, type check, 전체 suite는 통합 후 main이 한 번 돌린다. 슬라이스·통합·repair 기본값은 `references/defaults.md`에 있다.

## 승인 게이트

- **I2P-14** [U] 근본 원인 해결이 프로젝트의 핵심을 바꿔야 하면 구현 전에 멈추고 자초지종을 설명해 승인받는다. "핵심(구조 변경)"의 정의와 선택지 조사는 `isac-triage` 스킬(TRI-25)을, 질문 형식은 `isac-brief`를 따른다. 핵심이 아니면 묻지 않고 곧바로 QA list 단계로 간다. 계획 단계에서 이미 결정된 변경(사용자가 승인한 구조 변경 방향, `triage:fix-direction-decided`로 확정된 수정 방향, 사용자의 직접 수정 지시)은 전역 `application-code-change-approval`이 말하는 식별된 범위의 승인이므로 구현 단계에서 다시 묻지 않고 진행한다. 구현 중 그 결정 밖의 새 구조 변경이 필요해질 때만 같은 게이트로 돌아가 다시 승인받는다.
- **I2P-15** [U] 승인된 goal이나 brief 안에서 goal 달성을 막는 버그(e2e·QA가 드러낸 코드 버그 포함)는 하나하나 묻지 않고 고친다. brief가 이미 허가한 수정을 다시 묻지 않는다.
- **I2P-17** 기능 유지(플랫폼 한계 문서화)와 fail-closed(기능 제거)가 부딪치면 추측하지 않고 사용자에게 올린다. 기능 유지를 고르면 한계를 명시하고 실제 앱 E2E로 검증한다.

## 수정 설계

- **I2P-18** 증상이 아니라 불변식이나 근본 원인을 고친다. blind retry, jitter, 무한 대기, 근거 없는 timeout 증가, 특정 입력 special-case, assertion 약화나 skip, race를 고정 delay로 덮기는 금지다. 원인이 업스트림에 있으면 우리 쪽 불변식(backend 선택, controlled error, 정확한 보고)을 고치고 업스트림 부분은 증거와 함께 문서화하되 고쳤다고 주장하지 않는다.
- **I2P-19** 기존 안전 의미론(fail-closed, 소유권 검증, revocation, 관측 전용 모드의 무쓰기)을 약화하지 않는다. 보안 수정의 acceptance는 부정 불변식("X는 절대 일어나지 않는다")과 정상 동작 보존으로 적는다.
- **I2P-20** 라이브 e2e에서 드러난 외부 API 응답 결함은 클라이언트에서 견고하게 처리하고 클라이언트 회귀 테스트를 붙인다.
- **I2P-21** 문서가 이제 틀린 동작을 서술하면 같은 PR에서 고친다. CHANGELOG `[Unreleased]`의 맞는 섹션에 사용자 가시 변경을 적고, 과거 릴리스 항목은 고치지 않는다.

## QA list (구현 전)

- **I2P-22** [U] 구현 전에(TDD식) 이 변경이 문제를 일으킬 수 있는 모든 위치를 먼저 고민해 QA list를 만든다. 에이전트 하나가 아니라 여러 에이전트가 각자 영향 반경을 파악하고 토론·합의로 확정한다. 절차는 `isac-consensus`(QA 목록 판정)를, 영향 반경 각도·QA-ID 표·통합 산출물은 `references/qa-debate.md`를 따른다.
- **I2P-23** 각 QA 항목은 안정 ID, 기대 동작, 효과를 증명하는 관측, 덮을 테스트 이름과 계층, 실행 가능성(executable / conditional / permission-negative / BLOCKED)을 갖는다. 알려진 계약 편입 트랙과 미지 버그 탐색 트랙을 섞지 않는다.

## QA 실행과 회귀 증명

- **I2P-24** [U] 구현이 끝나면 QA list 전체를 실행하고, 모든 항목이 통과하고 CI가 전부 green이 될 때까지 고친다.
- **I2P-25** [U] 이슈 owner가 직접 같은 테스트 코드로 이전 버전에서는 문제가 재현되고 새 버전에서는 해결됨을 확인하고, healthy control도 함께 돌린다. 이 확인이 끝나야 PR을 연다. 제보자 환경이나 동등한 환경에서 새 버전으로 재현이 사라짐을 확인하는 것은 머지 전 조건이다(I2P-52). 방법은 `references/test-codification.md`에 있다.
- **I2P-26** 수정과 재검증 반복은 `isac-consensus`의 리뷰-GREEN 루프를 따른다. 이 스킬에서 "같은 절차"는 QA list 전체와 앞서 돌린 old/new·동등 환경 검증 명령이다.
- **I2P-27** [U] 우회 경로로 통과시키고 "완료"라고 하지 않는다. 검증 대상 기능 자체가 실제 경로로 동작해야 완료다. 외부 자원을 관리하는 제품이면 "제품이 실제로 했는가"는 제품이 기록한 원격 식별자와 외부 시스템의 실제 객체를 1:1로 대조해 증명한다.
- **I2P-28** [U] 설치·실사용 검증(데모, 릴리스 후 확인, 설치 경로 이슈, 제보자 동등 환경 검증)에서는 README의 공개 설치 방법으로 설치한 산출물로 검증하고 소스 트리 직접 실행이나 개발용 지름길을 쓰지 않는다. 수정이 아직 릴리스 전이면 브랜치에서 릴리스와 같은 방식(wheel, 이미지, 패키지)으로 산출물을 빌드해 같은 설치 방법으로 설치한다. 막히면 문서에 없는 패키지나 숨은 우회를 쓰지 않고 실제 실패를 보고하며 문서나 코드 수정을 제안한다. 보고에는 설치 방법, README 경로 일치 여부, 설치·실행 중 문제를 적는다. 어느 검증이든 API 성공 문자열이 아니라 실제 결과를 본다.
- **I2P-30** pass / fail / blocked를 분리해 보고하고 blocked를 pass로 세지 않는다. 권한 부족으로 못 하는 쓰기는 빼지 않고 permission-denial 테스트나 blocked 항목으로 남긴다. 실환경·공유 환경에서 돌릴 항목은 `isac-live-qa`의 안전 절차를 거친다.
- **I2P-32** PR 전에 `isac-consensus`의 독립 리뷰어 규칙대로 구현과 분리된 리뷰어가 현재 worktree를 교차 리뷰하고, 그 루프의 종료 조건을 만족해야 PR을 연다.

## 테스트 코드화

- **I2P-33** [U] 머지 전에 QA list의 모든 항목이 테스트 코드에 들어가 있어야 한다. QA와 e2e 테스트 코드 작성은 선택이 아니다.
- **I2P-34** [U] 테스트 구조는 테스트 피라미드를 따른다. 항목별 계층은 목록을 하나씩 분석하고 에이전트 토론으로 합의한다. 프로젝트에 공식 conformance suite가 있으면 그것을 최상위에 둘지 별도 e2e를 둘지도 토론으로 정한다.
- **I2P-35** [U] 각 QA 계약은 그것을 증명할 수 있는 가장 낮은 계층에 둔다. 계층 기준과 QA-ID별 배치 표는 `references/test-codification.md`를 따른다. fake가 우리 가정을 그대로 구현할 뿐이면 그 항목은 e2e로 남긴다.
- **I2P-36** [U] 커버리지가 부족하면 축소가 아니라 확장으로 푼다. 낮은 계층이 같은 계약을 증명할 때만 내리고, 순 계약 커버리지는 줄이지 않으며, 대체 불가능한 라이브 seam은 e2e에 남긴다.
- **I2P-37** 영구 회귀 테스트는 소비자가 관측하는 계약을 assert해서 수정을 되돌리면 실패해야 한다. 금지 패턴과 fake 기준은 `references/test-codification.md`에 있다.
- **I2P-38** 결정적 오류는 즉시 실패시키고, 전체 suite 재실행으로 흡수하지 않는다. eventual consistency 대기는 각 테스트 안의 bounded poll로만 한다.
- **I2P-39** 바뀐 테스트나 CI 게이트가 결함을 실제로 잡는지 mutation-check로 증명한다(예: 수정이나 의존성 상한을 빼면 기존 테스트가 실패한다).
- **I2P-40** 테스트만 다루는 작업 중이거나 승인된 goal 밖에서 제품 버그를 찾으면 몰래 고치지 않고 failing·skip·TODO 테스트로 커밋하지도 않는다. 최소 재현과 심볼을 담은 blocker로 보고한다. goal 안의 버그는 I2P-15를 따른다.

## PR

- **I2P-41** [U] PR 본문 등 GitHub 게시물의 언어·길이·문체는 `isac-publish`를 따른다. PR 본문은 길어져도 되며, 구조·방향이 바뀌는 PR이면 전반적 구조·방향·설계를 담는다. 사용자에게 하는 채팅 보고는 한국어로 최대한 짧고 간결하게, 글쓰기 스킬(`writing-clearly-and-concisely`, `humanizer`)을 적용해 쓴다. 본문 구성은 `references/pr-body-template.md`를 따른다.
- **I2P-42** [U] 본문에 `Fixes #N`을 쓴다. PR을 열 때 QA나 coverage audit이 부분 해결을 보이면, 또는 일부러 닫지 않을 때는 `Related to #N`을 쓰고 완료 보고에 그 사실과 이유를 명시한다.
- **I2P-43** PR을 재작업할 때 결함 귀속(main / 이전 PR head / 이 브랜치)을 정확히 적고, 사용자가 준 공개 문구는 그대로 쓴다.
- **I2P-44** [U] "PR 만들어"처럼 PR까지 요청받았으면 브랜치, 커밋, 푸시, PR을 한 흐름으로 한다. PR 생성 자체는 전역 PR 생성 가드의 메타데이터·승인 요건을 따르고, 푸시 권한이 없으면 fork 브랜치에서 base 저장소로 PR을 연다. 로컬에만 두고 "다 했다"고 하지 않는다. PR 요청이 없을 때 커밋·푸시 범위는 전역 task-intent 가드를 따르고, 한 일과 하지 않은 일(커밋, 푸시)을 보고한다.
- **I2P-45** PR의 순 diff(`git diff origin/main...HEAD`)는 의도한 변경으로 제한한다. 최신화는 `git merge origin/main`으로 하고, 리뷰어가 생긴 브랜치의 이력은 다시 쓰지 않는다. 커밋 메시지는 저장소 컨벤션을 따르고, 없으면 Conventional Commits를 쓴다.

## CI

- **I2P-46** [U] 완료 조건에는 CI 전체 통과가 들어간다. "PR 만들고 CI 다 통과시켜"는 실패를 고쳐 green까지 끌고 가라는 뜻이다. 머지 여부는 I2P-53을 따른다.
- **I2P-47** CI 실패는 진짜 원인(캐시 동기화 race, fixture 준비, 공유 fake 오염 등)을 고쳐 통과시킨다. assertion 약화, timeout 인상, 테스트 skip, 검증 우회는 금지다. 인프라성 flaky는 같은 커밋 재실행으로 판별하고 그렇게 보고한다.
- **I2P-48** 사용자가 준비할 외부 사전조건(시크릿 등) 부족으로 생긴 CI 실패는 예상된 결과로 설명하고, 조건이 충족되면 이어서 진행한다. 최종 완료 시점에는 green이어야 한다.
- **I2P-49** [U] 배포 패키지의 설치 경로 결함을 CI E2E로 막는 수정이면 최소 기준은 빌드된 산출물이 lock 없이 자기 메타데이터로 의존성을 해석해 설치되는 경로다. 사용자가 받아들인 나머지 gap까지 CI로 재현하지 않는다.
- **I2P-50** 이 스킬의 기본 종료는 PR이 열려 있고 충돌이 없고 모든 required check가 green인 상태다. 외부 요인(fork workflow 승인 대기, 필수 사람 리뷰, rerun 권한 없음)으로 막힌 항목은 각각 external blocker로 분류해 보고하고 무기한 기다리지 않는다. CI는 백그라운드로 watch한다. CI 하드닝과 비게이트 leg 기준은 `references/defaults.md`에 있다.

## 리뷰와 머지

- **I2P-51** [U] main 리뷰어(`isac-consensus`의 병렬 수정 리뷰 규칙)는 각 PR 코드를 한 줄씩 읽고 이슈와 대조해 세 가지를 판정한다: 또 다른 regression을 일으키는가, 성능 문제를 일으키는가, 이슈의 문제를 실제로 해결하는가. 기준과 판정 형식은 `isac-review`를 따른다. finding은 담당 에이전트가 고치고 CI green을 유지한다.
- **I2P-52** [U] 머지 게이트: 리뷰 통과(`isac-consensus` 리뷰-GREEN 루프 종료 조건; `PR-ready: true`만으로는 부족), QA list 전부 테스트 코드화, CI 전부 green, 회귀 테스트와 제보자 동등 환경 검증 완료. 넷이 모두 충족돼야 머지 후보가 된다. 머지 승인·방법·옵션은 전역 PR 머지 가드를 따른다.
- **I2P-53** [U] 머지 여부는 요청마다 다르다. 현재 지시를 다시 확인하고 추정하지 않는다. 머지하라는 지시가 없으면 머지하지 않는다.
- **I2P-54** [U] 여러 PR의 머지를 지시받았으면 하나씩 처리한다: 최신 main으로 up to date → CI 통과 확인 → 머지. 형제 PR이 머지되면 남은 PR은 새 main을 합치고 새 HEAD에서 전체 검증을 다시 돌린다.
- **I2P-56** 머지 승인을 구하거나 머지 알림을 줄 때 변경 범위를 명시한다: 테스트 전용인지 제품 런타임인지, 무엇을 건드리지 않았는지.

## 머지 후와 보고

- **I2P-57** [U] 머지로 `Fixes #N`이 이슈를 닫으면 종료 댓글을 남긴다: 수정 상태(merged / released 여부), 쓸 버전, 검증 범위, 제보자 환경과 다르면 그 한계. 제보자가 반박하면 재오픈한다. 템플릿은 `references/pr-body-template.md`.
- **I2P-58** [U] 확인된 결함이 모두 고쳐지고 회귀 테스트가 통과했으면 원래 환경·라이브 재검증을 못 했다는 이유로 이슈를 열어 두지 않고, 그 한계를 종료 댓글에 적는다. 확인된 잔여 결함이 있을 때만 부분 해결로 두고 남은 증상을 적는다. 동등 환경 검증 게이트(I2P-52)는 그대로다.
- **I2P-59** 머지 뒤 "실제로 해결됐냐"는 질문에는 `isac-triage`의 수정 재검증 규칙으로 답한다.
- **I2P-60** [U] 수정이 main에는 있지만 릴리스에 없으면 사용자와 제보자에게 릴리스가 필요하다는 것과 어떤 버전을 쓰면 되는지 알린다.
- **I2P-61** [U] 완료 보고는 fixed-in-PR / merged / released / deployed를 구분한다(상태 어휘는 `issue-validation`의 fix provenance). 검증한 것과 하지 않은 것(재현 안 된 조건, 에뮬레이션만 한 값, 안 돌린 테스트, 미출시 수정)을 명시한다. 형식은 이슈·원인·수정·PR 표, 검증 결과, 남은 한계다.

## 교정 루프

결과가 기대와 다르면 사용자는 `isac-correct`로 이 스킬을 고칠 수 있다. 실행 중 사용자가 교정했다면 최종 보고에 "스킬에 반영하려면 `스킬 고쳐`"를 한 줄 적는다. 실행 도중 따로 묻지 않는다.
