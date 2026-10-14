# 단계·게이트·방법 (0단계에 전부 읽고, 재개 뒤 현재 단계 절을 다시 읽는다)

규칙 문장은 SKILL.md의 `E2V-nn`이 소유한다. 이 파일은 단계 사이 전이 조건, 게이트마다 ledger에 남겨야 하는 종료 산출물, 그리고 각 단계의 방법을 적는다. ledger 열과 보고 템플릿은 `ledger-and-report.md`, 바꿀 수 있는 숫자와 운영 기본값은 `defaults.md`가 소유한다. 다른 스킬의 절차는 이름과 rule ID로만 가리키고 여기서 다시 쓰지 않는다.

## 1. 단계 흐름

```text
0 intake·preflight ─▶ 1 변경 목록·버전 근거 ─▶ [analysis 모드: ANALYSIS_DONE]
                                │
                                ▼
                 2 후보 검증(차등) ─▶ G-GO
                     ├─ GO ──────────────────────────────────────────┐  [qa 모드: QA_DONE]
                     └─ NO-GO ─▶ 보고 ─▶ STOPPED_NO_GO (대기)         │
                                  └─ 수정 지시·사전 승인 있음 ─▶ F    │
F 수정 분기: 목록(미검증) → 프로토콜 동결 → MAC 판정 → 결정 파일
  → NEEDS-USER(종속 단계만 보류) → I2P 구현 → 리뷰 루프(MAC-16)
  → 수정 PR 최종 head에서 G-REQA → G-MERGE → 1(버전 재도출)과 2(변경분 범위)로 재진입
3 컷: 버전 근거·노트 초안(GO 직후) → 버전·노트 승인(E2V-35, 위임이면 생략. 프로필 Overrides가 요구하면 묻는다) → release PR 작성(또는 bot PR 검증) → 노트 독립 리뷰(E2V-34) → G-CUT → G-MERGE
4 게시(되돌릴 수 없음): G-PUB 사전 assertion(tree·ancestry) → trigger(agent tag push 또는 bot PR merge) → pipeline → 채널 → release 객체
5 게시 후: 머지된 SHA의 기본 브랜치 CI → 공개 배포 채널에서 문서대로 clean install → 후속 PR → 정리 처분(E2V-45)
  → 보고 ─▶ RELEASED_VERIFIED | RELEASED_WITH_FOLLOWUPS | PARTIAL_PUBLISH
모든 단계 ─▶ BLOCKED(사용자 입력·자격증명·baseline 부족, 외부 의존) | NOT_APPLICABLE(0단계만)
```

- 단계는 다섯 개(0~5)이고 수정 분기 F는 조건부다. G-GO와 G-REQA는 게이트이지 단계가 아니다.
- 모드(E2V-02)가 멈춤 지점을 정한다. `analysis`는 1단계 뒤, `qa`는 G-GO 판정과 보고 뒤에 멈춘다. `release`만 3~5단계로 간다.
- 3단계 merge와 4단계 게시는 따로 판정한다. 단, bot이 release PR을 만들고 그 merge가 게시 trigger인 저장소에서는 게시 전에 적용되는 게이트(G-GO, 해당하면 G-REQA, G-CUT, bot PR의 G-MERGE)와 G-PUB의 trigger 전 assertion(§10)을 그 merge 전에 끝낸다(E2V-13). 그 merge가 되돌릴 수 없는 첫 단계다. G-PUB의 trigger 뒤 assertion과 G-POST는 merge 뒤에 끝내고, tag·release 객체는 bot이 만든 것을 관찰한다(§11).

## 2. 종착 상태

| 종착 | 진입 조건 | 보고에 꼭 들어갈 것 |
|---|---|---|
| `NOT_APPLICABLE` | 게시된 release, registry 패키지, release workflow가 모두 없음(E2V-03의 기계적 검사) | 검사 결과와 넘길 스킬 이름(배포 전용 서비스는 `isac-e2e-qa-to-fix` 또는 `isac-issue-to-pr`) |
| `ANALYSIS_DONE` | `analysis` 모드에서 G-VERSION 통과 | 변경 목록, 버전 근거 표, 버전 제안과 반론 결과 |
| `QA_DONE` | `qa` 모드에서 G-GO가 GO | GO 보고 전체 |
| `STOPPED_NO_GO` | NO-GO이고 수정 지시도 사전 승인도 없음(E2V-20). 모드와 관계없다 | NO-GO 보고. tag, release PR, 게시는 만들지 않는다 |
| `BLOCKED(<무엇>)` | 사용자 입력, 자격증명, materialize 불가 baseline, 외부 의존 때문에 다음 게이트를 판정할 수 없음 | 막힌 게이트, 필요한 것, 이미 끝난 산출물, 재개 지점 |
| `PARTIAL_PUBLISH(<채널>)` | 여러 채널 중 일부만 게시됨(E2V-40) | 채널별 상태(게시됨 / 제출만 됨 / 실패)와 재개 방법 |
| `RELEASED_WITH_FOLLOWUPS(<열린 PR·승인>)` | 게시와 게시 후 검증은 끝났고 후속 PR이나 승인이 남음(E2V-43) | 후속 항목마다 상태와 필요한 승인 |
| `RELEASED_VERIFIED` | G-POST 통과, 열린 후속 없음 | 최종 보고(E2V-44) |

## 3. 게이트와 종료 산출물

게이트는 ledger에 종료 산출물이 있어야 통과다. 산출물이 없으면 통과로 치지 않는다. 산출물의 모든 검증 기록은 실행한 SHA나 아티팩트, 명령, 범위를 단다(E2V-09). 어떤 게이트든 판정 전에 그 앞 게이트의 종료 산출물이 ledger에 있는지 먼저 확인한다. 재개 규칙은 SKILL.md `## 단계와 게이트`가 정한다. 게이트마다 어느 산출물이 증거인지는 ledger에 복사한 `ledger-checklist.md` 블록이 정한다.

| 게이트 | 통과 조건 | 종료 산출물 |
|---|---|---|
| G-INTAKE (0단계) | 모드와 권한 지도(행동·PR마다 근거 지시) 기록. 적용 가능성 판정. 저장소 하네스 파일과 프로파일의 내용을 읽었거나(pointer 목록만으로는 부족) "없음"으로 기록. unit마다 직전 release 확정(E2V-06). baseline 상태 = available / none / blocked(E2V-07). 후보 SHA 고정. 기억된 환경 사실 재확인과 대상 환경 probe 결과(E2V-08). 기준 브랜치의 열린 PR·진행 중인 변경을 조회해 ledger 머리에 적고, 후보 SHA와 겹치면 범위를 조정한다 | ledger 머리 |
| G-VERSION (1단계) | baseline 이후 모든 변경을 읽음(E2V-10). baseline과 후보의 표면 목록을 diff. breaking·mixed unit은 전부 읽음. 버전 제안은 잠정이고 반론을 거침(E2V-11, MAC-05 사소). baseline `none`이면 §5의 첫 release 산출물로 대신한다 | 변경 목록 + 버전 근거 표 |
| G-GO (2단계) | GO: 모든 lane이 ran / not_applicable / blocked 중 하나로 보고됨(게시 전 공개 문서 설치 lane 포함, §6.1), coverage table이 표면 목록 전체를 덮음, 모든 regression·new-bug 가설에 challenger 판정이 있음, 검증하지 못한 범위가 적힘(E2V-21). NO-GO: blocker가 하나 이상이고 각 blocker에 발견자 아닌 에이전트의 재현, 결함 판정, 개선 테스트 실패가 있음(E2V-19). 레인 목록은 GO와 같은 기준으로 채운다(각각 ran / not_applicable / blocked). | coverage table, finding 목록(finding마다 상태), 후보 아티팩트 설치 기록, GO/NO-GO 보고 |
| G-REQA (수정 분기) | 수정 PR 최종 head에서: baseline suite × head, 수정이 동작을 바꾼 표면의 A/B를 결정 파일의 목표 계약으로 판정, release와 같은 형태의 아티팩트를 공개 문서대로 clean 환경에 설치(I2P-28). baseline `none`이면 suite·A/B 대신 단일 아티팩트 방법(§5). 선언되지 않은 차이는 새 finding으로 F에 되돌림(E2V-28) | head SHA를 키로 한 re-QA 변경분 보고 |
| G-MERGE (run의 모든 PR) | 근거 지시가 있음(E2V-02). 그 head에서 리뷰 루프 종료(MAC-16). ruleset이 요구하는 모든 context가 정확히 그 head에 보고됨, "대기 중 없음"으로 대신하지 않음(E2V-30). 필수 리뷰는 정확히 그 head 기준으로 보고됐는지, 아니면 전역 pull-request-merge 가드가 허용하는 예외인지 가드의 판정을 기록한다. 실패는 E2V-31로 분류 | PR별 ledger 행(필수 리뷰 처리 열 포함) |
| G-CUT (3단계) | release PR을 만들기 전에 버전 근거 행이 ledger에 있음: 수정 분기를 거쳤으면 수정 merge 뒤 최종 commit 기준으로 재도출한 행(E2V-12), 아니면 1단계 행. release PR의 버전은 그 행과 같음. release PR diff = 직전 release PR의 모양 + 버전 변경(또는 bot PR 검증 완료, E2V-13). baseline `none`이면 §5의 첫 release 기준을 쓴다. drift는 설명됨(E2V-32). 독립 리뷰어가 release PR의 최종 head에서 그 주장(버전 일관성, changelog 링크, 버전 주장 대 interface 변경분)과 PR 본문을 포함한 공개 문구, 노트를 저장소 규칙에 대조해 게시 전에 리뷰함(E2V-34). head가 바뀌면 리뷰를 다시 한다. 버전·노트 승인은 E2V-35를 프로필 `## Overrides`까지 적용한 뒤 판단한다(위임이면 생략. 프로필 Overrides가 요구하면 묻는다): 요청이 버전 결정과 release를 끝까지 명시적으로 위임했고 Overrides가 질문을 요구하지 않으면 묻지 않고 버전 근거와 노트를 최종 보고에 넣는다. 위임이어도 Overrides가 요구하면 그 Overrides가 정한 버전 질문을 버전 제안과 근거를 붙여 한 번 묻고, 답이 올 때까지 3단계와 그 뒤 단계만 멈춘다. 이 경우 G-CUT은 버전 답 기록(NEEDS-USER 표)이 있어야 통과한다. 위임이 아니면 `release` 모드의 GO 직후 버전과 노트를 한 번에 묻고 답을 기록한다. NO-GO 보고에는 이 질문을 넣지 않는다 | 버전 근거 행(수정 분기를 거쳤으면 E2V-12 재도출 행) + release PR 행 + release PR 최종 head SHA를 키로 한 독립 리뷰 기록(노트 포함) + 승인 기록(위임이면 위임 근거 지시. Overrides가 질문을 요구하면 버전 답 기록도) |
| G-PUB (4단계) | trigger 전: 게시될 commit의 tree == 마지막으로 게이트를 모두 통과한 head의 tree, QA한 후보와 그 commit 사이 commit이 정확히 이 run의 수정·release PR뿐(아니면 범위를 좁혀 재검증). trigger 뒤: tag 이름·대상 commit·tree(agent가 만든 tag면 push 전), 프로젝트가 선언한 서명 방식이 있으면 서명(없으면 `not_applicable`), pipeline, 채널별 게시, release 객체를 각각 별도 assertion으로 확인. bot 소유 unit은 tag·release 객체를 만들지 않고 관찰·검증만 한다(E2V-13, E2V-37, E2V-38, E2V-39) | 사전 assertion 행 + tag / pipeline / 채널 / release 증거 행 |
| G-POST (5단계) | merge된 SHA마다 기본 브랜치 CI를 관찰하고 분류(E2V-41). unit이 공개 문서로 안내하는 배포 채널(registry, release asset 등)에서 문서대로 clean 환경 설치와 release 내용 기반 smoke. asset 설치면 내려받은 파일의 digest가 게시된 asset과 같음을 확인(E2V-42). 공백 분류. 후속은 자기 권한으로 열림(E2V-43) | 게시 후 보고 |

## 4. 되돌림과 재진입

- **G-REQA 실패:** 선언되지 않은 차이나 계약 위반은 새 finding이다. F의 목록 단계로 돌아가고, 결정 파일에 행을 더한 뒤 같은 절차를 다시 탄다.
- **수정 PR merge 뒤, 3단계의 어떤 행동 전에:** 1단계로 돌아가 최종 commit의 baseline 대비 변경으로 버전을 다시 도출한다(E2V-12). 2단계는 수정이 건드린 표면과 기대 변경분만 다시 돈다(§8). 나머지 lane 기록은 SHA가 바뀌었으므로 "이전 SHA에서 실행"으로 남기고 G-PUB의 ancestry 검사로 연결한다. 수정 분기를 거친 run의 재검증 GO는 G-REQA 통과와 재도출된 G-VERSION이 ledger에 있는 시점이다. 프로필 Overrides가 요구하는 버전 질문은 이 시점에만 보낸다.
- **head 변경:** 모든 PR은 head가 바뀌면 그 PR의 G-MERGE를 처음부터 다시 판정한다. 이전 head의 context와 리뷰는 세지 않는다.
- **NEEDS-USER 답:** 보류했던 종속 단계만 그 지점에서 재개한다. 답 뒤에 사용자가 다시 질문하면 그 항목은 다시 열린 것이다. 답하고 종속 단계를 다시 보류한다(E2V-24).
- **BLOCKED 해제:** 빠진 것이 오면 막힌 게이트부터 다시 판정한다. 이미 끝난 산출물은 SHA가 같을 때만 재사용한다.
- **G-PUB 실패:** 그 단계에서 멈춘다. 다음 게시 단계를 이어서 실행하지 않는다(E2V-38). ancestry 불일치면 추가 commit만큼 범위를 좁혀 재검증한 뒤 G-PUB을 다시 판정한다.
- **NO-GO 뒤 수정 지시:** `STOPPED_NO_GO`에서 F로 들어간다. 지시가 수정만 허가하고 release는 허가하지 않으면 F 뒤 재진입한 2단계 GO에서 다시 멈추고 보고한다.

## 5. baseline 삼상태 (E2V-06, E2V-07)

baseline은 unit마다 releases API나 registry가 보여 주는 가장 최근의 non-draft, non-prerelease release다. tag 패턴은 후보를 거르는 데만 쓴다. 패턴이 바뀐 이력이 있으면 패턴 하나로 찾다가 "첫 release"로 잘못 판단한다.

materialize 순서: 게시된 아티팩트 > release asset > tag에서 rebuild(drift를 적는다). 프로파일이 이유와 함께 순서를 바꿀 수 있다.

| 상태 | 뜻 | lane과 QA |
|---|---|---|
| `available` | baseline이 있고 materialize됨 | 모든 lane을 돈다. A/B 차등 QA와 old suite × 후보를 실행한다 |
| `none` | 이 unit의 직전 release가 없음(첫 release) | A/B와 old suite × 후보는 2단계와 G-REQA 모두에서 `not_applicable`. QA는 단일 아티팩트 "새 표면" 방법(§6.4 끝)으로 바꾼다. `regression` 분류는 쓰지 않고 `new-bug`로 적는다. 다른 게이트의 대체 산출물은 아래 표 |
| `blocked` | baseline은 있지만 materialize 불가(yank, rebuild drift, registry 소실 등) | `isac-decision-brief` 형식으로 사용자에게 묻는다. 답이 올 때까지 `BLOCKED(baseline)`. 자동으로 GO하거나 `none` 방법으로 낮추지 않는다 |

baseline `none`일 때 baseline을 기준으로 삼는 게이트는 다음 산출물로 대신한다. 저장소 선언으로 정해지지 않는 선택만 묻는다(E2V-05와 같은 원칙).

| 게이트 | `available`일 때 | `none`일 때 대신하는 것 |
|---|---|---|
| G-VERSION | baseline 이후 변경 목록, baseline 대비 표면 diff | 후보의 공개 표면 목록 전체(diff 대신), 첫 버전의 근거(버전 파일의 현재 값, 저장소가 선언한 버전 정책). 근거가 없거나 서로 다르면 묻는다 |
| G-REQA | baseline suite × head, 수정이 바꾼 표면의 A/B | 수정이 바꾼 표면을 단일 아티팩트 방법으로 결정 파일의 목표 계약에 대조. suite·A/B 행은 `not_applicable` |
| G-CUT | 직전 release PR의 모양 + 버전 변경 | 저장소가 선언한 release 절차·workflow·버전 파일 목록에서 도출한 모양. 다른 unit의 release가 있으면 그 모양을 참고한다 |
| G-PUB tag | 직전 release의 tag 형식과 서명 방식(서명하지 않았으면 서명 `not_applicable`) | release workflow의 tag trigger 패턴, 저장소 문서, 다른 unit의 tag 형식. 서명은 저장소가 선언한 정책을 따르고, 선언이 없으면 `not_applicable`. 형식이 그래도 정해지지 않으면 묻는다 |

## 6. 차등 QA 방법 (2단계)

### 6.1 lane (E2V-15)

각 lane은 ran / not_applicable / blocked 중 하나로 ledger에 기록한다. suite가 green이어도 그것만으로 GO가 아니다.

1. 후보 전체 suite.
2. 후보 SHA에서 필수 CI 완료(watcher 완결성은 E2V-30).
3. baseline suite × 후보 코드. 실패마다 changelog의 의도된 변경과 대조한다. 정확한 표면 목록이나 개수를 고정하는 assert는 추가 변경에도 깨진다. 실패한 assert가 테스트를 일찍 중단시키면 그 뒤에서 확인됐어야 할 것을 적고 다른 방법으로 덮는다(E2V-16).
4. CI가 실제로 실행하는 테스트 집합과 저장소에 있는 테스트 집합의 diff.
5. A/B 탐색 QA(§6.3~§6.6). 새 테스트 × 이전 코드(old-fail/new-pass)는 I2P-25가 소유한다.
6. 게시 전 공개 문서 설치: 후보 SHA로 release와 같은 형태의 아티팩트를 만들고, 공개 설치 문서를 글자 그대로 따라 clean 환경에 설치한 뒤 release의 핵심 변경으로 smoke한다(I2P-28). 기록은 아티팩트 digest와 후보 SHA를 키로 한다. 문서와 다르게 해야 설치되면 finding이다. 수정 분기를 거치면 G-REQA가 최종 head에서 같은 설치를 다시 한다. 설치 문서가 나열한 실행 의존성이 그 환경에 실재하는지 확인한다.

### 6.2 표면 목록과 영역 (E2V-14)

- 표면 목록: baseline과 후보 각각에서 공개 진입점(도구·명령·API·설정·설치 경로 등)을 실제로 나열한다. 고정 테스트 케이스 목록에서 가져오지 않는다.
- 폭: 모든 공개 표면을 smoke 수준으로 덮는다. 깊이: 변경 집합과 위험이 정한다.
- 영역 = 프로파일의 영역 seed 목록 ∩ 요청의 폭. 프로파일이 없으면 표면 목록을 진입점 기준으로 묶어 만든다.
- 시나리오는 영역 담당 에이전트가 이번 run의 표면 × 변경 집합에서 설계한다: 정상 경로, 경계값, 잘못된 입력, 상호작용.
- 도달할 수 없는 대상 환경은 건너뛰지 않고 "검증하지 못한 범위"에 넣는다(E2V-08).

### 6.3 QA brief 필드

영역 에이전트 하나에 brief 하나. brief는 파일로 먼저 쓰고 경로를 넘긴다. 구현·리뷰 handoff(§7)도 같은 "읽을 스킬" 필드를 둔다.

| 필드 | 내용 |
|---|---|
| 목표 | 이 영역에서 baseline과 후보의 동작 차이를 찾고 분류한다. 수정하지 않는다 |
| baseline / 후보 | 두 아티팩트의 식별자(digest, SHA)와 materialize 방법, baseline 상태 |
| 쓰기 경계 | 저장소, 원격, 공유 환경에 쓰지 않는다. scratch 경로와 자기 컨테이너만 쓴다 |
| 읽을 스킬 | 역할에 맞게 고른 스킬 이름과 rule ID 또는 절 제목. 탐색 에이전트: `issue-validation`의 "Build a minimal, representative reproducer", `isac-live-qa` LQA-20, LQA-21. challenger: `isac-multi-agent-consensus` MAC-05, MAC-09. 절차는 brief에 옮겨 쓰지 않는다 |
| 환경 한계 | 프로파일의 env-limitation 목록과 대상 환경 probe 결과. 이 목록에 있는 현상은 버그가 아니라 `env-limitation`으로 적는다. 컨테이너 상한(`defaults.md`) |
| 방법 단계 | §6.4 절차. changelog의 의도된 변경 목록을 주되 "검증할 주장"으로 준다 |
| 닫힌 어휘 | ok / regression / new-bug / pre-existing-bug / env-limitation / not-testable. 다른 말을 만들지 않는다 |
| coverage table | §6.6 형식으로 반환. 시나리오마다 행 하나 |

regression suite lane은 탐색 에이전트가 아닌 다른 에이전트가 맡는다.

### 6.4 A/B 절차

1. 같은 시나리오를 같은 입력과 순서로 baseline과 후보에서 각각 실행한다.
2. 결과를 diff한다. 차이가 없으면 `ok`. 두 쪽 모두 같은 결함이면 `pre-existing-bug`로 표시한다.
3. 차이는 최소 두 번 재현하고 최소화한다(`issue-validation`의 "Build a minimal, representative reproducer"). 출시 tag와 main 사이의 출처 추적이 필요하면 같은 스킬의 "Compare three code states and trace provenance"를 쓴다.
4. 차이가 changelog의 의도된 변경이면 그 주장 자체가 맞는지 확인한다. 맞으면 개선 테스트(§6.5)로, 틀리면 finding으로.
5. 의도되지 않은 차이는 개선 테스트를 먼저 거친다. 통과하면 KEEP 후보이고 되돌리지 않는다(E2V-18). 실패하면 `regression` 가설이다.
6. 새 표면(baseline에 없음)과 baseline `none`인 unit은 단일 아티팩트 방법을 쓴다: 정상 경로, 경계값, 잘못된 입력, 상호작용을 공개 문서와 계약으로 판정하고, 결함은 `new-bug`.

### 6.5 오라클 규칙

- 2단계 A/B: baseline 동작 + 검증된 의도 변경이 기준이다. baseline과 다르다는 것만으로는 결함이 아니다.
- 개선 테스트: 차이가 (a) 결함을 고쳤거나 (b) 더 직관적이거나 (c) 더 표준적이면 개선이다. 하나라도 성립하면 KEEP.
- 새 표면과 baseline `none`: 공개 문서, 도움말, schema, 프로파일의 영역별 오라클 힌트가 기준이다.
- G-REQA: 결정 파일의 목표 계약이 기준이다. 이전 release가 아니다.
- 오라클 자체가 틀렸다는 증거가 나오면 판정을 바꾸지 말고 finding으로 올려 MAC 판정에 넘긴다.

### 6.6 coverage table

분모는 §6.2의 표면 목록 전체다(LQA-20). 행이 빠진 표면은 "검증하지 못한 범위"에 사유와 함께 적는다.

| 표면 | 영역 | 깊이(smoke/depth) | 시나리오 | baseline 결과 | 후보 결과 | 분류 | finding | 확인자 |
|---|---|---|---|---|---|---|---|---|

### 6.7 가설에서 GO/NO-GO까지

1. QA finding은 가설이다. 목록에 "미검증"으로 넣는다.
2. 영역마다 첫 결과(R1)가 오는 대로 그 묶음의 challenger(R2)를 바로 보낸다. 모든 영역을 기다리지 않는다.
3. NO-GO 후보 blocker마다 발견자가 아닌 에이전트가 재현하고 결함 판정을 낸다(MAC-05 사소). 개선 테스트에 실패해야 blocker다(E2V-19).
4. 그 밖의 finding은 "미검증"으로 보고한다. 전면 합의는 사용자가 범위를 지시한 뒤에 한다.
5. G-GO 판정은 §3 표의 조건으로 main이 한다(MAC-02). 보고 형식은 `ledger-and-report.md`의 GO/NO-GO 템플릿(E2V-22).

## 7. 수정 분기 F (E2V-23~E2V-29, E2V-47)

1. **목록:** 2단계 finding 전체(이미 있던 버그 포함)를 "미검증"으로 모은다.
2. **프로토콜 동결:** 조사 전에 판정 질문 하나, 사용자의 강한 규칙(개선은 되돌리지 않음 등), 닫힌 판정 집합 FIX / KEEP / DOCS / NOT-A-PROBLEM / UPSTREAM / NEEDS-USER를 파일로 고정한다. 판정 집합 밖의 결론은 없다. 증거 칸은 ledger-checklist F 블록, brief는 briefs.md의 조사자·challenger 틀을 쓴다.
3. **MAC 판정:** finding마다 판정을 `isac-multi-agent-consensus`로 낸다. 구성과 반박 2라운드의 응답자는 E2V-46이 정한다. ledger-checklist F 블록은 그 증거를 담는 칸일 뿐이다. 재반론 뒤에도 갈리는 기술 쟁점만 조사에 참여하지 않은 arbiter가 판정한다(MAC-11). 절차상 흠결인 arbiter 판정은 이전 판정으로 되돌리지 않고 같은 구성으로 다시 판정한다(E2V-46). 판정 단계에서 나온 관찰, 증거, 검증 상태는 결정 파일을 확정하기 전에 기존 finding 표의 해당 행에 반영한다. 새 결함이면 finding 행을 더한다.
4. **결정 파일:** 구현자가 쓰는 유일한 계약이다. 섹션과 작성자는 E2V-23이 정하고, briefs.md의 결정 작성자 틀은 그것을 옮긴 양식이다. 작성자는 메인이 아니다(E2V-23). 규약에는 반환 지점 표, 유지할 동작 pin 목록 등을 빠짐없이 적는다. 저장소 전체의 client가 보는 계약을 바꾸는 FIX도 사용자 기준(고쳐짐·더 직관적·표준)에 맞으면 합의로 확정한다. 그런 FIX는 동작 변경 목록에 넣고 release 노트와 보고에 동작 변경으로 따로 적는다(E2V-47). FIX 행마다 적용 범위(같은 유형 전체 vs 개별 인스턴스)의 판정을 규약에 기록한다. 새 상한·방어 코드는 실행된 경계 측정과 트리거 원인 귀속을 근거로 규약에 적고, 근거가 없으면 NEEDS-USER로 올린다.
5. **NEEDS-USER:** 알게 되는 즉시 사용자에게 보내고 종속 단계만 보류한다(E2V-24). 나머지 slice는 계속한다. 사용자 기준 안에서 이미 정해진 항목(닫힌 판정 집합의 FIX·DOCS, E2V-47 합의로 확정된 계약 변경)은 NEEDS-USER에 올리지 않는다. 근거 없는 새 상한·방어 코드(4번)와 사용자 기준 밖의 제품 결정(MAC-12)은 계속 NEEDS-USER로 올린다.
6. **구현:** `isac-issue-to-pr`가 한 PR로 구현한다. FIX 항목은 모두 테스트를 동반한다. 구현 brief는 briefs.md의 구현자 틀을 쓴다. 구현 brief에 프로파일의 환경 능력 사실을 넣고, suite 실패는 제품 코드를 고치기 전에 테스트 산출물인지 제품 결함인지 진단 증거로 분류한다(E2V-25). gate는 CI가 쓰는 환경에서 돈다(E2V-26). old-fail/new-pass는 최종 head의 최종 테스트 집합에서 돌거나 돌지 않은 테스트를 나열한다(E2V-27). slice와 worktree·브랜치의 대응은 ledger-checklist F 블록의 표로 남긴다(E2V-23).
7. **리뷰 루프:** MAC-16의 종료 조건까지. 리뷰어 brief는 briefs.md의 리뷰어 틀을 쓴다(리뷰 대상은 commit된 SHA). 리뷰어 brief는 확인할 사실과 모든 수작업 편집을 공개하고 판정을 미리 말하지 않는다(E2V-29). 선택 finding은 `receiving-code-review`로 평가한다.
8. **G-REQA**(§8) → **G-MERGE** → §4의 재진입.

## 8. re-QA 범위 (G-REQA)

- 시점: 수정 PR의 최종 head, merge 전. merge 뒤 release 준비를 바로 시작하지 않는다.
- 범위: baseline suite × head 전체, 그리고 수정이 동작을 바꾼 표면(결정 파일의 FIX·DOCS 행이 가리키는 표면)의 A/B. baseline `none`이면 §5 대체 표를 따른다.
- 같은 시나리오 재실행과 새 탐색은 분리해 기록한다. 같은 시나리오는 2단계 스크립트를 그대로 다시 쓴다. 탐색 상한은 `defaults.md`.
- 설치 경로: §6.1의 6번 lane을 최종 head에서 다시 한다(I2P-28).
- 판정: 결정 파일의 목표 계약 대비. 기대 변경분 외의 차이는 새 finding.
- 각 lane의 artifact 디렉터리 이름이나 environment.json에 대상 head SHA를 기록한다(ledger 행과 함께).

## 9. 컷 (3단계)

- 0단계 ledger의 `저장소 하네스·프로필` 행(찾은 릴리스·노트 스킬 또는 "없음")을 이 절차의 첫 근거로 적고, 행이 없거나 비었으면 0단계 경로(SKILL.md `## 0단계: 프로젝트 훅`, E2V-04)를 다시 찾는다. release 절차는 이 단계에 들어갈 때 읽는다: 저장소 release·노트 스킬과 하네스 문서(E2V-04) > 프로파일 > 직전 release의 PR, commit, tag, CI·게시 workflow 파일에서 도출(E2V-05). 도출한 절차는 ledger에 적고 모호할 때만 묻는다.
- release PR의 파일 집합과 diff 모양은 직전 release PR + 버전 변경과 같아야 한다. 그 밖의 차이는 drift로 설명한다. lockfile metadata가 base와 다르면 원인 도구와 이유를 적고, 수작업 정규화는 리뷰어에게 수작업 편집으로 공개한다(E2V-32).
- bot이 버전을 올리는 unit은 버전 파일과 tag를 직접 고치지 않는다. bot PR을 버전 근거와 대조하고, 필수 context가 bot PR head에 실제로 보고됐는지 확인한다(없으면 같은 tree에서 gate를 돌린다). 전역 머지 가드의 admin bypass 기본값은 bot 작성 PR에 적용되지 않는다(E2V-13).
- 노트는 저장소 규칙을 따르고 독립 리뷰어가 그 규칙과 changelog에 대조해 리뷰한다(E2V-34). 직전 노트는 문체 참고일 뿐이다.
- 공개 문구의 모든 주장은 코드나 SHA를 단 실행 명령으로 확인한다(E2V-33).

## 10. exact-SHA·ancestry 검사 (G-PUB, E2V-37)

trigger(tag push 또는 bot PR merge) 전에 확인하는 사전 assertion이다.

1. 마지막으로 모든 게이트를 통과한 head의 tree hash와 게시될 commit(agent tag의 대상, 또는 bot PR merge가 만들 commit의 tree = bot PR head tree)의 tree hash를 계산해 비교한다. branch 보호의 "strict" 설정으로 추론하지 않는다. bypass 권한자는 strict를 건너뛸 수 있다.
2. QA한 후보 SHA부터 게시될 commit까지의 commit을 나열한다. 이 run이 merge한 수정·release PR의 commit만 있어야 한다. bot PR이면 그 base가 현재 기본 브랜치 head인지도 확인한다. 나열한 커밋 목록을 ledger에 그대로 적는다.
3. 다른 commit이 끼어 있으면(외부 PR merge 등) 그 commit이 건드린 표면만 범위를 좁혀 재검증하고 G-PUB을 다시 판정한다.

## 11. 게시 단계 순서 (4단계, E2V-38~E2V-40)

unit마다 tag, 게시 trigger, release 객체를 누가 만드는지 먼저 정한다(저장소 하네스, 프로파일 `## Release procedure`, release workflow에서 발견). 각 단계는 별도 명령이고, 실패하면 다음 단계를 실행하지 않는다. `&&`, `;`, `|`로 검증과 게시를 한 줄에 묶거나 종료 상태를 숨기지 않는다.

**agent 소유 unit:**

1. §10 사전 assertion.
2. 직전 release의 형식으로 tag를 만든다. 저장소가 서명 정책을 선언했으면 그 방식으로 서명한다(baseline `none`이면 §5 대체 표).
3. push 전에 tag를 검증한다: tag 이름과 대상 commit, 대상 tree = §10의 tree. 서명 정책이 있으면 서명도 검증하고, 없으면 ledger에 서명을 `not_applicable`로 적는다.
4. tag를 push한다.
5. 게시 pipeline을 끝까지 관찰한다.
6. 배포 파일과 채널마다 공개 게시를 확인한다: draft가 아니고, "제출됨"이 아니라 "게시됨".
7. 검증된 tag를 대상으로 release 객체를 만든다. pipeline이 만들면 만들지 않고 7번 대신 관찰·검증한다.

**bot 소유 unit (E2V-13):**

1. 게시 전에 적용되는 게이트(G-GO, 해당하면 G-REQA, G-CUT, bot PR의 G-MERGE)와 §10의 trigger 전 assertion을 bot PR head에 대해 bot PR merge 전에 끝낸다. G-PUB의 trigger 뒤 assertion(아래 3~6번)과 G-POST는 merge 뒤에 한다.
2. bot PR을 G-MERGE로 한 번 merge한다. 이것이 게시 trigger다.
3. 게시 pipeline을 끝까지 관찰한다.
4. bot이 만든 tag를 검증한다: tag 이름과 대상 commit, 대상 tree = §10의 tree. 서명 정책이 있으면 서명도 검증하고, 없으면 서명을 `not_applicable`로 적는다.
5. 배포 파일과 채널마다 공개 게시를 확인한다(agent 소유 6번과 같다).
6. bot이 만든 release 객체가 검증된 tag를 가리키고 draft가 아닌지 확인한다. tag와 release 객체를 직접 만들거나 고치지 않는다.

두 경우 모두 한 채널이 실패해도 다른 채널은 막지 않는다. 끝에서 `PARTIAL_PUBLISH`로 보고한다.

## 12. 게시 후 검증 (5단계)

- release 체인에서 merge된 SHA마다 기본 브랜치 CI를 관찰한다. 실패는 E2V-31로 분류한다(로그 서명 확인, 즉시 재실행 최대 1회, 필수인지 확인, 이후 상한 있는 간격 재시도, bypass 금지).
- unit이 공개 문서로 안내하는 배포 채널(registry, release asset 등)에서 clean 환경에 공개 문서를 글자 그대로 따라 설치한다. release asset이면 내려받은 파일의 digest를 게시된 asset과 대조한다. release의 핵심 변경과 수정으로 smoke한다. 우회하기 전에 실패를 기록하고 최종 사용자 문서 공백인지 환경 전용 산출물인지 분류한다(E2V-42).
- 문서·결함 후속은 `isac-issue-to-pr`로 별도 PR을 만들고, 그 merge는 따로 권한을 받는다(E2V-43).
- 정리: run이 만든 자원은 E2V-45대로 cleanup ledger에 적고 처분한다(종류, 삭제 신호, 삭제 전 확인은 전역 temporary-resource-cleanup 가드). 워크스테이션 사실은 프로필이 아니라 memory에 남긴다(E2V-45).

## 13. 매 run 도출 vs 스킬 고정

| 스킬에 고정 | 매 run 도출(테스트 케이스로 저장하지 않음) |
|---|---|
| 단계·게이트 골격과 종착 상태 | 요청에서 읽은 모드와 권한 지도 |
| baseline = unit별 가장 최근 게시 release, materialize 순서, 삼상태 | 어떤 아티팩트·recipe를 쓸지, drift 설명 |
| 버전 근거 방법(interface 변경분 + breaking unit 전문 읽기 + 리뷰어) | 표면 목록과 버전 제안 |
| lane: 후보 suite, CI 완결성, baseline suite × 후보, CI-저장소 테스트 diff, A/B 탐색 QA | 명령(프로파일·발견), 영역(프로파일 seed ∩ 요청 폭), 시나리오(영역 에이전트가 표면 × 변경 집합에서 설계) |
| 닫힌 QA 분류 + 표면 목록 기준 coverage table | finding, coverage 행 |
| 개선 테스트(고쳐짐 / 더 직관적 / 더 표준적)와 KEEP | 어떤 차이가 개선인지 |
| 수정 판정 어휘 + 결정 파일 섹션 | 판정, 규약, slice, NEEDS-USER 항목 |
| re-QA 범위 규칙 | 건드린 표면, 기대 변경분 |
| merge 완결성, flake 프로토콜, exact-SHA·ancestry 불변식, 게시 단계 규율 | 필수 context 목록(live 조회), flake 서명, 게시 단계(저장소·프로파일·도출) |
| 게시 후 방법(clean 환경, 문서 글자 그대로, release 내용 기반 smoke, 공백 분류) | 설치 채널, 이미지, 핵심 변경·수정에서 만든 smoke 시나리오 |
| 보고 구조 | 내용, 타임라인 |

## 14. 출처 세션과 다른 점

이 스킬은 출처 세션을 그대로 재연하지 않는다. 설명할 때 이 차이를 보여 준다.

- **더 엄격한 곳:** 수정 뒤 re-QA(G-REQA), 게시 전 문서대로 설치, exact-SHA·ancestry 검사, watcher 완결성, merge 뒤 기본 브랜치 CI 관찰, 저장소 규칙 대비 노트 독립 리뷰, 검증과 게시를 한 명령으로 묶기 금지, 수정 뒤 버전 재도출, NO-GO 전 발견자 아닌 에이전트의 blocker 확인.
- **뺀 것:** hunk 판정기와 그 threshold, 판정 사전값, 상시 arbiter(합의 실패 때만 arbiter), lockfile을 말없이 손으로 고치기.

## 15. 프로젝트 프로파일 스키마 (작성자용)

경로는 `references/projects/<owner>__<repo>.md`다. 공개 저장소만 이 스킬에 둔다. 비공개 저장소는 같은 heading으로 자기 저장소 하네스에 두고, 그 이름을 이 스킬이나 다른 프로파일에 쓰지 않는다.

작성 원칙:
- 프로파일은 선택이다. 없으면 run은 발견(discovery)으로 돌고 발견한 것을 ledger에 적는다. 프로파일은 같은 저장소에서 두 번째 run부터 쓸모가 생길 때 만든다.
- 저장소의 release·노트 스킬과 하네스 문서가 프로파일보다 우선한다(E2V-04). 프로파일은 그것을 가리키고, 없는 것만 보탠다.
- 칸마다 pointer(파일과 heading) 또는 다시 도출하는 조회를 쓴다. 개수, 버전, PR 번호, run id, 분 단위 시간 같은 구체 값은 `## Cases`에 날짜가 붙은 증거로만 쓴다. 필수 context 이름 목록 대신 그 목록을 얻는 조회를 쓰는 식이다.
- 기본값(`defaults.md`)을 좁힐 수는 있지만 `[U]` 규칙과 전역 가드를 완화할 수는 없다. 규모를 낮추는 `scale` 같은 칸은 없다.
- 시나리오와 테스트 케이스를 쓰지 않는다. 영역 seed와 오라클 힌트까지만 쓴다.
- heading은 아래 순서 그대로 둔다. 해당 없는 칸은 "없음"과 이유를 적는다.

```text
# <owner>/<repo> release profile
## Sources of truth
## Releasable units
## Release procedure
## Baseline recipe
## Verification environment
## Surface areas and oracles
## CI and merge facts
## Install contract
## Release notes
## Overrides
## Cases
```

| heading | 쓰는 것 | 쓰지 않는 것 |
|---|---|---|
| Sources of truth | 먼저 읽을 저장소 문서·스킬의 pointer(heading까지) | 그 문서 내용의 복사 |
| Releasable units | unit마다: 이름, 직전 release 조회(releases·registry API), 과거 tag 패턴(필터로만), 버전 파일, 버전 올리는 주체(`agent` / `bot <이름>` / `human`), `bot_pr_ci`(`runs` / `absent`), 버전 신호 힌트(예: 1.0 이전 단계에서 어떤 변경을 minor로 보는가) | 현재 버전 값 |
| Release procedure | 우선순위 pointer(저장소 스킬 > 이 칸), 직전 release PR 검색 키, 스크립트·일관성 검사, lockfile 도구와 drift 정책, tag 형식과 서명 확인, 게시 trigger와 workflow 파일, 채널별 "게시됨" 조회, release 객체 단계. 저장소에 아직 없는 절차를 여기 복사했으면 `INTERIM` 표시와 제거 조건(저장소 하네스가 흡수하면 삭제) | 명령 출력, 과거 tag 이름 |
| Baseline recipe | materialize 순서를 바꾸는 이유(예: 테스트가 이미지에 구워져 rebuild가 필요), 변형별 재현 가능성 | 특정 baseline digest |
| Verification environment | 표준 gate 환경과 명령 pointer, 코드 변경 뒤 rebuild 규칙, `env-limitation`으로 분류할 환경 한계, 컨테이너 상한 값, intake 질문(예: 실제 대상 세션에 닿을 수 있는가) | 워크스테이션 사실(호스트 OS, VM 크기, 로컬 경로, 주소) — memory로 |
| Surface areas and oracles | 영역 seed 목록: 영역마다 진입점과 오라클 힌트 | 시나리오, 기대 출력 |
| CI and merge facts | 필수 context 조회, 외부·늦게 붙는 context, 자동 승인자와 그 의미, strict 최신화 여부, 알려진 flake 서명과 정책, 소요 시간 조회 | context 이름 목록, run id, 측정 시간 |
| Install contract | 공개 설치 문서 pointer, clean 이미지, 최종 사용자 경로와 환경 전용 경로를 가르는 힌트 | 설치 로그 |
| Release notes | 저장소 노트 규칙·스킬 pointer. 직전 노트는 문체 참고뿐이라는 표시 | 노트 템플릿 복사 |
| Overrides | E2V rule ID별로 좁히는 내용과 이유 | 규칙 완화 |
| Cases | 프로젝트 케이스(`CASE-YYYYMMDD-slug`, `isac-skill-correction`의 cases 형식). 구체 값은 여기에만 | 사용자 발화 원문 |
