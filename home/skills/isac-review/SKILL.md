---
name: isac-review
description: Use when reviewing a GitHub pull request as the reviewer, including an independent pre-merge review gate. Understand the change, trace blast radius and severity, verify it really fixes the claimed or linked problem, check regression, performance, security, and structure, then give an explicit verdict as an English GitHub review whose event matches it (APPROVE, REQUEST_CHANGES, or COMMENT). Also covers auditing stale or external PRs that may already be on main. Triggers include "PR 리뷰해", "이 PR 검수해", "PR도 확인만 해봐", "리뷰해서 코멘트 남겨", "오래된 PR 정리", "이미 반영된 PR 닫아". Not for responding to review feedback on your own PR (receiving-code-review) or implementing an issue fix (isac-fix).
---

# GitHub PR Review

리뷰어 쪽 작업이다. PR을 현재 head 기준으로 이해하고, 실제로 문제를 해결하는지와 프로젝트에 주는 영향을 판정하고, 판정을 영어 리뷰 코멘트로 남긴다. 외부·오래된 PR이 이미 main에 반영됐는지 감사하는 변형을 포함한다.

## 경계

- 이 스킬이 소유: PR 판정 절차, 리뷰 차원, PR 판정에 붙는 필드, 리뷰 코멘트 내용, 판정별 리뷰 이벤트(APPROVE / REQUEST_CHANGES / COMMENT), 재리뷰에서 PR 고유 확인 항목, 외부·오래된 PR 감사.
- 재현·claim 판정·수정 출처(fix provenance)는 `issue-validation`, 원인 체인 도출은 `five-whys-root-cause-analysis`, 이슈 처리 순서는 `isac-triage`가 소유한다. 여기서는 호출만 한다.
- 판정 어휘(`GREEN`/`BLOCKING`, P0–P3 척도, `PR-ready`), GREEN까지의 수정 → 재리뷰 루프, 병렬 수정에서 메인이 리뷰어를 맡고 finding을 owner에게 돌려보내는 역할, 리뷰어 구성 규모 게이트는 `isac-consensus`가 소유한다.
- 게시 모드 판단, 영어 문체·공개 위생, 기존 코멘트 수정 vs 새 코멘트, 승인 초안 대조, 게시 주체, 라벨 조회·생성 메커닉, 자기 산출물 추적과 "제거 요청은 close"는 `isac-publish`가 소유한다.
- 머지 여부를 실행마다 확인하는 일과 머지 직전 변경 범위(테스트 전용 vs 런타임) 보고는 `isac-fix`가 소유한다. 그 스킬이 머지 전 독립 리뷰 게이트로 이 스킬을 호출한다.
- 받은 리뷰에 대응하는 일은 `receiving-code-review`와 전역 `pull-request-review-handling`이 소유한다. `runbear-bot` 요청·대기·head 무효화는 전역 `pull-request-review-guard`, 머지·관리자 우회·브랜치 삭제는 전역 `pull-request-merge-authorization`과 `pull-request-merge`가 소유한다.
- 배포 환경에서만 확인할 수 있는 주장은 `isac-live-qa`를 참조한다. 사용자에게 선택을 물을 때는 `isac-brief` 형식을 쓴다.

## 0. 프로젝트 훅

`gh repo view --json nameWithOwner,visibility`로 대상을 확인한다. 이 스킬의 `references/projects/<owner>__<repo>.md`가 있으면 먼저 읽는다(공개 저장소만 여기 둔다). 비공개 저장소의 프로젝트 사실은 그 저장소 자체 지침(AGENTS.md, `.agents/skills`)에 있다. 프로젝트 문서는 기본값을 좁히거나 구체화할 뿐, `[U]` 규칙과 전역 가드를 완화하지 못한다. 저장소의 스킬, AGENTS, 컨벤션 문서 중 관련된 것도 리뷰 전에 읽는다.

## 1. 모드와 권한

- **PRR-01** [U] 기본은 읽기 전용 분석이다. 산출물은 판정과 근거가 든 GitHub 리뷰 하나이고, 리뷰 이벤트가 판정을 나타낸다(PRR-25). 게시할지 초안으로 둘지는 전역 `task-intent-boundary`와 `isac-publish`의 게시 모드 규칙을 따른다.
- **PRR-02** [U] 검증 지시는 쓰기 권한이 아니다. "확인만"인 패스에서 GitHub 쓰기는 PRR-01로 승인된 리뷰뿐이다. 수정 push, close, merge는 사용자가 그 실행에서 따로 지시했을 때만 한다. 리뷰 판정이 머지를 트리거하지 않는다.
- **PRR-03** [U] 승인된 수정은 그 PR 브랜치에 push한다(대체 PR을 새로 만들지 않는다). 승인된 범위를 넘으면 전역 `application-code-change-approval`에 따라 다시 승인받는다.
- **PRR-04** 판정 리뷰어와 재현·감사 실행자의 분리, 격리 실행, 구성 규모는 `isac-consensus`를 따른다. PR 리뷰에서 추가로, 재현·감사는 대상 저장소와 PR 브랜치에 쓰지 않는다(승인된 수정 push는 PRR-03).

## 2. 대상 고정과 읽기

- **PRR-05** [U] 리뷰 대상은 PR 설명·작성자 보고·요약이 아니라 현재 head의 실제 diff와 코드다. 변경된 코드(생성물·lock·벤더 파일 제외)를 한 줄씩 읽고, 연결 이슈가 있으면 PR이 주장하는 내용을 이슈 원문과 대조한다.
- **PRR-06** 시작 시 head SHA, base 브랜치, merge-base, 연결 이슈, CI 상태, 충돌 상태를 기록한다. 판정과 리뷰 이벤트는 이 head에만 유효하다.
- **PRR-07** 작성자·수정자·이전 리뷰의 보고는 claim이다. "복원했다", "고쳤다"는 현재 트리와 1차 소스(모듈 캐시의 SDK 타입, upstream 소스, 공식 API, 저장소 Makefile)로 다시 확인한다.

## 3. 문제 실재성과 해결 여부

- **PRR-08** [U] 가장 먼저 판정한다: PR이 해결한다고 주장하는 문제가 실제로 있는가, 재현되는가, 근본 원인은 무엇인가, 이 PR이 그 근본 원인을 고치는가(증상이나 타임아웃만 덮지 않는가).
- **PRR-09** [U] PR을 이슈와 같은 엄격도와 순서로 다룬다. 그 프로젝트에서 이슈를 처리해 온 순서(재현 → 근본 원인 → 해결 적합성 → 코멘트)를 그대로 쓴다. 재현과 claim 판정은 `issue-validation`, 원인 체인을 새로 도출해야 하면 `five-whys-root-cause-analysis`를 호출하고, 절차를 새로 만들지 않는다.
- **PRR-10** [U] 연결 이슈가 없는 PR도 같은 순서로 검증한다. 결과는 그 PR의 코멘트로 남기고, 새 이슈는 사용자가 요청할 때만 만든다.
- **PRR-11** "고친다"는 판정에는 실행 증거가 필요하다. merge-base(또는 PR 적용 전)에서 주장된 실패가 재현되고, PR head(오래됐으면 main 위로 rebase한 것)에서 통과하며, 정상 대조군(healthy control)도 관찰한다. rebase가 충돌하면 head를 그 merge-base 기준으로 검증하고, `PR-ready: false (merge conflict)`로 적고, 겹치는 main 커밋을 나열한다. 일부 claim만 맞는 PR을 전체 해결로 판정하지 않는다. 방법은 `references/review-dimensions.md` §1, claim 판정 어휘는 `references/defaults.md`.

## 4. 리뷰 차원

- **PRR-12** [U] 변경이 다른 regression을 일으킬 수 있는지 코드를 하나하나 읽어 판정한다.
- **PRR-13** [U] 변경이 성능 문제를 일으킬 수 있는지 판정한다.
- **PRR-14** [U] 보안 문제를 판정한다.
- **PRR-15** [U] 구조적 문제(문제에 비해 과하거나 어긋난 변경, 필요한 구조 변경을 피한 국소 패치)를 판정한다.
- **PRR-16** [U] 변경이 프로젝트에 미치는 영향 범위(blast radius)를 판정한다.
- **PRR-17** [U] 이 PR이 현재 main에서 여전히 필요한지 판정한다. 이미 main에 반영됐는지는 간접 머지(커밋이 다른 PR을 통해 들어간 경우)까지 추적한다.
- **PRR-18** PRR-12–PRR-17의 확인 항목과 방법은 `references/review-dimensions.md`의 기본값을 쓴다. 테스트 방어력, 의미 보존, 생성물·공개 계약·CI 게이트, 도메인 불변조건, 의존성 PR, 결정적/일시적 실패, 릴리스 노트·문서 PR의 claim 정확성도 해당될 때 같은 문서대로 본다.
- **PRR-19** 공개 저장소에서 악용 가능한 취약점이나 유출된 비밀을 찾으면 세부를 공개 코멘트에 쓰지 않고 사용자에게 먼저 보고한다. 리뷰 코멘트는 사용자가 비공개 보고 경로를 정한 뒤에 게시한다(`references/review-dimensions.md` §5).
- **PRR-20** 범위 규율을 지킨다. 범위 밖 리팩터링 제안, 스타일·취향 지적, 중복 테스트 지적은 하지 않는다. 이 PR이 들여오지 않은 기존 결함은 finding이 아니라 관찰 사항으로 따로 적는다.

## 5. 증거와 심각도

- **PRR-21** 모든 finding에는 `file:line`(또는 심볼·아티팩트 위치), 결함 메커니즘, 최소 수정안이 있어야 한다. 가능하면 재현 조각(옛 코드 실패, 새 코드 통과)을 붙인다. 실행한 결과, 소스만 읽고 추론한 결과, 측정하지 않은 값을 구분해 표기한다.
- **PRR-22** [U] 심각도는 변경이 프로젝트에 미치는 실제 영향으로 매긴다. 척도는 `isac-consensus`의 정의를 쓰고, PR 리뷰의 보정 방법은 `references/review-dimensions.md` §8.
- **PRR-23** 증거가 반증하면 자기 finding도 철회한다. 다른 리뷰어의 주장도 소스로 확인한 뒤 채택하고, 여러 리뷰어가 같은 결함을 찾으면 한 번만 센다. "기존 코드가 완성돼 있다"는 이유로 현상 유지 편향을 두지 않는다.

## 6. 판정 계약

- **PRR-24** PR 리뷰는 `isac-consensus`의 라운드 판정(`GREEN` 또는 `BLOCKING`)으로 끝나고, 다음 PR 고유 필드를 붙인다:
  - `BLOCKING`이면 P0/P1 finding마다 `file:line`과 수정안.
  - `PR-ready`: `GREEN`이고, 현재 head에서 required check가 통과하고, base와 충돌이 없을 때만 `true`. 아니면 `false`와 이유 한 줄. CI 면제 여부는 판단하지 않고 머지 가드와 사용자에게 넘긴다.
  - 리뷰한 head SHA, CI 상태, 확인했고 문제없던 영역(`Verified`), 확인하지 못한 영역(`Not verified`).

  외부·오래된 PR 감사는 §10 판정 어휘를 함께 쓴다. 매핑은 `references/stale-pr-audit.md`.

## 7. 게시

- **PRR-25** [U] 판정은 라벨이 아니라 GitHub 리뷰 이벤트로 남긴다. `GREEN`은 `gh pr review <N> --approve`, `BLOCKING`(`partially superseded`, `close-without-merge` 포함)은 `--request-changes`, 판정이 아닌 보고(superseded 닫기 안내, 판정 없이 남기는 정보)는 `--comment`다. `GREEN`이지만 `PR-ready: false`(check 실패, 충돌)여도 diff에 blocking finding이 없으면 APPROVE하고 본문 첫 줄에 이유를 적는다. 리뷰 계정이 PR 작성자라서 GitHub가 APPROVE·REQUEST_CHANGES를 거부하면(`gh api user --jq .login`과 PR author 비교) 같은 본문을 `COMMENT`로 남기고, 원래 이벤트를 쓰지 못한 이유를 최종 보고에 적는다. 초안 모드에서는 쓸 이벤트를 초안에 함께 적는다.
- **PRR-26** 코멘트는 판정을 맨 앞에 두고 `references/comment-template.md`의 PR 고유 요소를 담는다. 문체, 위생, 승인 초안 대조, 게시 주체는 `isac-publish`를 따른다.
- **PRR-37** head가 바뀐 뒤의 재리뷰는 새 판정에 맞는 이벤트로 다시 남긴다. 같은 리뷰어의 최신 리뷰가 이전 APPROVE·REQUEST_CHANGES를 대체하므로 이전 리뷰를 따로 dismiss하지 않는다. 재리뷰하지 않을 거면 이전 APPROVE가 새 head를 보증하지 않는다고 최종 보고에 적는다.
- **PRR-28** fork PR의 CI 실패(예: 토큰 권한 부족으로 인한 403)는 PR 결함이라고 말하기 전에 환경·권한 문제인지 먼저 분리하고, 그렇다면 그렇게 보고한다.

## 8. 재리뷰

재리뷰 루프와 head 변경 시 판정 무효화는 `isac-consensus`, 자동 리뷰어 재요청과 대기는 전역 `pull-request-review-guard`를 따른다. PR에 고유한 부분만 둔다.

- **PRR-29** 새 head의 재리뷰 코멘트는 이전 finding마다 새 라인 증거로 Closed/Open을 먼저 표시하고, 그다음 새 finding을 나열한다. 수정이 새 회귀 경로를 만들지 않았는지 §4 회귀 항목을 다시 적용한다. head가 바뀌면 이전 판정과 CI 결과도 무효로 보고 PRR-37대로 다시 남긴다.
- **PRR-30** 문구·범위만 바꾸는 fix-round에서는 판정을 바꾸지 않고 재현도 다시 돌리지 않는다. 원래 모르는 영역에 대해 새 테스트나 근본 원인의 확실성을 새로 요구하지 않는다. 교정은 구체적일 때만 내고 아니면 통과시킨다.

## 9. 사용자 보고(한국어)

- **PRR-31** [U] 여러 PR을 함께 보고할 때는 PR별 판정을 결정 단위로 묶는다. 묶음 어휘(`머지 가능 / 수정 후 머지 / 이미 main 반영·닫기 권장 / 일부만 유효`)는 바꿀 수 있는 기본 형식이다. 각 PR에 핵심 근거 한 줄을 붙이고, "머지 가능"과 "수정 후 머지"가 각각 무엇을 뜻하는지(무엇이 바뀌었고 왜 그 판정이며 무엇이 남았는지) 설명한다. PR 하나만 보고할 때는 그 판정의 의미 설명만 적용한다.
- **PRR-32** [U] main에 남아 있지만 PR 코멘트에만 기록된 문제는 따로 나열한다. 읽기 쉬운 요약과, 재현했다면 재현 정보를 함께 준다. 전달 형태(이슈, 요약 페이지 등)는 그 실행의 사용자 지시를 따른다.

## 10. 외부·오래된 PR 감사

절차, 판정 어휘, 산출물, 닫기 코멘트는 `references/stale-pr-audit.md`.

- **PRR-33** [U] "이미 main에 반영됨(superseded)"은 확실히 증명됐을 때만 판정한다. 증명 절차는 `references/stale-pr-audit.md` 절차 4. 외부 기여자 PR을 superseded로 닫을 때 프로젝트가 릴리스를 배포한다면 수정이 포함된 첫 릴리스 버전을 코멘트에 적는다.
- **PRR-34** [U] 외부 기여자 PR을 superseded로 닫을 때, 판정이 이전 패스에서 나온 것이면 닫기 직전에 현재 main 기준으로 다시 검증하고 확실할 때만 코멘트와 함께 닫는다(닫기 지시가 있을 때, PRR-02). 에이전트나 사용자 자신의 PR을 일회성으로 정리할 때는 제외한다. 코멘트 구성과 자원 정리는 `references/stale-pr-audit.md`.
- **PRR-35** PRR-33 상황에서 수정이 main에만 있고 릴리스가 없으면 버전 대신 "merged but unreleased"라고 적고, 사용자에게 릴리스가 필요하다고 알린다.

## 완료 조건

- 현재 head에 대해 PRR-24 판정, `PR-ready`, 리뷰한 head SHA가 있다.
- 모든 blocking finding에 `file:line`, 메커니즘, 수정안이 있고, 실행 확인과 추론이 구분돼 있다.
- 게시 모드면 현재 head에 대한 리뷰가 하나 있고, 이벤트가 PRR-25의 판정 매핑과 맞는다(작성자 계정이라 COMMENT로 대체했다면 그 사유가 보고에 있다). 초안 모드면 초안, 쓸 이벤트, 게시 가능 안내가 최종 보고에 있다.
- 사용자 보고가 PRR-31, PRR-32 형식을 따른다.

## 교정 루프

결과가 기대와 다르면 사용자는 `isac-correct` 스킬로 이 스킬을 교정할 수 있다. 실행 중 사용자가 교정했다면 최종 보고에 "스킬에 반영하려면 `isac-correct`" 한 줄만 적는다(실행 도중 따로 묻지 않는다). `references/cases.md`는 교정 때만 읽는다.

## References

- `references/review-dimensions.md`: 해결 여부 확인, 영향 범위, 회귀, 성능, 보안 패스, 구조·비례성, 기타 차원, 심각도 보정, 증거 규율.
- `references/comment-template.md`: 리뷰·재리뷰·닫기 코멘트 템플릿, 판정별 리뷰 이벤트와 게시 명령.
- `references/stale-pr-audit.md`: 외부·오래된 PR 감사 절차, superseded 증명, 판정 매핑, 닫기.
- `references/defaults.md`: 리뷰어 관점 프리셋, claim 판정 어휘, 게시·사용자 보고 형식 등 바꿀 수 있는 기본값.
