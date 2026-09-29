---
name: isac-skill-correction
description: Use when the user says a skill in this family (isac-issue-triage, isac-issue-to-pr, isac-pr-review, isac-live-qa, isac-skill-correction, isac-multi-agent-consensus, isac-github-publishing, isac-decision-brief, isac-e2e-issue-resolution, isac-e2e-pr-backlog, isac-e2e-qa-to-fix, isac-e2e-promo-readiness, isac-positioning, isac-brand-identity, isac-project-site, isac-discovery-surfaces, isac-demo-media) or one of its dependencies (issue-validation, five-whys-root-cause-analysis, receiving-code-review) behaved against expectations and wants the skill itself fixed, or wants a new skill added to or distilled for this family from past sessions. A read-only subagent reads the original session, the user approves a short proposal, and a subagent opens a pull request against isac322/nix-config. Takes precedence over instruction-architect for these skills. Triggers include "<skill name> 스킬 고쳐", "스킬 고쳐", "스킬에 반영해", "이 지침 때문에", "이런 건 묻지 말라고 했잖아, 스킬 고쳐", "그 세션에서 스킬이 잘못했어", "이 패밀리에 새 스킬로 만들어", "isac-skill-correction". Not for one-off corrections that need no durable change, or for skills outside this family and global policy segments (instruction-architect).
---

# Skill Correction

사용자가 레지스트리 스킬의 동작이 기대와 달랐다고 지적하면 원본 세션에서 원인 규칙을 찾아 수정안을 제안하고, 승인 후 `isac322/nix-config`에 PR을 연다. 학습 규약(규칙 ID, `[U]`, `references/cases.md`, 프로젝트 훅, 교정 루프, 승격·재발 처리, 파일 위생)의 정본은 `references/cases-format.md`다. 다른 스킬은 이 스킬 이름으로만 참조한다. 아직 어느 스킬에도 배치되지 않은 사용자 요구는 `references/backlog.md`에 둔다.

`[U]` = 사용자 지시·교정·승인에서 온 규칙(사용자 승인 없이 완화·삭제 불가). 태그 없음 = 바꿀 수 있는 기본값.

## 레지스트리

정본 경로는 모두 `home/skills/<name>/`다(저장소 `isac322/nix-config`, 공개). 의존 스킬은 규칙 ID가 없으므로 `SKILL.md` 섹션 제목으로 지목하고, 첫 교정 때 그 스킬에 `references/cases.md`를 만든다.

| 스킬 | ID | 등급 | 소유 범위 |
|---|---|---|---|
| `isac-issue-triage` | TRI | 패밀리 | 버그 이슈 판독 → 이슈 라벨 의미 + 분석 코멘트, 구조 변경 방향 조사 |
| `isac-issue-to-pr` | I2P | 패밀리 | 방향 확정 이슈 → QA 리스트 합의 → 구현 → QA 코드화 → 회귀·동등환경 검증 → PR → CI green → mergeable |
| `isac-pr-review` | PRR | 패밀리 | PR 반경·심각도·실제 해결·보안·성능·구조 리뷰, 판정별 리뷰 이벤트(APPROVE/REQUEST_CHANGES/COMMENT), 외부·오래된 PR 감사 |
| `isac-live-qa` | LQA | 패밀리 | 배포 환경 탐색 QA → 이슈, 인터뷰·위험 고지·허용범위·격리·복구, 문제 판단 기준 |
| `isac-e2e-issue-resolution` | E2I | e2e | 이슈 1~N개 intake → 중복 정리 → 이슈별 단계 전이·종착 상태(트리아지 → 수정 PR → 리뷰 → 머지 → 종료 알림, 또는 정보 요청 등에서 멈춤) → ledger·최종 보고 |
| `isac-e2e-pr-backlog` | E2P | e2e | 열린 PR 묶음 감사 → 판정 → 수정 push·최신화 → 순차 머지 또는 근거 댓글과 close → 남은 main 문제 인계 |
| `isac-e2e-qa-to-fix` | E2Q | e2e | 라이브 QA → 이슈 등록 → 이슈 해결(E2I) → 반영 지점 이후 같은 QA 재검증 루프 |
| `isac-e2e-promo-readiness` | E2R | e2e | 홍보 준비 오케스트레이션: 착수 계약 → 병렬 조사·토론 → 스티어링 리포트 페이지 → 영역별 위임 → 오너 프리뷰·승인 게이트 → 배포·외부 사본 교체 → 전 표면 라이브 감사 |
| `isac-positioning` | POS | 패밀리 | 저장소 감사·경쟁/선례·검색 의도 조사 → 단일 포지셔닝 소스(셀링 포인트·반(反)주장·성숙도 표기) |
| `isac-brand-identity` | BRD | 패밀리 | 이름·상표 확인, impeccable 기반 로고·색, SVG 우선 브랜드 키트·생성기, 아이콘·소셜 이미지, 리브랜드 전 표면 재검증 |
| `isac-project-site` | SITE | 패밀리 | 랜딩·문서 사이트(Astro/Starlight/Bun): IA·자체 표면 카피·impeccable 디자인·기술 SEO·도메인 IaC·분석 연결·시각 QA |
| `isac-discovery-surfaces` | DSC | 패밀리 | README·GitHub 저장소 표면·커뮤니티/신뢰 신호·레지스트리 메타데이터, code==docs==site==listings 일관성 게이트 |
| `isac-demo-media` | MED | 패밀리 | 스크린샷·녹화: 재현 가능한 스크립트 캡처, 타이밍 검증, 형식 규칙, 표면별 규격 |
| `isac-skill-correction` | SKC | 패밀리 | 교정 워크플로, 레지스트리, 학습 규약, 세션 탐색, backlog |
| `isac-multi-agent-consensus` | MAC | 공유 | 독립 조사 → 상호 반박 → 합의·중재, GREEN 리뷰 루프, 판정 어휘, 규모 게이트 |
| `isac-github-publishing` | GHP | 공유 | GitHub 쓰기 공통: 영어·위생·중복 확인·댓글 수정 vs 신규·라벨 메커닉·부모만 게시 |
| `isac-decision-brief` | DBR | 공유 | 사용자에게 묻는 형식과 묻지 않을 것 |
| `issue-validation` | — | 의존 | 주장 분해, 실행 재현, 판정, fix provenance |
| `five-whys-root-cause-analysis` | — | 의존 | 증거 기반 인과 그래프 RCA, 교정 조치 적합성 |
| `receiving-code-review` | — | 의존 | 받은 리뷰의 평가·대응 기법 |

## 0. 준비

원본 세션이 작업한 저장소를 그 세션의 cwd에서 `gh repo view --json nameWithOwner,visibility`로 확인한다(cwd가 이 호스트에 없으면 세션 기록의 remote 정보로 판단한다). 결과는 반영 위치 분류(SKC-11)에 쓴다. owner 스킬에 `references/projects/<owner>__<repo>.md`가 있으면 분석 서브에이전트가 함께 읽는다. 프로젝트 문서는 기본값을 좁히거나 구체화만 하고 `[U]` 규칙과 전역 가드를 완화할 수 없다.

## 1. 발동과 즉시 반영

- **SKC-01** [U] 발동: 사용자가 레지스트리 스킬의 동작을 지적하며 고치라고 하거나("스킬 고쳐", "스킬에 반영해", "이 지침 때문에…"), 과거 세션·사례를 지목해 스킬 개선을 요청할 때다. 지적만 하고 고치라는 요청이 없으면 발동하지 않는다. 그 경우는 해당 스킬의 교정 루프가 최종 보고에 한 줄로 안내한다.
- **SKC-02** [U] 발동하면 현재 세션에서 받은 교정을 즉시 현재 작업의 standing constraint로 삼아, 같은 종류의 질문·실수를 반복하지 않는다. 실행 중인 서브에이전트 전파는 `isac-multi-agent-consensus`, 이미 답한 것을 다시 묻지 않는 기준은 `isac-decision-brief`를 따른다. 영속화는 이 스킬의 제안·승인 경로로 한다.
- **SKC-35** 교정 절차가 원래 작업을 막지 않게 한다. 분석 서브에이전트는 백그라운드로 돌리고, SKC-15 제안은 원래 작업의 다음 사용자 보고 지점이나 최종 보고에 붙인다. 사용자가 스킬 교정을 요청했거나 교정을 먼저 하라고 했으면 분석이 끝나는 즉시 보인다.
- **SKC-03** [U] 교정 대상은 레지스트리 표의 스킬뿐이다. 원인이 전역 policy segment, instruction-architect, 기타 스킬이면 고치지 않는다. `out-of-family: <소유 자산>`으로 보고하고 instruction-architect 경로를 안내한다. 의존 스킬 변경안에는 "패밀리 밖 사용처에도 영향"을 부작용으로 적는다.

## 2. 세션 조사 (메인 컨텍스트 보존)

- **SKC-04** [U] 메인은 세션 JSONL의 내용을 읽지 않는다. 메인은 `references/session-sources.md`로 세션 파일 경로, 앵커 msg id, 서브에이전트 transcript 디렉터리만 해석해 넘긴다. 경로·앵커 확정에 필요한 스크립트 검색은 매치된 id와 시각만 출력하는 경우에 한해 허용한다. 내용 분석은 읽기 전용 분석 서브에이전트가 `references/analysis-brief.md`의 위임문과 outputSchema로 한다. 메인이 받는 것은 스키마 결과뿐이다.
- **SKC-05** [U] 분석은 세션 전체를 코드로 전수 순회한다. 모든 record, 사용자 메시지, ask 답변, goal 텍스트, 직전 에이전트 행동, 필요한 서브에이전트 transcript가 대상이다. 앞뒤나 검색 샘플만 읽으면 실패다.
- **SKC-06** 근거 가중치는 사용자 지시·교정·ask 답변 > 승인된 제안 > 에이전트 관례 순이다. 에이전트 문장(위임문 제약, 사후 설명, 자기 보고)을 사용자 근거로 쓰지 않는다.
- **SKC-07** 분석은 세션 당시 로드된 스킬 문구와 `origin/main` 정본을 비교하고, owner 스킬의 `references/cases.md`와 열린 교정 PR을 확인한다. 이미 고쳐졌으면 `already-fixed`다. 같은 케이스가 있으면 새 케이스 대신 재발로 처리한다(`references/cases-format.md`).
- **SKC-08** [U] 여러 세션·사례를 한 번에 교정하거나 세션에서 스킬을 새로 증류할 때는 세션·도메인별 병렬 서브에이전트로 추출하고, 분류·배치 결정은 `isac-multi-agent-consensus`로 교차 검증·합의한다.

## 3. 원인 판정과 반영 위치

- **SKC-09** 원인은 `wrong | loose | missing | conflict | not-followed` 중 하나와 규칙 ID로 적는다. 규칙이 사용자 기준보다 느슨하면 사용자 기준에 맞춰 강화한다. 사용자 교정으로 확정된 증거 기준은 그대로 옮기고 완화하지 않는다. 맞는 규칙이 처음 지켜지지 않은 `not-followed`는 규칙 문구를 바꾸지 않고 케이스만 기록한다(`references/cases-format.md`).
- **SKC-34** [U] 사용자 발화 하나를 그 자체로 규칙으로 일반화하지 않는다. 규칙은 그 발화가 나온 상황과 대상(작업 종류, 저장소 소유권·가시성, 산출물 종류, 위험도)과 함께 도출하고, 제안에 적용 조건을 적는다. 그 상황에만 해당하는 일회성 지시는 규칙이 아니라 케이스로 남긴다.
- **SKC-10** 규칙 부재가 원인이면 가장 가까운 단계 스킬에 추가하는 안을 낸다. 새 스킬이 필요하면 제안에서 명시적으로 묻는다.
- **SKC-11** [U] 반영 위치를 분류해 제안에 넣는다. 위에서부터 먼저 맞는 것을 고른다. 분석 위임문(`references/analysis-brief.md` 7단계)도 이 목록과 순서를 그대로 쓴다. 반영 위치와 케이스 `일반화` 값의 대응은 `references/cases-format.md`에 있다.
  - `memory`: 특정 저장소·대상에만 적용되는 사용자의 작업 방식 선호(예: 한 저장소의 머지·승인 방식). 레지스트리 규칙이 다루는 행동이라도 그 저장소 한정 예외면 여기다. memory에만 두고, 커밋되는 어떤 파일에도 넣지 않는다.
  - `skill`: 레지스트리 스킬 규칙이 다루는 행동을 저장소와 무관하게 바꾸는 교정(질문·승인 방식이라도 `isac-decision-brief` 등 레지스트리 규칙이 다루면 여기), 또는 저장소와 무관하게 이 패밀리 작업에 적용할 새 행동 규칙 → owner 스킬 정본(nix-config PR). 사용자가 레지스트리 스킬을 고치라고 한 저장소 무관 교정은 memory로 낮추지 않는다.
  - `out-of-family`: 레지스트리 규칙이 다루지 않는 전역 정책 의미(승인·머지·검증 등)나 레지스트리 밖 스킬 → instruction-architect 경로 안내.
  - `repo-harness`: 그 저장소에서 일하는 모든 에이전트가 따라야 할 공유 규칙·암묵지, 비공개 저장소의 사실 → 그 저장소의 자체 지침(AGENTS.md, `.agents/`). nix-config에는 쓰지 않고, 이 스킬은 그 저장소를 수정하지 않고 안내만 한다.
  - `project-reference`: 공개 저장소 자체의 사실·기본값(명령, 경로, 라벨 매핑 등) → owner 스킬 `references/projects/<owner>__<repo>.md`(nix-config PR).
- **SKC-12** [U] 저장 위치가 틀렸다는 교정이면 잘못 넣은 변경을 먼저 되돌리고 올바른 위치에 저장한 뒤, 어디에 무엇을 넣고 무엇을 되돌렸는지 보고한다. nix-config의 잘못된 변경은 같은 교정 PR에서, memory의 잘못된 항목은 승인 후 직접 되돌린다. 다른 저장소에 잘못 쓴 것은 이 스킬이 되돌리지 않지만 빠뜨리지 않는다: 제안의 반영 위치 줄과 최종 보고에 `revert needed: <repo>/<file> — not done by this skill`로 적는다. 되돌림이 다른 사람의 작업을 덮으면 `destructive-operations`를 따른다.
- **SKC-13** `[U]` 규칙을 완화·삭제·의미 변경하는 안은 `references/cases.md` 출처 색인의 원 지시를 인용해 명시한다. 새 교정과 기존 `[U]` 규칙이 충돌하면 시간순으로 덮지 않고 두 근거를 나란히 보여 사용자가 고르게 한다. 전역 가드와 충돌하면 스킬이 진다(`out-of-family`).

## 4. 제안과 승인 게이트

- **SKC-14** [U] 사용자가 "스킬 고쳐"라고 했더라도 이 스킬은 제안이 승인되기 전에 어떤 쓰기도 하지 않는다(브랜치, 커밋, memory, GitHub 포함). 전역 `task-intent-boundary`보다 엄격한 이 스킬의 자체 게이트이며, 가드는 그대로 적용된다.
- **SKC-15** [U] 제안은 `isac-decision-brief` 형식의 한국어 글이다. 짧게 쓰되 현상, 원인 규칙, 변경안, 적용 조건을 빠짐없이 담는다(약 10줄은 기본값). diff 원문은 요청할 때만 보인다.

  ```text
  이해한 문제: <사용자에게 보인 현상, 기대 vs 실제>
  원인: `<스킬>` <규칙 ID> "<현재 문구 요지>" — <분류>
  변경안: <before 요지> → <after 요지> | 규칙 유지, 케이스 기록 (케이스 CASE-YYYYMMDD-<slug>)
  적용 조건: <상황·대상 경계>  / 반영 위치: <skill | project-reference | repo-harness | memory | out-of-family>
  정본 기준: <main | 열린 PR head (main에 아직 없을 때)>
  부작용: <영향 범위>  / [U] 규칙 변경: <아니오 | 예: 원 지시 인용>
  진행할까요? (예 / 수정: … / memory에만 저장 / 취소)
  ```

- **SKC-16** [U] 승인 1건은 그 교정 PR 1건의 생성(브랜치, 서명 커밋, push, PR)까지만 유효하다. 머지와 `darwin-rebuild switch`는 하지 않는다. 머지는 `pull-request-merge-authorization` 가드와 사용자의 별도 지시를 따른다. `memory`로 분류된 교정은 승인 후 memory 저장만 하고, `repo-harness`와 `out-of-family`는 안내로 끝낸다.

## 5. PR 서브에이전트

- **SKC-17** [U] 승인 후 PR은 서브에이전트가 연다. 대상은 세션이 작업한 저장소가 아니라 스킬 정본 저장소 `isac322/nix-config`다. 위임문은 `references/pr-brief.md`다.
- **SKC-30** PR 서브에이전트는 `$TMPDIR` 스크래치 SSH clone에서 정본 기준 ref(보통 `origin/main`)로부터 `skill-fix/<skill>-<slug>` 브랜치를 만들어 작업하고, `/etc/nix-darwin` 작업 트리와 `.git`은 건드리지 않는다. instruction-architect 스킬을 먼저 읽고 그 편집 절차와 검증을 따른다. 원 사례의 검증을 다시 돌릴 수 있으면 그 절차를 레시피로 적고, 수정 후 같은 절차를 틀린 결과가 0이 될 때까지 반복한다.
- **SKC-18** [U] PR 본문은 영어로 쓰고 Problem / Direction / Rationale을 담는다. Rationale에는 사용자 지적의 요약과 원인 규칙 위치를 넣는다. Source case / Changed rules / Verification 섹션은 `references/pr-brief.md` 템플릿의 기본값이다. 문체·공개 위생은 `isac-github-publishing`, PR 생성 조건은 `pull-request-creation` 가드를 따른다.
- **SKC-19** 편집은 최소·정밀하게 한다. 사례가 반증한 문구만 고치고, 넓은 규칙은 대상별로 쪼개고, 잘못된 성격 규정은 정정한다. 전체 재작성, 무관한 규칙 동시 수정, 존재하지 않는 명령 발명을 하지 않는다. 세션 보고서에서 온 숫자와 경로는 현재 코드로 다시 확인하고, 중간 설계 발언과 최종 구현을 구분한다.
- **SKC-20** [U] nix-config에 반영하는 교정(`skill`, `project-reference`)은 owner 스킬 `references/cases.md`(프로젝트 문서면 그 `## Cases`)에 케이스로 남긴다. 재발 확인 기준은 필수다. `memory`, `repo-harness`, `out-of-family` 교정은 케이스를 만들지 않고 최종 보고에 반영 위치만 적는다.
- **SKC-21** cases.md와 스킬 파일의 공개 위생은 `references/cases-format.md`, PR 텍스트의 위생은 `isac-github-publishing`을 따른다.

## 6. 스킬 편집 원칙 (교정·신설 공통)

정본 위치, 의미 중복 검사, 단일 소유, `references/` 분리, cutover 정리는 instruction-architect가 소유한다. 아래는 이 패밀리에 더하는 기준이다.

- **SKC-22** [U] 판단 기준은 널리 통용되는 방법론과 업계 표준을 깊게 조사해 적용한다.
- **SKC-23** [U] 새 스킬은 실제 작업 사례(수행한 작업이나 과거 세션)에서 배운 것과 일반 방법론을 합쳐 만든다. 워크플로의 각 단계가 스킬 분할 단위다.
- **SKC-24** [U] 프로젝트 고유 지침은 범용 본문에 섞지 않고 같은 스킬의 `references/`로 분리한다.
- **SKC-25** [U] 다른 스킬은 이름으로 참조해 조합한다. 글쓰기는 `writing-clearly-and-concisely`와 `humanizer`를 호출한다.
- **SKC-26** [U] always-load와 on-demand는 비용과 성능 기준으로 나눈다. 하네스별 로딩·import 의미론을 확인하고, 비용 절감이 없는 분할·import 구조는 쓰지 않는다. 크기 목표와 기본값 배치 기준은 `references/cases-format.md`에 있다.
- **SKC-27** [U] 스킬 신설이나 여러 규칙 변경은 혼자 끝내지 않고 에이전트 간 교차 검증·토론·합의로 감사한다(`isac-multi-agent-consensus`).
- **SKC-31** 감사 순서: 초안 → 독립 감사(의미 중복, 인정된 외부 방법론 대비 엄밀성, reference 도달성, 트리거 충돌) → 수정 → 변경분만 재감사, blocker 0이면 끝낸다. 단일 규칙 최소 수정은 PR 서브에이전트의 자체 점검으로 충분하다.
- **SKC-32** 분할한 스킬은 겹치지 않는 범위와 명시적 handoff 계약으로 잇고 description 트리거가 서로 충돌하지 않게 한다. 위임문에는 관련 스킬 읽기를 필수로 넣는다.
- **SKC-33** 금방 낡는 사실(PR 번호, 릴리스 상태, 개수, 버전)은 본문에 넣지 않는다. 변하는 값은 동적 source of truth를 가리키고, 코드 위치는 찾는 단서로만 쓴다. 줄 번호는 쓰지 않는다(시점이 고정된 증거 인용은 예외).

## 7. 보고

- **SKC-28** [U] 최종 보고는 한국어로 짧게 쓴다. PR URL, 실제로 실행한 검증과 결과, "머지와 `darwin-rebuild switch` 전에는 배포되지 않는다"를 적는다. 여러 파일을 바꿨으면 파일마다 무엇을 소유하는지 한 줄씩 브리핑한다.
- **SKC-29** 배포 뒤 사용자가 확인을 원하면 새 세션을 여러 cwd에서 띄워, 주입된 컨텍스트만으로 정해진 한 줄 출력(예: `SKILL=<name> RULE=<ID> PRESENT=yes`)을 내게 하는 결정적 probe로 로딩과 문구를 확인한다.

## 경계

- 저장 위치 판단의 세부(semantic class, 의미 중복 검사, 생성 mirror 편집 금지, Nix 검증, 배포 전 active 주장 금지)는 instruction-architect가 소유한다.
- 완료 판정을 원래 목적과 대조하는 기준과 실행하지 않은 검증 주장 금지는 전역 `verification`이 소유한다.
- 교정 PR에 달린 리뷰 대응은 `receiving-code-review`와 전역 review-handling 가드를 따른다.

## 교정 루프

이 스킬의 결과가 기대와 다르면 사용자는 `isac-skill-correction`으로 이 스킬 자체를 교정할 수 있다. 실행 중 사용자가 교정했다면 따로 묻지 말고 최종 보고에 한 줄로 안내한다. `references/cases.md`는 교정할 때만 읽는다.
